`timescale 1ns / 1ps
// ============================================================================
// CAN Handler Testbench - Full CAN Communication Test
// Tests can_handler with can_top peer device
// ============================================================================

module can_handler_tb;

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam CLK_FREQ      = 60_000_000;  // 60MHz system clock
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;  // ~16.67ns

    // CAN命令定义 (必须与can_handler.v中的定义一致)
    localparam CMD_CAN_CONFIG = 8'h27;
    localparam CMD_CAN_TX     = 8'h28;
    localparam CMD_CAN_RX     = 8'h29;

    // ========================================================================
    // Signals
    // ========================================================================
    reg         clk;
    reg         rst_n;

    // CAN Handler命令接口
    reg  [7:0]  cmd_type;
    reg  [15:0] cmd_length;
    reg  [7:0]  cmd_data;
    reg  [15:0] cmd_data_index;
    reg         cmd_start;
    reg         cmd_data_valid;
    reg         cmd_done;
    wire        cmd_ready;

    // CAN物理总线
    tri         can_bus;
    wire        handler_can_tx;
    wire        handler_can_rx;
    wire        peer_can_tx;
    wire        peer_can_rx;

    // CAN总线仲裁（tri-state + pullup模拟wired-AND，总线默认隐性态=1）
    pullup(can_bus);

    // CAN PHY模拟 (类似TJA1050) - 使用模块实例
    tb_can_phy handler_phy(.can_tx(handler_can_tx), .can_rx(handler_can_rx), .can_bus(can_bus));
    tb_can_phy peer_phy(.can_tx(peer_can_tx), .can_rx(peer_can_rx), .can_bus(can_bus));

    // CAN Handler上传接口
    wire        upload_active;
    wire        upload_req;
    wire [7:0]  upload_data;
    wire [7:0]  upload_source;
    wire        upload_valid;
    reg         upload_ready;

    // CAN对端设备接口
    reg         peer_tx_valid;
    wire        peer_tx_ready;
    reg  [63:0] peer_tx_data;
    reg  [ 3:0] peer_tx_len;

    wire        peer_rx_valid;
    wire        peer_rx_last;
    wire [7:0]  peer_rx_data;
    wire [28:0] peer_rx_id;
    wire        peer_rx_ide;

    integer i;

    // ========================================================================
    // DUT: can_handler
    // ========================================================================
    can_handler u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .cmd_type         (cmd_type),
        .cmd_length       (cmd_length),
        .cmd_data         (cmd_data),
        .cmd_data_index   (cmd_data_index),
        .cmd_start        (cmd_start),
        .cmd_data_valid   (cmd_data_valid),
        .cmd_done         (cmd_done),
        .cmd_ready        (cmd_ready),
        .can_rx           (handler_can_rx),
        .can_tx           (handler_can_tx),
        .upload_active    (upload_active),
        .upload_req       (upload_req),
        .upload_data      (upload_data),
        .upload_source    (upload_source),
        .upload_valid     (upload_valid),
        .upload_ready     (upload_ready)
    );

    // ========================================================================
    // Peer Device: can_top (对端CAN设备)
    // ========================================================================
    can_top #(
        .LOCAL_ID           (11'h002),           // 对端ID = 0x002
        .RX_ID_SHORT_FILTER (11'h001),           // 接收ID = 0x001 (来自handler)
        .RX_ID_SHORT_MASK   (11'h7FF),
        .default_c_PTS      (16'd34),
        .default_c_PBS1     (16'd5),
        .default_c_PBS2     (16'd10)
    ) u_can_peer (
        .rstn               (rst_n),
        .clk                (clk),
        .cfg_override_en    (1'b1),              // 启用运行时配置覆盖
        .cfg_local_id       (11'h002),           // Peer发送ID = 0x002
        .cfg_rx_filter_short(11'h001),           // 接收Handler的帧
        .cfg_rx_mask_short  (11'h7FF),
        .cfg_rx_filter_long (29'h0),
        .cfg_rx_mask_long   (29'h0),
        .cfg_c_pts          (16'd34),
        .cfg_c_pbs1         (16'd5),
        .cfg_c_pbs2         (16'd10),
        .can_rx             (peer_can_rx),
        .can_tx             (peer_can_tx),
        .tx_valid           (peer_tx_valid),
        .tx_ready           (peer_tx_ready),
        .tx_data            (peer_tx_data),
        .tx_len             (peer_tx_len),
        .rx_valid           (peer_rx_valid),
        .rx_last            (peer_rx_last),
        .rx_data            (peer_rx_data),
        .rx_id              (peer_rx_id),
        .rx_ide             (peer_rx_ide)
    );

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    // ========================================================================
    // Reset and Initialization
    // ========================================================================
    initial begin
        rst_n = 1'b0;
        cmd_type = 0;
        cmd_length = 0;
        cmd_data = 0;
        cmd_data_index = 0;
        cmd_start = 0;
        cmd_data_valid = 0;
        cmd_done = 0;
        upload_ready = 1'b1;

        peer_tx_valid = 1'b0;
        peer_tx_data = 64'h0;
        peer_tx_len = 4'd0;

        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1;
        $display("[%0t] Reset released", $time);
    end

    // ========================================================================
    // Task: Send Command to CAN Handler
    // ========================================================================
    task send_can_config;
        input [10:0] local_id;
        input [10:0] rx_filter;
        input [10:0] rx_mask;
        begin
            $display("\n[%0t] === Sending CAN CONFIG Command ===", $time);
            $display("  Local ID: 0x%03x", local_id);
            $display("  RX Filter: 0x%03x", rx_filter);
            $display("  RX Mask: 0x%03x", rx_mask);

            cmd_type = CMD_CAN_CONFIG;
            cmd_length = 16'd16;
            cmd_start = 1;
            @(posedge clk);
            cmd_start = 0;
            @(posedge clk);

            // 发送配置数据
            for (i = 0; i < 16; i = i + 1) begin
                cmd_data_index = i;
                cmd_data_valid = 1;

                case (i)
                    0: cmd_data = local_id[7:0];
                    1: cmd_data = {5'b0, local_id[10:8]};
                    2: cmd_data = rx_filter[7:0];
                    3: cmd_data = {5'b0, rx_filter[10:8]};
                    4: cmd_data = rx_mask[7:0];
                    5: cmd_data = {5'b0, rx_mask[10:8]};
                    14: cmd_data = 8'd34;  // c_pts低字节
                    15: cmd_data = 8'd0;   // c_pts高字节
                    default: cmd_data = 8'h0;
                endcase

                @(posedge clk);
                cmd_data_valid = 0;
                @(posedge clk);
            end

            cmd_done = 1;
            @(posedge clk);
            cmd_done = 0;
            @(posedge clk);

            $display("[%0t] CAN CONFIG sent", $time);
        end
    endtask

    task send_can_tx;
        input [63:0] data;
        input [ 3:0] len;  // 数据长度: 1-8
        integer actual_len;
        begin
            actual_len = (len > 8) ? 8 : ((len == 0) ? 4 : len);

            $display("\n[%0t] === Sending CAN TX Command ===", $time);
            $display("  Data: 0x%016x (Length: %0d bytes - NO ALIGNMENT)", data, actual_len);

            cmd_type = CMD_CAN_TX;
            cmd_length = actual_len;
            cmd_start = 1;
            @(posedge clk);
            cmd_start = 0;
            @(posedge clk);

            // 直接发送原始数据，高字节先发送（大端序）
            for (i = 0; i < 4; i = i + 1) begin
                cmd_data_index = i;
                // 从高字节到低字节发送：byte3, byte2, byte1, byte0
                cmd_data = data[(3-i)*8 +: 8];
                cmd_data_valid = 1;
                @(posedge clk);
                cmd_data_valid = 0;
                @(posedge clk);
            end

            cmd_done = 1;
            @(posedge clk);
            cmd_done = 0;
            @(posedge clk);

            $display("[%0t] CAN TX command sent (%0d bytes)", $time, actual_len);
        end
    endtask

    task send_can_rx_request;
        begin
            $display("\n[%0t] === Sending CAN RX Request ===", $time);

            cmd_type = CMD_CAN_RX;
            cmd_length = 16'd0;
            cmd_start = 1;
            @(posedge clk);
            cmd_start = 0;
            @(posedge clk);

            cmd_done = 1;
            @(posedge clk);
            cmd_done = 0;
            @(posedge clk);

            $display("[%0t] CAN RX request sent", $time);
        end
    endtask

    // ========================================================================
    // Task: Peer Device Send CAN Frame
    // ========================================================================
    task peer_send_frame;
        input [63:0] data;
        input [ 3:0] len;
        begin
            $display("\n[%0t] === Peer Sending CAN Frame ===", $time);
            $display("  Data: 0x%016x (Length: %0d bytes)", data, len);

            peer_tx_data = data;
            peer_tx_len = len;
            peer_tx_valid = 1'b1;
            @(posedge clk);

            wait(peer_tx_ready);
            @(posedge clk);
            peer_tx_valid = 1'b0;

            $display("[%0t] Peer frame queued", $time);
        end
    endtask

    // ========================================================================
    // Monitor: Upload Data
    // ========================================================================
    always @(posedge clk) begin
        if (upload_valid && upload_ready) begin
            $display("[%0t] UPLOAD: source=0x%02x, data=0x%02x",
                     $time, upload_source, upload_data);
        end
    end

    // ========================================================================
    // Monitor: Peer RX Data
    // ========================================================================
    always @(posedge clk) begin
        if (peer_rx_valid) begin
            $display("[%0t] PEER RX: id=0x%03x, data=0x%02x, last=%b",
                     $time, peer_rx_id, peer_rx_data, peer_rx_last);
        end
    end

    // ========================================================================
    // Monitor: Handler RX Buffer Status (调试用)
    // ========================================================================
    always @(posedge clk) begin
        // 监控Handler的RX FIFO写入
        if (u_dut.can_rx_valid) begin
            $display("[%0t] HANDLER RX: can_rx_valid=1, data=0x%02x, id=0x%03x, rx_count=%0d, buffer_full=%b",
                     $time, u_dut.can_rx_data, u_dut.can_rx_id[10:0], u_dut.rx_count, u_dut.rx_buffer_full);
        end

        // 监控Handler can_top内部的pkt_rx_ack信号（关键！）
        if (u_dut.u_can_top.pkt_rx_ack) begin
            $display("[%0t] CAN_TOP (Handler): pkt_rx_ack=1, pkt_rx_id=0x%03x, pkt_rx_ide=%b",
                     $time, u_dut.u_can_top.pkt_rx_id[10:0], u_dut.u_can_top.pkt_rx_ide);
        end

        // 监控Handler packet level RX
        if (u_dut.u_can_top.u_can_level_packet.rx_valid) begin
            $display("[%0t] CAN_LEVEL_PACKET (Handler): rx_valid=1, rx_id=0x%07x, rx_ide=%b, rx_len=%0d",
                     $time, u_dut.u_can_top.u_can_level_packet.rx_id,
                     u_dut.u_can_top.u_can_level_packet.rx_ide,
                     u_dut.u_can_top.u_can_level_packet.rx_len);
        end

        // 监控Peer can_top的TX活动
        if (u_can_peer.pkt_txing) begin
            $display("[%0t] CAN_TOP (Peer): pkt_txing=1, 正在发送CAN帧",
                     $time);
        end
    end

    // ========================================================================
    // Monitor: Handler CAN Top Configuration (调试用)
    // ========================================================================
    initial begin
        #(CLK_PERIOD_NS * 5000);  // 在配置完成后打印
        $display("\n[%0t] === Handler CAN Top Config ===", $time);
        $display("  cfg_override_en: %b", u_dut.u_can_top.cfg_override_en);
        $display("  local_id_actual: 0x%03x", u_dut.u_can_top.local_id_actual);
        $display("  rx_filter_short_actual: 0x%03x", u_dut.u_can_top.rx_filter_short_actual);
        $display("  rx_mask_short_actual: 0x%03x", u_dut.u_can_top.rx_mask_short_actual);
        $display("  Handler local_id reg: 0x%03x", u_dut.local_id);
        $display("  Handler rx_id_short_filter reg: 0x%03x", u_dut.rx_id_short_filter);
        $display("  Handler rx_id_short_mask reg: 0x%03x", u_dut.rx_id_short_mask);
        $display("================================\n");

        $display("[%0t] === Peer CAN Top Config ===", $time);
        $display("  cfg_override_en: %b", u_can_peer.cfg_override_en);
        $display("  local_id_actual: 0x%03x (Peer TX ID)", u_can_peer.local_id_actual);
        $display("  rx_filter_short_actual: 0x%03x", u_can_peer.rx_filter_short_actual);
        $display("  rx_mask_short_actual: 0x%03x", u_can_peer.rx_mask_short_actual);
        $display("================================\n");

        // Monitor rx_id_short_filter and handler_state changes
        $monitor("[%0t] MON: handler_state=%0d, rx_id_short_filter=0x%03x, local_id=0x%03x",
                 $time, u_dut.handler_state, u_dut.rx_id_short_filter, u_dut.local_id);
    end

    // ========================================================================
    // Monitor: Handler Upload State (调试用)
    // ========================================================================
    always @(posedge clk) begin
        if (u_dut.handler_state == 6) begin  // UPLOAD state
            $display("[%0t] HANDLER STATE: UPLOAD, upload_state=%0d, rx_count=%0d, upload_valid=%b, upload_ready=%b",
                     $time, u_dut.upload_state, u_dut.rx_count, upload_valid, upload_ready);
        end

        // 监控upload状态机变化
        if (u_dut.upload_state == 1) begin  // UP_SEND state
            $display("[%0t] UPLOAD STATE: UP_SEND, upload_req=%b, upload_data=0x%02x, upload_valid=%b, upload_ready=%b",
                     $time, upload_req, upload_data, upload_valid, upload_ready);
        end
    end

    // ========================================================================
    // Monitor: CAN Bus Activity (调试用)
    // ========================================================================
    reg [31:0] can_bus_transition_count;
    reg last_can_bus;

    initial begin
        can_bus_transition_count = 0;
        last_can_bus = 1;
    end

    always @(posedge clk) begin
        if (can_bus != last_can_bus) begin
            can_bus_transition_count = can_bus_transition_count + 1;
        end
        last_can_bus = can_bus;
    end

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        wait (rst_n == 1'b1);
        #(CLK_PERIOD_NS * 100);

        $display("\n========================================");
        $display("=== CAN Handler Variable Length Test ===");
        $display("========================================\n");

        // Test 1: 配置CAN Handler
        send_can_config(
            11'h001,  // Local ID = 0x001
            11'h002,  // RX Filter = 0x002 (接收对端的帧)
            11'h7FF   // RX Mask = 全匹配
        );

        #(CLK_PERIOD_NS * 1000);

        // Test 2: 只发送一帧4字节
        $display("\n=== Test 2: Send 4 bytes (AABB0000) ===");
        send_can_tx(64'h0000_0000_AABB_0000, 4'd4);  // 4字节

        // 等待第一帧完全发送完成
        wait(u_dut.u_can_top.pkt_tx_done);
        $display("[%0t] First TX done signal received", $time);
        #(CLK_PERIOD_NS * 5000);  // 等待更长时间让FIFO推进

        // Test 3: 发送第二帧4字节数据
        $display("\n=== Test 3: Send 4 bytes (DEADBEEF) ===");
        send_can_tx(64'h0000_0000_DEAD_BEEF, 4'd4);

        // 等待第二帧完全发送完成
        wait(u_dut.u_can_top.pkt_tx_done);
        $display("[%0t] Second TX done signal received", $time);
        #(CLK_PERIOD_NS * 5000);

        // Test 4: 发送2字节数据
        $display("\n=== Test 4: Send 2 bytes (FF00) ===");
        send_can_tx(64'h0000_0000_FF00_0000, 4'd2);

        wait(u_dut.u_can_top.pkt_tx_done);
        $display("[%0t] Third TX done signal received", $time);
        #(CLK_PERIOD_NS * 5000);

        // Test 6: Peer发送2字节给Handler
        $display("\n=== Test 6: Peer sends 2 bytes to Handler ===");
        peer_send_frame(64'h0000_0000_0000_AABB, 4'd2);
        #(CLK_PERIOD_NS * 10000);

        // Test 7: 读取Handler接收到的数据
        send_can_rx_request();
        #(CLK_PERIOD_NS * 5000);

        // Test 8: Peer发送8字节给Handler
        $display("\n=== Test 8: Peer sends 8 bytes to Handler ===");
        peer_send_frame(64'hCAFE_BABE_DEAD_BEEF, 4'd8);
        #(CLK_PERIOD_NS * 10000);

        send_can_rx_request();
        #(CLK_PERIOD_NS * 5000);

        $display("\n========================================");
        $display("=== Simulation Complete ===");
        $display("CAN Bus transitions: %0d", can_bus_transition_count);
        $display("Handler RX count: %0d", u_dut.rx_count);
        $display("Handler state: %0d", u_dut.handler_state);
        $display("Upload state: %0d", u_dut.upload_state);
        $display("========================================\n");

        #(CLK_PERIOD_NS * 1000);
        $finish;
    end

    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #(CLK_PERIOD_NS * 500_000); // 500k cycles timeout
        $display("\n*** ERROR: Simulation timeout! ***");
        $finish;
    end

    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("can_handler_tb.vcd");
        $dumpvars(0, can_handler_tb);
    end

endmodule

// ============================================================================
// CAN PHY Simulation Module (类似TJA1050芯片)
// ============================================================================
module tb_can_phy(
    input  wire    can_tx,
    output wire    can_rx,
    inout          can_bus    // can_bus = CAN_H - CAN_L
);

// CAN PHY逻辑修正：
// CAN标准：1=隐性(Recessive, 总线默认态), 0=显性(Dominant, 优先级高)
// 物理层：can_tx=1时不驱动总线(高阻，总线上拉到1), can_tx=0时驱动总线为0
assign can_bus = can_tx ? 1'bz : 1'b0;  // TX=1→高阻(隐性), TX=0→驱动0(显性)
assign can_rx = can_bus;                 // 直接读取总线状态

endmodule
