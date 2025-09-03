// ============================================================================
// Module:  uart_module
// Author:  Gemini
// Date:    2025-09-02
//
// Description:
// A synthesizable, parameterized UART module including both a transmitter (TX)
// and a receiver (RX).
// - 8 data bits
// - No parity bit
// - 1 stop bit
// ============================================================================
// TODO: Use sync registers
module uart#(
    // --- Parameters ---
    parameter CLK_FREQ  = 50_000_000, // FPGA System Clock Frequency (e.g., 50 MHz)
    parameter BAUD_RATE = 9600        // Desired Baud Rate (e.g., 9600, 115200)
)(
    // --- Global ---
    input  wire         clk,
    input  wire         rst_n,

    // --- TX Interface ---
    input  wire [7:0]   tx_data_in,     // Data to be transmitted
    input  wire         tx_start,       // Start transmission signal (pulse)
    output wire         tx_busy,        // Indicates that the transmitter is busy
    output reg          uart_tx,        // UART transmit pin

    // --- RX Interface ---
    input  wire         uart_rx,        // UART receive pin
    output reg  [7:0]   rx_data_out,    // Received data
    output reg          rx_data_valid   // Data valid signal (pulse)
);

//-----------------------------------------------------------------------------
// Local Parameter Calculation
//-----------------------------------------------------------------------------
// Calculate how many system clock cycles fit into one bit period.
localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

//=============================================================================
// TX (TRANSMITTER) LOGIC
//=============================================================================

// --- TX FSM States ---
localparam TX_IDLE  = 3'b001;
localparam TX_START = 3'b010;
localparam TX_DATA  = 3'b011;
localparam TX_STOP  = 3'b100;

// --- TX Registers ---
reg [2:0]  tx_state;          // TX state machine
reg [19:0] tx_clk_cnt;        // Clock counter for bit timing (20 bits for safety up to 1 second)
reg [3:0]  tx_bit_cnt;        // Counter for data bits sent
reg [7:0]  tx_data_reg;       // Register to hold data being sent

// --- TX Logic ---
assign tx_busy = (tx_state == TX_IDLE) ? 1'b0 : 1'b1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Reset state
        tx_state    <= TX_IDLE;
        tx_clk_cnt  <= 0;
        tx_bit_cnt  <= 0;
        tx_data_reg <= 0;
        uart_tx     <= 1'b1; // Idle line is high
    end else begin
        case (tx_state)
            TX_IDLE: begin
                uart_tx <= 1'b1;
                if (tx_start) begin
                    tx_data_reg <= tx_data_in;
                    tx_clk_cnt  <= 0;
                    tx_state    <= TX_START;
                end
            end
            
            TX_START: begin
                uart_tx <= 1'b0; // Send start bit
                if (tx_clk_cnt < CLKS_PER_BIT - 1) begin
                    tx_clk_cnt <= tx_clk_cnt + 1;
                end else begin
                    tx_clk_cnt <= 0;
                    tx_bit_cnt <= 0;
                    tx_state   <= TX_DATA;
                end
            end
            
            TX_DATA: begin
                uart_tx <= tx_data_reg[tx_bit_cnt];
                if (tx_clk_cnt < CLKS_PER_BIT - 1) begin
                    tx_clk_cnt <= tx_clk_cnt + 1;
                end else begin
                    tx_clk_cnt <= 0;
                    if (tx_bit_cnt < 7) begin
                        tx_bit_cnt <= tx_bit_cnt + 1;
                    end else begin
                        tx_state <= TX_STOP;
                    end
                end
            end
            
            TX_STOP: begin
                uart_tx <= 1'b1; // Send stop bit
                if (tx_clk_cnt < CLKS_PER_BIT - 1) begin
                    tx_clk_cnt <= tx_clk_cnt + 1;
                end else begin
                    tx_state <= TX_IDLE;
                end
            end
            
            default:
                tx_state <= TX_IDLE;
        endcase
    end
end

//=============================================================================
// RX (RECEIVER) LOGIC
//=============================================================================

// --- RX FSM States ---
localparam RX_IDLE  = 3'b001;
localparam RX_START = 3'b010;
localparam RX_DATA  = 3'b011;
localparam RX_STOP  = 3'b100;

// --- RX Registers ---
reg [2:0]  rx_state;
reg [19:0] rx_clk_cnt;
reg [3:0]  rx_bit_cnt;
reg [7:0]  rx_data_reg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Reset state
        rx_state      <= RX_IDLE;
        rx_clk_cnt    <= 0;
        rx_bit_cnt    <= 0;
        rx_data_out   <= 0;
        rx_data_valid <= 1'b0;
    end else begin
        // Default assignment for pulse signal
        rx_data_valid <= 1'b0;

        case (rx_state)
            RX_IDLE: begin
                // Wait for a falling edge (start bit)
                if (uart_rx == 1'b0) begin
                    rx_clk_cnt <= 0;
                    rx_state   <= RX_START;
                end
            end

            RX_START: begin
                // Wait for half a bit period to sample in the middle of the start bit
                if (rx_clk_cnt < (CLKS_PER_BIT / 2) - 1) begin
                    rx_clk_cnt <= rx_clk_cnt + 1;
                end else begin
                    // Check if it's a valid start bit (still low)
                    if (uart_rx == 1'b0) begin
                        rx_clk_cnt <= 0;
                        rx_bit_cnt <= 0;
                        rx_state   <= RX_DATA;
                    end else begin
                        // Glitch detected, return to idle
                        rx_state <= RX_IDLE;
                    end
                end
            end

            RX_DATA: begin
                // Wait for a full bit period to sample in the middle of a data bit
                if (rx_clk_cnt < CLKS_PER_BIT - 1) begin
                    rx_clk_cnt <= rx_clk_cnt + 1;
                end else begin
                    rx_clk_cnt <= 0;
                    rx_data_reg[rx_bit_cnt] <= uart_rx; // Sample and store LSB first
                    if (rx_bit_cnt < 7) begin
                        rx_bit_cnt <= rx_bit_cnt + 1;
                    end else begin
                        rx_state <= RX_STOP;
                    end
                end
            end

            RX_STOP: begin
                // Wait for one bit period to get past the stop bit
                if (rx_clk_cnt < CLKS_PER_BIT - 1) begin
                    rx_clk_cnt <= rx_clk_cnt + 1;
                end else begin
                    // Present the received data and generate valid pulse
                    rx_data_valid <= 1'b1;
                    rx_data_out   <= rx_data_reg;
                    rx_state      <= RX_IDLE;
                end
            end

            default:
                rx_state <= RX_IDLE;
        endcase
    end
end

endmodule