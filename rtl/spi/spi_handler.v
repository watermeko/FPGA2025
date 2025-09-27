module spi_handler (
    input clk,
    input rst_n,
    
    // Command Interface
    input [7:0]  cmd_type,
    input [15:0] cmd_length,
    input [7:0]  cmd_data,
    input [15:0] cmd_data_index,
    input        cmd_start,
    input        cmd_data_valid,
    input        cmd_done,
    output reg   cmd_ready,
    
    // SPI Interface
    output       spi_clk,
    output       spi_cs_n,
    output       spi_mosi,
    input        spi_miso,
    
    // Data Upload Interface
    output reg       upload_req,
    output reg [7:0] upload_data,
    output reg [7:0] upload_source,
    output reg       upload_valid,
    input            upload_ready
);

    // SPI command type definitions
    parameter CMD_SPI_CONFIG = 8'h10;
    parameter CMD_SPI_WRITE  = 8'h11;
    parameter CMD_SPI_READ   = 8'h12;

    // Signals for connecting to the SPI IP core
    wire        spi_tx_en;
    wire        spi_rx_en;
    wire [2:0]  spi_waddr;
    wire [7:0]  spi_wdata;
    wire [2:0]  spi_raddr;
    wire [7:0]  spi_rdata;
    wire        spi_int;

    // Internal state machine
    reg [3:0] state;
    parameter IDLE             = 4'd0;
    parameter CONFIG           = 4'd1;
    parameter TX_SETUP         = 4'd2;
    parameter SELECT_SLAVE     = 4'd3;
    parameter TX_DATA          = 4'd4;
    parameter WAIT_TRANSFER    = 4'd5;
    parameter DEASSERT_CS      = 4'd6;
    parameter RX_DELAY         = 4'd7;
    parameter RX_CMD           = 4'd8;
    parameter RX_WAIT_IP   = 4'd13;
    parameter RX_DATA_WAIT = 4'd12;
    parameter RX_SAMPLE    = 4'd11;
    parameter UPLOAD       = 4'd10;

    // Data buffers and control signals
    reg [7:0] tx_buffer [0:255];
    reg [7:0] rx_buffer [0:255];
    reg [7:0] tx_count, rx_count;
    reg [7:0] byte_index;
    reg [4:0] wait_counter;
    reg [1:0] rx_wait_cnt;

    // IP core control signals
    reg tx_enable;
    reg rx_enable; 
    reg [2:0] write_addr;
    reg [7:0] write_data;
    reg [2:0] read_addr;


    assign spi_tx_en = tx_enable;
    assign spi_rx_en = rx_enable;
    assign spi_waddr = write_addr;
    assign spi_wdata = write_data;
    assign spi_raddr = read_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_ready <= 1'b1;
            state <= IDLE;
            tx_enable <= 1'b0;
            rx_enable <= 1'b0;
            byte_index <= 8'd0;
            upload_req <= 1'b0;
            upload_valid <= 1'b0;
            wait_counter <= 0;
            rx_wait_cnt <= 2'd0;
        end else begin
            tx_enable <= 1'b0;
            rx_enable <= 1'b0;
            upload_valid <= 1'b0;

            case (state)
                IDLE: begin
                    cmd_ready <= 1'b1;
                    if (cmd_start) begin
                        cmd_ready <= 1'b0;
                        case (cmd_type)
                            CMD_SPI_CONFIG: state <= CONFIG;
                            CMD_SPI_WRITE, CMD_SPI_READ: begin
                                state <= TX_SETUP;
                                tx_count <= cmd_length[7:0];
                                byte_index <= 8'd0;
                            end
                            default: cmd_ready <= 1'b1;
                        endcase
                    end
                end
                
                CONFIG: begin
                    if (cmd_data_valid) begin
                        write_addr <= cmd_data_index[2:0];
                        write_data <= cmd_data;
                        tx_enable <= 1'b1;
                    end
                    if (cmd_done) state <= IDLE;
                end
                
                TX_SETUP: begin
                    if (cmd_data_valid) tx_buffer[cmd_data_index] <= cmd_data;
                    if (cmd_done) begin
                        state <= SELECT_SLAVE;
                        byte_index <= 8'd0;
                    end
                end

// 在 SELECT_SLAVE 状态里，**提前 8 个 SCLK 就启动时钟**
SELECT_SLAVE: begin
    write_addr <= 3'h04;
    write_data <= 8'h01;
    tx_enable <= 1'b1;
    state <= TX_DATA;
    // **提前 8 个 SCLK 启动时钟**
    wait_counter <= 5'd8;  // 提前 8 个 SCLK 启动
end
                
                TX_DATA: begin
                    if (byte_index < tx_count) begin
                        write_addr <= 3'h01;
                        write_data <= tx_buffer[byte_index];
                        tx_enable <= 1'b1;
                        state <= WAIT_TRANSFER;
                        wait_counter <= 0;
                    end else begin
                        state <= DEASSERT_CS;
                    end
                end

                WAIT_TRANSFER: begin
                    if (wait_counter == 5'd20) begin
                        byte_index <= byte_index + 1'b1;
                        state <= TX_DATA;
                    end else begin
                        wait_counter <= wait_counter + 1;
                        state <= WAIT_TRANSFER;
                    end
                end
                
                DEASSERT_CS: begin
                    write_addr <= 3'h04;
                    write_data <= 8'h00;
                    tx_enable <= 1'b1;
                    if (cmd_type == CMD_SPI_READ) begin
                        rx_count <= cmd_length[7:0];
                        byte_index <= 8'd0;
                        state <= RX_DELAY;
                    end else begin
                        state <= IDLE;
                    end
                end

                RX_DELAY: begin
                    state <= RX_CMD;
                end

                // ------------------------------------------------------------------
                // 接收流程：与从机字节边界同拍对齐
                // ------------------------------------------------------------------
                RX_CMD: begin
    if (byte_index < rx_count) begin
        read_addr <= 3'h00;   // 选择接收寄存器
        rx_enable <= 1'b1;    // 发起读
        state <= RX_WAIT_IP;
    end else begin
        state <= UPLOAD;
        byte_index <= 8'd0;
    end
end

RX_WAIT_IP: begin
    rx_enable <= 1'b0;
    if (spi_int) begin        // 等 IP 发出接收完成中断
        rx_buffer[byte_index] <= spi_rdata;
        byte_index <= byte_index + 1'b1;
        state <= RX_CMD;
    end
end

                           // ------------------------------------------------------------------
            //  已修正：等“完整字节拼完”再上传
            // ------------------------------------------------------------------
            UPLOAD: begin
                upload_valid <= 1'b0;
                // 用 IP 核中断作为“字节完成”标志，不再用 slave_bit_cnt
                if (spi_int && upload_ready && byte_index < rx_count) begin
                    upload_data <= rx_buffer[byte_index];
                    upload_source <= 8'h03;
                    upload_valid <= 1'b1;
                    upload_req   <= 1'b1;
                    byte_index   <= byte_index + 1'b1;
                end
                if (byte_index >= rx_count) begin
                    upload_req <= 1'b0;
                    state      <= IDLE;
                end
            end


                
            endcase
        end
    end

    // Instantiate SPI IP Core
    SPI_MASTER_Top u_spi_master (
        .I_CLK(clk),
        .I_RESETN(rst_n),
        .I_TX_EN(spi_tx_en),
        .I_WADDR(spi_waddr),
        .I_WDATA(spi_wdata),
        .I_RX_EN(spi_rx_en),
        .I_RADDR(spi_raddr),
        .O_RDATA(spi_rdata),
        .O_SPI_INT(spi_int),
        .MISO_MASTER(spi_miso),
        .MOSI_MASTER(spi_mosi),
        .SS_N_MASTER(spi_cs_n),
        .SCLK_MASTER(spi_clk),
        .MISO_SLAVE(),
        .MOSI_SLAVE(1'b0),
        .SS_N_SLAVE(1'b1),
        .SCLK_SLAVE(1'b0)
    );

endmodule