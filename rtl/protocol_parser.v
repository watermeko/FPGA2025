// ============================================================================
// Module: protocol_parser
// Author: Gemini
// Date: 2025-09-03
//
// Description:
// Parses a command frame received over UART. The frame format is:
// SOF1 (0xAA) | SOF2 (0x55) | CMD (1B) | LEN (2B) | PAYLOAD (0-N B) | CHECKSUM (1B)
//
// Features:
// - Detects Start-of-Frame (SOF) bytes.
// - Extracts command, length, and payload.
// - Calculates and verifies the checksum.
// - Stores the payload in a memory for later retrieval.
// - Outputs status signals (parse_done, parse_error).
// - Provides a read port for the command processor to access the payload.
// ============================================================================
module protocol_parser #(
        parameter MAX_PAYLOAD_LEN = 256
    )(
        // System Signals
        input wire clk,
        input wire rst_n,

        // UART Input
        input wire [7:0] uart_rx_data,
        input wire uart_rx_valid,

        // Payload Read Port (for command_processor)
        input wire [$clog2(MAX_PAYLOAD_LEN)-1:0] payload_read_addr,
        output wire [7:0] payload_read_data,

        // Parser Outputs
        output reg parse_done,
        output reg parse_error,
        output reg [7:0] cmd_out,
        output reg [15:0] len_out
    );

    // 存储接收到的payload
    reg [7:0] payload_mem [MAX_PAYLOAD_LEN-1:0];
    reg [7:0] payload_read_data_reg; // 用于同步读取的寄存器

    // 状态机状态
    localparam [2:0]
        S_IDLE      = 3'b000,
        S_SOF2      = 3'b001,
        S_CMD       = 3'b010,
        S_LEN_H     = 3'b011,
        S_LEN_L     = 3'b100,
        S_PAYLOAD   = 3'b101,
        S_CHECKSUM  = 3'b110;

    reg [2:0] state = S_IDLE;
    reg [15:0] payload_counter = 0;
    reg [7:0] checksum = 0;

    // 同步读取 payload
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n) begin
            payload_read_data_reg <= 0;
        end
        else begin
            payload_read_data_reg <= payload_mem[payload_read_addr];
        end
    end
    assign payload_read_data = payload_read_data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            parse_done <= 1'b0;
            parse_error <= 1'b0;
            cmd_out <= 8'h00;
            len_out <= 16'h0000;
            payload_counter <= 0;
            checksum <= 0;
        end else begin
            // Default assignments
            parse_done <= 1'b0;
            parse_error <= 1'b0;

            if (uart_rx_valid) begin
                case (state)
                    S_IDLE: begin
                        if (uart_rx_data == 8'hAA) begin
                            state <= S_SOF2;
                        end
                    end
                    S_SOF2: begin
                        if (uart_rx_data == 8'h55) begin
                            state <= S_CMD;
                            checksum <= 0; // Reset checksum
                        end else begin
                            state <= S_IDLE; // Invalid SOF, reset
                        end
                    end
                    S_CMD: begin
                        cmd_out <= uart_rx_data;
                        checksum <= checksum + uart_rx_data;
                        state <= S_LEN_H;
                    end
                    S_LEN_H: begin
                        len_out[15:8] <= uart_rx_data;
                        checksum <= checksum + uart_rx_data;
                        state <= S_LEN_L;
                    end
                    S_LEN_L: begin
                        len_out[7:0] <= uart_rx_data;
                        checksum <= checksum + uart_rx_data;
                        if ({len_out[15:8], uart_rx_data} > MAX_PAYLOAD_LEN) begin
                            parse_error <= 1'b1; // Payload too long
                            state <= S_IDLE;
                        end else if ({len_out[15:8], uart_rx_data} == 0) begin
                            state <= S_CHECKSUM; // No payload
                        end else begin
                            payload_counter <= 0;
                            state <= S_PAYLOAD;
                        end
                    end
                    S_PAYLOAD: begin
                        payload_mem[payload_counter] <= uart_rx_data;
                        checksum <= checksum + uart_rx_data;
                        if (payload_counter == len_out - 1) begin
                            state <= S_CHECKSUM;
                        end else begin
                            payload_counter <= payload_counter + 1;
                        end
                    end
                    S_CHECKSUM: begin
                        if (checksum == uart_rx_data) begin
                            parse_done <= 1'b1;
                        end else begin
                            parse_error <= 1'b1;
                        end
                        state <= S_IDLE;
                    end
                    default: begin
                        state <= S_IDLE;
                    end
                endcase
            end
        end
    end

endmodule