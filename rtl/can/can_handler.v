`timescale 1ns / 1ps
// ============================================================================
// Module: can_handler
// Description: CAN总线处理器，连接command_processor和can_top核心
// ============================================================================
module can_handler (
    input  wire        clk,
    input  wire        rst_n,

    // 命令总线接口（与command_processor对接）
    input  wire [7:0]  cmd_type,
    input  wire [15:0] cmd_length,
    input  wire [7:0]  cmd_data,
    input  wire [15:0] cmd_data_index,
    input  wire        cmd_start,
    input  wire        cmd_data_valid,
    input  wire        cmd_done,
    output reg         cmd_ready,

    // CAN物理接口
    input  wire        can_rx,
    output wire        can_tx,

    // 数据上传接口（接收到的CAN数据通过USB上传）
    output wire        upload_active,
    output reg         upload_req,
    output reg  [7:0]  upload_data,
    output reg  [7:0]  upload_source,
    output reg         upload_valid,
    input  wire        upload_ready
);

    // ========================================================================
    // 命令定义
    // ========================================================================
    localparam CMD_CAN_CONFIG = 8'h27;  // 配置CAN（波特率、ID过滤器）
    localparam CMD_CAN_TX     = 8'h28;  // 发送CAN数据帧
    localparam CMD_CAN_RX     = 8'h29;  // 读取CAN接收数据

    // 上传数据源标识
    localparam UPLOAD_SOURCE_CAN = 8'h11;

    // ========================================================================
    // 状态机定义
    // ========================================================================
    localparam IDLE           = 3'd0;
    localparam RX_CONFIG      = 3'd1;
    localparam UPDATE_CFG     = 3'd2;
    localparam RX_TX_DATA     = 3'd3;
    localparam WAIT_TX_READY  = 3'd4;
    localparam HANDLE_RX      = 3'd5;
    localparam UPLOAD         = 3'd6;

    reg [2:0] handler_state;

    // 上传状态机
    localparam UP_IDLE = 2'd0;
    localparam UP_SEND = 2'd1;
    localparam UP_WAIT = 2'd2;

    reg [1:0] upload_state;

    // ========================================================================
    // CAN配置寄存器
    // ========================================================================
    reg [10:0] local_id;              // 本地发送ID（11位）
    reg [10:0] rx_id_short_filter;    // 短ID过滤器
    reg [10:0] rx_id_short_mask;      // 短ID掩码
    reg [28:0] rx_id_long_filter;     // 长ID过滤器（29位）
    reg [28:0] rx_id_long_mask;       // 长ID掩码
    reg [15:0] c_pts;                 // 时序参数：传播段
    reg [15:0] c_pbs1;                // 时序参数：相位段1
    reg [15:0] c_pbs2;                // 时序参数：相位段2

    // 临时存储配置数据
    reg [7:0] config_data [0:15];

    // ========================================================================
    // 发送缓冲区（32字节足够大多数应用）
    // ========================================================================
    localparam TX_BUFFER_SIZE = 16;
    reg [7:0]  tx_buffer [0:TX_BUFFER_SIZE-1];
    reg [15:0] tx_data_count;
    reg [4:0]  tx_write_ptr;
    reg [3:0]  tx_data_len;  // 实际发送长度（1-4字节）

    // ========================================================================
    // 接收缓冲区（64字节）
    // ========================================================================
    localparam RX_BUFFER_SIZE = 16;
    reg [7:0]  rx_buffer [0:RX_BUFFER_SIZE-1];
    reg [7:0]  rx_write_ptr;
    reg [7:0]  rx_read_ptr;
    reg [8:0]  rx_count;
    wire       rx_buffer_full;
    wire       rx_buffer_empty;

    assign rx_buffer_full  = (rx_count == RX_BUFFER_SIZE);
    assign rx_buffer_empty = (rx_count == 0);

    // ========================================================================
    // CAN核心接口信号
    // ========================================================================
    reg        can_tx_valid;
    reg [31:0] can_tx_data;
    reg [3:0]  can_tx_len;   // 发送长度（1-4字节）
    wire       can_tx_ready;

    wire       can_rx_valid;
    wire       can_rx_last;
    wire [7:0] can_rx_data;
    wire [28:0] can_rx_id;
    wire       can_rx_ide;

    reg [7:0]  upload_index;

    // Upload active signal
    assign upload_active = (handler_state == UPLOAD);

    // ========================================================================
    // 主状态机
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            handler_state <= IDLE;
            cmd_ready <= 1'b1;
            tx_data_count <= 0;
            tx_write_ptr <= 0;
            tx_data_len <= 4'd4;  // 默认4字节
            can_tx_valid <= 1'b0;
            can_tx_data <= 32'h0;
            can_tx_len <= 4'd4;   // 默认4字节

            // 默认配置（CAN 1MHz @ 60MHz系统时钟）
            local_id <= 11'h001;
            rx_id_short_filter <= 11'h002;
            rx_id_short_mask   <= 11'h7FF;  // 精确匹配
            rx_id_long_filter  <= 29'h12345678;
            rx_id_long_mask    <= 29'h1FFFFFFF; // 精确匹配
            c_pts  <= 16'd34;   // 对于1MHz CAN @ 60MHz clk
            c_pbs1 <= 16'd5;
            c_pbs2 <= 16'd10;
        end else begin
            // 默认拉低单周期脉冲
            can_tx_valid <= 1'b0;

            case (handler_state)
                IDLE: begin
                    cmd_ready <= 1'b1;
                    if (cmd_start) begin
                        case (cmd_type)
                            CMD_CAN_CONFIG: begin
                                handler_state <= RX_CONFIG;
                                $display("[%0t] CAN_HANDLER: Received CONFIG command", $time);
                            end

                            CMD_CAN_TX: begin
                                handler_state <= RX_TX_DATA;
                                tx_data_count <= 0;
                                tx_write_ptr <= 0;
                                // 根据cmd_length设置发送长度，限制为1-4字节
                                if (cmd_length == 0 || cmd_length > 4)
                                    tx_data_len <= 4'd4;  // 默认4字节
                                else
                                    tx_data_len <= cmd_length[3:0];
                                // 清空发送缓冲区，避免残留数据
                                tx_buffer[0] <= 8'h00;
                                tx_buffer[1] <= 8'h00;
                                tx_buffer[2] <= 8'h00;
                                tx_buffer[3] <= 8'h00;
                                $display("[%0t] CAN_HANDLER: Received TX command, length=%0d", $time, cmd_length);
                            end

                            CMD_CAN_RX: begin
                                handler_state <= HANDLE_RX;
                                $display("[%0t] CAN_HANDLER: Received RX command, rx_count=%0d", $time, rx_count);
                            end

                            default: begin
                                handler_state <= IDLE;
                            end
                        endcase
                    end
                end

                // 接收配置数据
                RX_CONFIG: begin
                    cmd_ready <= 1'b1;
                    if (cmd_data_valid && cmd_data_index < 16) begin
                        config_data[cmd_data_index] <= cmd_data;
                        $display("[%0t] CAN_HANDLER: Config data[%0d] = 0x%02x", $time, cmd_data_index, cmd_data);
                    end
                    if (cmd_done) begin
                        handler_state <= UPDATE_CFG;
                    end
                end

                // 更新配置寄存器
                UPDATE_CFG: begin
                    // 配置帧格式（16字节）：
                    // [0:1]   local_id (11位，低字节在前)
                    // [2:3]   rx_id_short_filter
                    // [4:5]   rx_id_short_mask
                    // [6:9]   rx_id_long_filter (29位)
                    // [10:13] rx_id_long_mask
                    // [14:15] c_pts (时序参数)
                    // 可选：[16:17] c_pbs1, [18:19] c_pbs2

                    $display("[%0t] CAN_HANDLER: *** ENTERING UPDATE_CFG STATE ***", $time);
                    $display("  config_data[0]=0x%02x [1]=0x%02x", config_data[0], config_data[1]);
                    $display("  config_data[2]=0x%02x [3]=0x%02x", config_data[2], config_data[3]);
                    $display("  config_data[4]=0x%02x [5]=0x%02x", config_data[4], config_data[5]);
                    $display("  Current rx_id_short_filter=0x%03x", rx_id_short_filter);
                    $display("  Will set to: 0x%03x", {3'b0, config_data[3][2:0], config_data[2]});

                    local_id <= {3'b0, config_data[1][2:0], config_data[0]};
                    rx_id_short_filter <= {3'b0, config_data[3][2:0], config_data[2]};
                    rx_id_short_mask   <= {3'b0, config_data[5][2:0], config_data[4]};
                    rx_id_long_filter  <= {config_data[9][4:0], config_data[8], config_data[7], config_data[6]};
                    rx_id_long_mask    <= {config_data[13][4:0], config_data[12], config_data[11], config_data[10]};
                    c_pts  <= {config_data[15], config_data[14]};

                    $display("[%0t] CAN_HANDLER: Updated config: local_id=0x%03x, filter=0x%03x",
                             $time, {3'b0, config_data[1][2:0], config_data[0]},
                             {3'b0, config_data[3][2:0], config_data[2]});

                    handler_state <= IDLE;
                end

                // 接收发送数据
                RX_TX_DATA: begin
                    if (cmd_data_valid && tx_write_ptr < TX_BUFFER_SIZE) begin
                        tx_buffer[tx_write_ptr] <= cmd_data;
                        tx_write_ptr <= tx_write_ptr + 1;
                        tx_data_count <= tx_data_count + 1;
                        $display("[%0t] CAN_HANDLER: Stored tx_buffer[%0d] = 0x%02x", $time, tx_write_ptr, cmd_data);
                    end

                    if (cmd_done && !cmd_data_valid) begin
                        // cmd_done单独出现，说明数据已接收完毕
                        // 数据应该已经由上层对齐好了，按大端序组装
                        can_tx_data <= {tx_buffer[0], tx_buffer[1], tx_buffer[2], tx_buffer[3]};
                        can_tx_len <= tx_data_len;  // 使用实际长度
                        can_tx_valid <= 1'b1;
                        handler_state <= WAIT_TX_READY;
                        $display("[%0t] CAN_HANDLER: Sending CAN frame (%0d bytes): 0x%02x%02x%02x%02x",
                                 $time, tx_data_len, tx_buffer[0], tx_buffer[1], tx_buffer[2], tx_buffer[3]);
                    end else if (cmd_done && cmd_data_valid) begin
                        // cmd_done和cmd_data_valid同时出现，最后一个字节刚到达
                        // 需要等待一个周期让数据写入tx_buffer
                        handler_state <= WAIT_TX_READY;
                        $display("[%0t] CAN_HANDLER: Last byte received, waiting one cycle", $time);
                    end
                end

                // 等待CAN核心准备好
                WAIT_TX_READY: begin
                    if (can_tx_valid) begin
                        // 已经发起发送，等待can_tx_ready
                        if (can_tx_ready) begin
                            handler_state <= IDLE;
                            $display("[%0t] CAN_HANDLER: TX complete", $time);
                        end
                    end else begin
                        // 这是从RX_TX_DATA延迟过来的，现在发送数据
                        // 数据应该已经由上层对齐好了，按大端序组装
                        can_tx_data <= {tx_buffer[0], tx_buffer[1], tx_buffer[2], tx_buffer[3]};
                        can_tx_len <= tx_data_len;  // 使用实际长度
                        can_tx_valid <= 1'b1;
                        $display("[%0t] CAN_HANDLER: Sending CAN frame (delayed, %0d bytes): 0x%02x%02x%02x%02x",
                                 $time, tx_data_len, tx_buffer[0], tx_buffer[1], tx_buffer[2], tx_buffer[3]);
                    end
                end

                // 处理接收请求
                HANDLE_RX: begin
                    if (!rx_buffer_empty) begin
                        upload_index <= 0;
                        handler_state <= UPLOAD;
                    end else begin
                        handler_state <= IDLE;
                    end
                end

                // 上传接收数据
                UPLOAD: begin
                    if (rx_buffer_empty) begin
                        handler_state <= IDLE;
                    end
                end

                default: handler_state <= IDLE;
            endcase
        end
    end

    // ========================================================================
    // 接收数据写入缓冲区
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_write_ptr <= 0;
            rx_read_ptr <= 0;
            rx_count <= 0;
        end else begin
            // 写入逻辑
            if (can_rx_valid && !rx_buffer_full) begin
                rx_buffer[rx_write_ptr] <= can_rx_data;
                rx_write_ptr <= rx_write_ptr + 1;
                rx_count <= rx_count + 1;
                $display("[%0t] CAN_HANDLER: RX data[%0d] = 0x%02x (ID=0x%07x, IDE=%0d)",
                         $time, rx_write_ptr, can_rx_data, can_rx_id, can_rx_ide);
            end

            // 读出逻辑（通过上传状态机控制）
            if ((upload_state == UP_SEND) && upload_ready && !rx_buffer_empty) begin
                rx_read_ptr <= rx_read_ptr + 1;
                rx_count <= rx_count - 1;
            end
        end
    end

    // ========================================================================
    // 上传状态机（独立控制）
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            upload_state <= UP_IDLE;
            upload_req <= 1'b0;
            upload_data <= 8'h00;
            upload_source <= UPLOAD_SOURCE_CAN;
            upload_valid <= 1'b0;
        end else begin
            case (upload_state)
                UP_IDLE: begin
                    if ((handler_state == UPLOAD) && !rx_buffer_empty && upload_ready) begin
                        upload_req <= 1'b1;
                        upload_data <= rx_buffer[rx_read_ptr];
                        upload_source <= UPLOAD_SOURCE_CAN;
                        upload_valid <= 1'b1;
                        upload_state <= UP_SEND;
                        $display("[%0t] CAN_HANDLER: Upload byte = 0x%02x", $time, rx_buffer[rx_read_ptr]);
                    end else begin
                        upload_req <= 1'b0;
                        upload_valid <= 1'b0;
                    end
                end

                UP_SEND: begin
                    upload_valid <= 1'b0;  // 单周期脉冲
                    if (upload_ready) begin
                        upload_state <= UP_WAIT;
                    end
                end

                UP_WAIT: begin
                    upload_req <= 1'b0;
                    upload_valid <= 1'b0;
                    if (!rx_buffer_empty && upload_ready) begin
                        upload_state <= UP_IDLE;
                    end else if (rx_buffer_empty) begin
                        upload_state <= UP_IDLE;
                    end
                end

                default: begin
                    upload_state <= UP_IDLE;
                    upload_req <= 1'b0;
                    upload_valid <= 1'b0;
                end
            endcase
        end
    end

    // ========================================================================
    // CAN核心实例化
    // ========================================================================
    can_top #(
        .LOCAL_ID           (11'h001),           // 默认值（可被运行时配置覆盖）集成测试配置
        .RX_ID_SHORT_FILTER (11'h002),           // 改为0x002，接收CAN2的帧
        .RX_ID_SHORT_MASK   (11'h7FF),
        .RX_ID_LONG_FILTER  (29'h12345678),
        .RX_ID_LONG_MASK    (29'h1FFFFFFF),
        .default_c_PTS      (16'd34),            // 1MHz @ 60MHz
        .default_c_PBS1     (16'd5),
        .default_c_PBS2     (16'd10)
    ) u_can_top (
        .rstn               (rst_n),
        .clk                (clk),

        // 运行时配置（连接到寄存器）
        .cfg_override_en    (1'b1),                    // 始终使用运行时配置
        .cfg_local_id       (local_id),
        .cfg_rx_filter_short(rx_id_short_filter),
        .cfg_rx_mask_short  (rx_id_short_mask),
        .cfg_rx_filter_long (rx_id_long_filter),
        .cfg_rx_mask_long   (rx_id_long_mask),
        .cfg_c_pts          (c_pts),
        .cfg_c_pbs1         (c_pbs1),
        .cfg_c_pbs2         (c_pbs2),

        // CAN PHY接口
        .can_rx             (can_rx),
        .can_tx             (can_tx),

        // 发送接口
        .tx_valid           (can_tx_valid),
        .tx_data            (can_tx_data),
        .tx_len             (can_tx_len),    // 添加长度接口
        .tx_ready           (can_tx_ready),

        // 接收接口
        .rx_valid           (can_rx_valid),
        .rx_last            (can_rx_last),
        .rx_data            (can_rx_data),
        .rx_id              (can_rx_id),
        .rx_ide             (can_rx_ide)
    );

endmodule
