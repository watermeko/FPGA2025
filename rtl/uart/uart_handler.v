module uart_handler(
        input  wire        clk,
        input  wire        rst_n,
        input  wire [7:0]  cmd_type,
        input  wire [15:0] cmd_length,
        input  wire [7:0]  cmd_data,
        input  wire [15:0] cmd_data_index,
        input  wire        cmd_start,
        input  wire        cmd_data_valid,
        input  wire        cmd_done,

        output wire        cmd_ready,
        output wire ext_uart_tx,
        input wire ext_uart_rx

    );

    // Command type codes
    localparam CMD_UART_CONFIG = 8'h07;
    localparam CMD_UART_TX     = 8'h08;
    localparam CMD_UART_RX     = 8'h09;

    // State machine definition
    localparam H_IDLE        = 3'b000; // Idle state
    localparam H_RX_CONFIG   = 3'b001; // Receiving UART configuration
    localparam H_UPDATE_CFG  = 3'b010; // Update UART configuration
    localparam H_RX_TX_DATA  = 3'b011; // Receiving data to transmit
    localparam H_HANDLE_RX   = 3'b100; // Handling UART receive command

    // TX state machine definition
    localparam TX_IDLE = 2'b00;
    localparam TX_SEND = 2'b01;
    localparam TX_WAIT = 2'b10;

    reg [1:0] tx_state;
    reg [2:0] handler_state;

    // UART Configuration Registers
    reg [31:0] uart_baud_rate;
    reg [7:0]  uart_data_bits;
    reg [7:0]  uart_stop_bits;
    reg [7:0]  uart_parity;

    // Temporary storage for command payload
    reg [7:0] uart_config_data [0:6];

    // TX FIFO
    reg [7:0]  tx_fifo [0:15];
    reg [3:0]  tx_fifo_wr_ptr;
    reg [3:0]  tx_fifo_rd_ptr;
    reg [4:0]  tx_fifo_count;
    wire       tx_fifo_full;
    wire       tx_fifo_empty;
    wire [7:0] tx_fifo_data_out;

    // RX FIFO
    reg [7:0]  rx_fifo [0:15];
    reg [3:0]  rx_fifo_wr_ptr;
    reg [3:0]  rx_fifo_rd_ptr;
    reg [4:0]  rx_fifo_count;
    wire       rx_fifo_full;
    wire       rx_fifo_empty;
    wire [7:0] rx_fifo_data_out;

    // UART module interface signals
    wire       uart_tx_busy;
    wire [15:0] uart_rx_data;
    wire        uart_rx_data_val;
    reg         uart_tx_data_val;
    reg [15:0]  uart_tx_data;

    wire fifo_wr_en = (handler_state == H_RX_TX_DATA) && cmd_data_valid && !tx_fifo_full;
    wire fifo_rd_en = (tx_state == TX_SEND) && uart_tx_busy;

    // Ready to accept new commands
    assign cmd_ready = (handler_state == H_IDLE) || (handler_state == H_RX_CONFIG) || ((handler_state == H_RX_TX_DATA) && !tx_fifo_full);

    // TX FIFO logic
    assign tx_fifo_empty = (tx_fifo_count == 0);
    assign tx_fifo_full = (tx_fifo_count == 16);
    assign tx_fifo_data_out = tx_fifo[tx_fifo_rd_ptr];

    // RX FIFO logic
    assign rx_fifo_empty = (rx_fifo_count == 0);
    assign rx_fifo_full = (rx_fifo_count == 16);
    assign rx_fifo_data_out = rx_fifo[rx_fifo_rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            handler_state <= H_IDLE;
            tx_state <= TX_IDLE;
            // TX FIFO reset
            tx_fifo_wr_ptr <= 0;
            tx_fifo_rd_ptr <= 0;
            tx_fifo_count  <= 0;
            // RX FIFO reset
            rx_fifo_wr_ptr <= 0;
            rx_fifo_rd_ptr <= 0;
            rx_fifo_count  <= 0;
            // Default UART config
            uart_baud_rate <= 115200;
            uart_data_bits <= 8;
            uart_stop_bits <= 0; // 1 stop bit
            uart_parity    <= 0; // None
        end else begin
            // Default assignments
            uart_tx_data_val <= 1'b0;

            // State machine
            case (handler_state)
                H_IDLE: begin
                    if (cmd_start) begin
                        case (cmd_type)
                            CMD_UART_CONFIG: handler_state <= H_RX_CONFIG;
                            CMD_UART_TX:     handler_state <= H_RX_TX_DATA;
                            CMD_UART_RX:     handler_state <= H_HANDLE_RX;
                            default:         handler_state <= H_IDLE;
                        endcase
                    end
                end

                H_RX_CONFIG: begin
                    if (cmd_data_valid) begin
                        uart_config_data[cmd_data_index] <= cmd_data;
                    end
                    if (cmd_done) begin
                        handler_state <= H_UPDATE_CFG;
                    end
                end

                H_UPDATE_CFG: begin
                    uart_baud_rate <= {uart_config_data[0], uart_config_data[1], uart_config_data[2], uart_config_data[3]};
                    uart_data_bits <= uart_config_data[4];
                    uart_stop_bits <= uart_config_data[5];
                    uart_parity    <= uart_config_data[6];
                    handler_state  <= H_IDLE;
                end

                H_RX_TX_DATA: begin
                    if (fifo_wr_en) begin
                        tx_fifo[tx_fifo_wr_ptr] <= cmd_data;
                        tx_fifo_wr_ptr <= tx_fifo_wr_ptr + 1;
                    end
                    if (cmd_done) begin
                        handler_state <= H_IDLE;
                    end
                end
                
                H_HANDLE_RX: begin
                    // Currently, this state just acknowledges the command.
                    // The received data is in the RX FIFO.
                    // A mechanism to send this data back to the host would be needed.
                    if (cmd_done) begin
                        handler_state <= H_IDLE;
                    end
                end

                default: begin
                    handler_state <= H_IDLE;
                end
            endcase

            // TX FIFO count logic
            if (fifo_wr_en && !fifo_rd_en) begin
                tx_fifo_count <= tx_fifo_count + 1;
            end else if (!fifo_wr_en && fifo_rd_en) begin
                tx_fifo_count <= tx_fifo_count - 1;
            end

            // TX state machine
            case (tx_state)
                TX_IDLE: begin
                    if (!tx_fifo_empty) begin
                        uart_tx_data <= {8'h00, tx_fifo_data_out};
                        tx_state <= TX_SEND;
                    end
                end
                TX_SEND: begin
                    uart_tx_data_val <= 1'b1;
                    if (uart_tx_busy) begin
                        tx_fifo_rd_ptr <= tx_fifo_rd_ptr + 1;
                        tx_state <= TX_WAIT;
                    end
                end
                TX_WAIT: begin
                    if (!uart_tx_busy) begin
                        tx_state <= TX_IDLE;
                    end
                end
            endcase

            // RX FIFO write logic
            if (uart_rx_data_val && !rx_fifo_full) begin
                rx_fifo[rx_fifo_wr_ptr] <= uart_rx_data[7:0];
                rx_fifo_wr_ptr <= rx_fifo_wr_ptr + 1;
                rx_fifo_count <= rx_fifo_count + 1;
            end
        end
    end

UART #(
    .CLK_FREQ(60_000_000)
) u_UART(
    .CLK         	(clk          ),
    .RST         	(~rst_n          ),
    .UART_TXD    	(ext_uart_tx     ),
    .UART_RXD    	(ext_uart_rx),
    .UART_RTS    	(),
    .UART_CTS    	(1'b0), // Tie CTS to active (ready to receive)
    .BAUD_RATE   (uart_baud_rate),
    .PARITY_BIT  (uart_parity),
    .STOP_BIT    (uart_stop_bits),
    .DATA_BITS   (uart_data_bits),
    .TX_DATA     	(uart_tx_data),
    .TX_DATA_VAL 	(uart_tx_data_val),
    .TX_BUSY     	(uart_tx_busy),
    .RX_DATA     	(uart_rx_data),
    .RX_DATA_VAL 	(uart_rx_data_val)
);

endmodule