// ============================================================================
// Module:  protocol_parser (REVISED AND DEBUGGED)
// ... (header is the same) ...
// ============================================================================

module protocol_parser #(
        parameter MAX_PAYLOAD_LEN = 256,
        parameter ADDR_WIDTH      = $clog2(MAX_PAYLOAD_LEN)
    )(
        // ... (ports are the same) ...
        input                       clk,
        input                       rst_n,
        input      [7:0]            uart_rx_data,
        input                       uart_rx_valid,
        input      [ADDR_WIDTH-1:0] payload_read_addr,
        output reg [7:0]            payload_read_data,
        output reg                  parse_done,
        output reg                  parse_error,
        output reg [7:0]            cmd_out,
        output reg [15:0]           len_out
    );

    // --- FSM State and Protocol Constant Definitions ---
    localparam IDLE      = 4'h0;
    localparam SYNC      = 4'h1;
    localparam CMD       = 4'h2;
    localparam LEN_H     = 4'h3;
    localparam LEN_L     = 4'h4;
    // **** NEW STATE ADDED ****
    localparam POST_LEN  = 4'h5; // New state to decide action after length is received
    localparam PAYLOAD   = 4'h6;
    localparam CHECKSUM  = 4'h7;

    localparam SOF1      = 8'hAA;
    localparam SOF2      = 8'h55;

    // --- Internal Registers and Memory ---
    reg [3:0]  current_state, next_state;
    reg [15:0] payload_cnt;
    reg [7:0]  checksum_reg;
    reg [7:0]  payload_mem [0:MAX_PAYLOAD_LEN-1];

    //-----------------------------------------------------------------------------
    // FSM Next State Logic (Combinational) - REVISED
    //-----------------------------------------------------------------------------
    always @(*) begin
        next_state = current_state;

        // The POST_LEN state is transient and doesn't depend on uart_rx_valid
        if (current_state == POST_LEN) begin
            if (len_out > MAX_PAYLOAD_LEN) begin
                next_state = IDLE; // Invalid length, abort and go to IDLE
            end
            else if (len_out == 0) begin
                next_state = CHECKSUM; // No payload, go directly to checksum
            end
            else begin
                next_state = PAYLOAD; // Valid length, proceed to receive payload
            end
        end
        else if (uart_rx_valid) begin // Other states transition on new data
            case (current_state)
                IDLE:
                    if (uart_rx_data == SOF1)
                        next_state = SYNC;
                SYNC:
                    if (uart_rx_data == SOF2)
                        next_state = CMD;
                    else
                        next_state = IDLE;
                CMD:
                    next_state = LEN_H;
                LEN_H:
                    next_state = LEN_L;
                // **** CHANGE ****
                // LEN_L now unconditionally goes to POST_LEN to make a decision
                LEN_L:
                    next_state = POST_LEN;
                PAYLOAD:
                    if (payload_cnt == len_out - 1)
                        next_state = CHECKSUM;
                    else
                        next_state = PAYLOAD;
                CHECKSUM:
                    next_state = IDLE;
                default:
                    next_state = IDLE;
            endcase
        end
    end

    //-----------------------------------------------------------------------------
    // FSM Output and Data Processing Logic (Sequential) - REVISED
    //-----------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ... (Reset logic is the same) ...
            current_state <= IDLE;
            parse_done    <= 1'b0;
            parse_error   <= 1'b0;
            cmd_out       <= 8'h00;
            len_out       <= 16'h0000;
            payload_cnt   <= 16'h0000;
            checksum_reg  <= 8'h00;
        end
        else begin
            parse_done  <= 1'b0;
            parse_error <= 1'b0;

            current_state <= next_state;

            // **** NEW LOGIC for POST_LEN ****
            // Handle logic that doesn't need uart_rx_valid
            if (current_state == POST_LEN) begin
                if (len_out > MAX_PAYLOAD_LEN) begin
                    parse_error <= 1'b1; // Assert error for invalid length
                end
            end

            if (uart_rx_valid) begin
                case (current_state)
                    IDLE: begin
                        payload_cnt  <= 16'h0000;
                        checksum_reg <= 8'h00;
                    end
                    CMD: begin
                        cmd_out      <= uart_rx_data;
                        checksum_reg <= uart_rx_data;
                    end
                    LEN_H: begin
                        len_out[15:8] <= uart_rx_data;
                        checksum_reg  <= checksum_reg + uart_rx_data;
                    end
                    LEN_L: begin
                        len_out[7:0] <= uart_rx_data;
                        checksum_reg <= checksum_reg + uart_rx_data;
                    end
                    PAYLOAD: begin
                        payload_mem[payload_cnt] <= uart_rx_data;
                        payload_cnt  <= payload_cnt + 1;
                        checksum_reg <= checksum_reg + uart_rx_data;
                    end
                    CHECKSUM: begin
                        if (checksum_reg == uart_rx_data) begin
                            parse_done <= 1'b1;
                        end
                        else begin
                            parse_error <= 1'b1;
                        end
                    end
                endcase
            end
        end
    end

    // --- Payload Memory Read Port Logic (Combinational) --- (This part is unchanged)
    always @(*) begin
        payload_read_data = payload_mem[payload_read_addr];
    end

endmodule
