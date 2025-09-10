// ============================================================================
// Module: command_processor (数据驱动架构)
// ============================================================================
module command_processor#(
        parameter PAYLOAD_ADDR_WIDTH = 8
    )(
        input  wire                           clk,
        input  wire                           rst_n,
        input  wire                           parse_done,
        input  wire [7:0]                     cmd_out,
        input  wire [15:0]                    len_out,
        input  wire [7:0]                     payload_read_data,

        output reg                            led_out,
        output reg [PAYLOAD_ADDR_WIDTH-1:0]   payload_read_addr,

        // 通用指令执行接口
        output reg [7:0]                      cmd_type_out,        // 指令类型
        output reg [15:0]                     cmd_length_out,      // 数据长度
        output reg [7:0]                      cmd_data_out,        // 当前数据字节
        output reg [15:0]                     cmd_data_index_out,  // 数据索引
        output reg                            cmd_start_out,       // 指令开始
        output reg                            cmd_data_valid_out,  // 数据有效
        output reg                            cmd_done_out,        // 指令完成
        
        // 从各功能模块返回的状态
        input  wire                           cmd_ready_in,        // 功能模块就绪
        
        // 数据上传接口 (用于UART接收数据等)
        input  wire                           upload_req_in,       // 上传请求
        input  wire [7:0]                     upload_data_in,      // 上传数据
        input  wire [7:0]                     upload_source_in,    // 上传数据源标识
        input  wire                           upload_valid_in,     // 上传数据有效
        output reg                            upload_ready_out,    // 上传准备就绪
        
        // 到USB FIFO的上传接口
        output reg  [7:0]                     usb_upload_data_out, // USB上传数据
        output reg                            usb_upload_valid_out // USB上传有效
    );

    // 状态机更新：增加两个WAIT状态以匹配payload RAM的2周期读延迟
    localparam IDLE         = 4'b0001;
    localparam SET_ADDR     = 4'b0010;
    localparam WAIT_DATA_1  = 4'b0100;
    localparam WAIT_DATA_2  = 4'b1000;
    localparam GET_DATA     = 4'b1001;

    reg [3:0]  state;
    reg [15:0] data_counter;
    reg [7:0]  current_cmd;
    reg [15:0] current_length;
    
    // 边沿检测
    reg parse_done_d1;
    wire parse_done_edge;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            parse_done_d1 <= 1'b0;
        end
        else begin
            parse_done_d1 <= parse_done;
        end
    end

    assign parse_done_edge = parse_done & ~parse_done_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            led_out <= 1'b0;
            payload_read_addr <= 0;
            data_counter <= 0;
            current_cmd <= 0;
            current_length <= 0;
            
            cmd_type_out <= 0;
            cmd_length_out <= 0;
            cmd_data_out <= 0;
            cmd_data_index_out <= 0;
            cmd_start_out <= 1'b0;
            cmd_data_valid_out <= 1'b0;
            cmd_done_out <= 1'b0;
            
            // 数据上传接口初始化
            upload_ready_out <= 1'b1;
            usb_upload_data_out <= 8'h00;
            usb_upload_valid_out <= 1'b0;
        end
        else begin
            // 默认将脉冲信号拉低
            cmd_start_out <= 1'b0;
            cmd_data_valid_out <= 1'b0;
            cmd_done_out <= 1'b0;
            usb_upload_valid_out <= 1'b0;
            
            // 数据上传处理（优先级高于指令处理）
            if (upload_req_in && upload_valid_in && upload_ready_out) begin
                usb_upload_data_out <= upload_data_in;
                usb_upload_valid_out <= 1'b1;
            end

            case (state)
                IDLE: begin
                    if (parse_done_edge) begin
                        current_cmd <= cmd_out;
                        current_length <= len_out;
                        
                        case (cmd_out)
                            8'hFF: begin // 心跳测试
                                led_out <= ~led_out;
                                cmd_type_out <= cmd_out;
                                cmd_length_out <= 0;
                                cmd_start_out <= 1'b1;
                                cmd_done_out <= 1'b1;
                            end
                            
                            default: begin // 所有其他指令
                                if (len_out > 0) begin
                                    cmd_start_out <= 1'b1;
                                    cmd_type_out <= cmd_out;
                                    cmd_length_out <= len_out;
                                    data_counter <= 0;
                                    state <= SET_ADDR;
                                end
                                else begin // 无数据指令
                                    cmd_type_out <= cmd_out;
                                    cmd_length_out <= 0;
                                    cmd_start_out <= 1'b1;
                                    cmd_done_out <= 1'b1;
                                end
                            end
                        endcase
                    end
                end

                SET_ADDR: begin
                    // 周期 N: 设置地址。地址将在下一个周期出现在输出端口。
                    payload_read_addr <= data_counter;
                    state <= WAIT_DATA_1;
                end

                WAIT_DATA_1: begin
                    // 周期 N+1: 等待地址传播，并让parser的同步RAM开始访问。
                    state <= WAIT_DATA_2;
                end

                WAIT_DATA_2: begin
                    // 周期 N+2: 等待parser将数据锁存到其输出寄存器。
                    state <= GET_DATA;
                end
                
                GET_DATA: begin
                    // 周期 N+3: 数据在 payload_read_data 上已经稳定。
                    if (cmd_ready_in) begin
                        cmd_data_out <= payload_read_data;
                        cmd_data_index_out <= data_counter;
                        cmd_data_valid_out <= 1'b1;

                        if (data_counter < current_length - 1) begin
                            data_counter <= data_counter + 1;
                            state <= SET_ADDR; // 获取下一个字节
                        end else begin
                            cmd_done_out <= 1'b1;
                            state <= IDLE;
                        end
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule