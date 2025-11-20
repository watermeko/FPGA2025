// ============================================================================
// Module: upload_arbiter (带FIFO缓存的数据上传管理器 - 支持数据包完整性)
// Description: 解决多个模块同时上传数据的冲突，数据不丢失
//
// Features:
//   - 每个数据源有独立的FIFO缓存（128深度）
//   - 所有数据先写入FIFO，不会丢失
//   - 按固定优先级从FIFO读取数据上传 (UART > SPI > I2C > SPI_SLAVE > I2C_SLAVE)
//   - **数据包完整性优先**：正在传输的数据包不会被打断
//   - 通过 req 信号识别数据包边界，只在数据包间隙切换源
//
// FIFO架构说明：
//   - 当前使用Verilog实现的同步FIFO
//   - FIFO接口与高云IP核兼容，便于后续移植
//   - 如需更大容量，可替换为高云FIFO IP核
// ============================================================================

module upload_arbiter #(
    parameter NUM_SOURCES = 5,      // 数据源数量(uart, spi, i2c, spi_slave, i2c_slave)
    parameter FIFO_DEPTH = 8      // 每个FIFO的深度（32字节平衡性能与资源） 11/17deleteCLS
)(
    input wire clk,
    input wire rst_n,


    // 来自各个数据源的上传请求
    input  wire [NUM_SOURCES-1:0]       src_upload_req,
    input  wire [NUM_SOURCES*8-1:0]     src_upload_data,
    input  wire [NUM_SOURCES*8-1:0]     src_upload_source,
    input  wire [NUM_SOURCES-1:0]       src_upload_valid,
    output wire [NUM_SOURCES-1:0]       src_upload_ready,

    // 到processor的统一上传接口
    output reg                          merged_upload_req,
    output reg  [7:0]                   merged_upload_data,
    output reg  [7:0]                   merged_upload_source,
    output reg                          merged_upload_valid,
    input  wire                         processor_upload_ready
);

    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH);

    // FIFO读使能控制信号（由状态机控制，避免跨generate块赋值）
    reg [NUM_SOURCES-1:0] fifo_rd_en_ctrl;

    // 为每个源创建FIFO和控制逻辑
    genvar i;
    generate
        for (i = 0; i < NUM_SOURCES; i = i + 1) begin : gen_fifos
            // FIFO存储器（增加req信号存储）
            reg [7:0] fifo_data_mem [0:FIFO_DEPTH-1];
            reg [7:0] fifo_source_mem [0:FIFO_DEPTH-1];
            reg       fifo_req_mem [0:FIFO_DEPTH-1];  // 存储req信号

            // FIFO指针和计数
            reg [ADDR_WIDTH-1:0] wr_ptr;
            reg [ADDR_WIDTH-1:0] rd_ptr;
            reg [ADDR_WIDTH:0]   count;

            // FIFO输出寄存器（同步读）
            reg [7:0] fifo_data_out;
            reg [7:0] fifo_source_out;
            reg       fifo_req_out;  // 输出req信号

            wire fifo_full;
            wire fifo_empty;
            wire fifo_wr_en;
            wire fifo_rd_en;  // 改为wire，从外部控制

            assign fifo_full = (count == FIFO_DEPTH);
            assign fifo_empty = (count == 0);
            assign fifo_wr_en = src_upload_valid[i] && !fifo_full;
            assign src_upload_ready[i] = !fifo_full;
            assign fifo_rd_en = fifo_rd_en_ctrl[i];  // 从外部控制信号获取

            // 写FIFO（同时存储req信号）
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    wr_ptr <= 0;
                end else if (fifo_wr_en) begin
                    fifo_data_mem[wr_ptr] <= src_upload_data[i*8 +: 8];
                    fifo_source_mem[wr_ptr] <= src_upload_source[i*8 +: 8];
                    fifo_req_mem[wr_ptr] <= src_upload_req[i];  // 存储req
                    if (wr_ptr == FIFO_DEPTH - 1)
                        wr_ptr <= 0;
                    else
                        wr_ptr <= wr_ptr + 1;
                end
            end

            // 读FIFO（同步读 - 读使能有效时输出数据并移动指针）
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    rd_ptr <= 0;
                    fifo_data_out <= 8'h00;
                    fifo_source_out <= 8'h00;
                    fifo_req_out <= 1'b0;
                end else if (fifo_rd_en) begin
                    fifo_data_out <= fifo_data_mem[rd_ptr];
                    fifo_source_out <= fifo_source_mem[rd_ptr];
                    fifo_req_out <= fifo_req_mem[rd_ptr];  // 读取req
                    if (rd_ptr == FIFO_DEPTH - 1)
                        rd_ptr <= 0;
                    else
                        rd_ptr <= rd_ptr + 1;
                end
            end

            // FIFO计数
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    count <= 0;
                end else begin
                    case ({fifo_wr_en, fifo_rd_en})
                        2'b10: count <= count + 1;
                        2'b01: count <= count - 1;
                        default: count <= count;
                    endcase
                end
            end
        end
    endgenerate

    // 调度状态机
    localparam IDLE = 2'd0;
    localparam READ_FIFO = 2'd1;
    localparam UPLOAD = 2'd2;

    reg [1:0] state;
    reg [2:0] current_source;  // 3位支持5个源(0-4)
    reg       in_packet;  // 标记是否正在传输数据包 (req=1)

    // 优先级抢占控制变量（声明在always块外）
    integer k;  // 使用 integer 用于 for 循环（综合工具会自动优化位宽）
    reg found_higher_priority;

    // 检查各FIFO是否有数据
    wire [NUM_SOURCES-1:0] fifo_has_data;
    generate
        for (i = 0; i < NUM_SOURCES; i = i + 1) begin : gen_status
            assign fifo_has_data[i] = !gen_fifos[i].fifo_empty;
        end
    endgenerate

    // 仲裁逻辑：固定优先级（根据NUM_SOURCES动态调整）
    // 优先级: 源0 > 源1 > 源2 > 源3 > 源4 (UART > SPI > I2C > SPI_SLAVE > I2C_SLAVE)
    integer j;
    reg [2:0] next_source_reg;  // 3位支持5个源(0-4)
    always @(*) begin
        next_source_reg = 0;
        for (j = NUM_SOURCES - 1; j >= 0; j = j - 1) begin
            if (fifo_has_data[j])
                next_source_reg = j;
        end
    end
    wire [2:0] next_source;  // 3位支持5个源(0-4)
    assign next_source = next_source_reg;

    // 状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_source <= 3'd0;  // 3位初始值
            in_packet <= 1'b0;  // 初始化数据包状态
            merged_upload_req <= 1'b0;
            merged_upload_data <= 8'h00;
            merged_upload_source <= 8'h00;
            merged_upload_valid <= 1'b0;

            // 清除所有FIFO读使能
            fifo_rd_en_ctrl <= {NUM_SOURCES{1'b0}};
        end else begin
            // 默认清除
            fifo_rd_en_ctrl <= {NUM_SOURCES{1'b0}};

            case (state)
                IDLE: begin
                    merged_upload_req <= 1'b0;
                    merged_upload_valid <= 1'b0;

                    if (|fifo_has_data) begin
                        current_source <= next_source;

                        // 立即发起FIFO读操作
                        fifo_rd_en_ctrl[next_source] <= 1'b1;

                        state <= READ_FIFO;
                    end
                end

                READ_FIFO: begin
                    // 等待FIFO数据读出（需要1个周期）
                    merged_upload_req <= 1'b1;

                    // FIFO数据已经出来，进入UPLOAD状态
                    state <= UPLOAD;
                end

                UPLOAD: begin
                    // FIFO数据已经在输出寄存器中，等待握手
                    merged_upload_req <= 1'b1;

                    // 只在进入UPLOAD状态的第一个周期输出数据和valid
                    if (!merged_upload_valid) begin
                        // 使用case语句动态选择FIFO输出
                        case (current_source)
                            3'd0: begin
                                merged_upload_data <= gen_fifos[0].fifo_data_out;
                                merged_upload_source <= gen_fifos[0].fifo_source_out;
                                in_packet <= gen_fifos[0].fifo_req_out;
                            end
                            3'd1: begin
                                merged_upload_data <= gen_fifos[1].fifo_data_out;
                                merged_upload_source <= gen_fifos[1].fifo_source_out;
                                in_packet <= gen_fifos[1].fifo_req_out;
                            end
                            3'd2: begin
                                merged_upload_data <= gen_fifos[2].fifo_data_out;
                                merged_upload_source <= gen_fifos[2].fifo_source_out;
                                in_packet <= gen_fifos[2].fifo_req_out;
                            end
                            3'd3: begin
                                merged_upload_data <= gen_fifos[3].fifo_data_out;
                                merged_upload_source <= gen_fifos[3].fifo_source_out;
                                in_packet <= gen_fifos[3].fifo_req_out;
                            end
                            3'd4: begin
                                merged_upload_data <= gen_fifos[4].fifo_data_out;
                                merged_upload_source <= gen_fifos[4].fifo_source_out;
                                in_packet <= gen_fifos[4].fifo_req_out;
                            end
                            default: begin
                                merged_upload_data <= 8'h00;
                                merged_upload_source <= 8'h00;
                                in_packet <= 1'b0;
                            end
                        endcase
                        merged_upload_valid <= 1'b1;
                    end

                    if (processor_upload_ready && merged_upload_valid) begin
                        // 握手成功，检查是否继续读取当前源
                        merged_upload_valid <= 1'b0;

                        // **关键修改**：只在数据包间隙（in_packet=0）才允许优先级抢占
                        // 检查是否有更高优先级的源有数据
                        found_higher_priority = 0;

                        if (!in_packet) begin
                            // 数据包已结束，检查更高优先级的源
                            for (k = 0; k < current_source; k = k + 1) begin
                                if ((k < NUM_SOURCES) && fifo_has_data[k[2:0]] && !found_higher_priority) begin
                                    current_source <= k[2:0];
                                    fifo_rd_en_ctrl[k[2:0]] <= 1'b1;
                                    state <= READ_FIFO;
                                    found_higher_priority = 1;
                                end
                            end
                        end

                        if (!found_higher_priority) begin
                            // 继续读取当前源，或在当前源为空时返回IDLE
                            if (fifo_has_data[current_source]) begin
                                fifo_rd_en_ctrl[current_source] <= 1'b1;
                                state <= READ_FIFO;
                            end else begin
                                in_packet <= 1'b0;  // 清除数据包状态
                                state <= IDLE;
                            end
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
