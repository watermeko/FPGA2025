// ============================================================================
// I2C Slave Handler Usage Example
// ============================================================================
// This example demonstrates how to use the upgraded I2C slave with:
//   1. Register preload functionality
//   2. I2C master write to registers
//   3. I2C master read from registers
// ============================================================================

module i2c_slave_usage_example (
    input  logic        clk,
    input  logic        rst_n,

    // I2C Physical Interface
    input  wire         i2c_scl,
    inout  wire         i2c_sda,

    // CDC Command Bus (for demonstration - connect to your CDC module)
    input  logic [7:0]  cmd_type,
    input  logic [15:0] cmd_length,
    input  logic [7:0]  cmd_data,
    input  logic [15:0] cmd_data_index,
    input  logic        cmd_start,
    input  logic        cmd_data_valid,
    input  logic        cmd_done,
    output logic        cmd_ready,

    // CDC Upload Bus (for demonstration - connect to your CDC module)
    output logic        upload_active,
    output logic        upload_req,
    output logic [7:0]  upload_data,
    output logic [7:0]  upload_source,
    output logic        upload_valid,
    input  logic        upload_ready
);

    // ========================================================================
    // Register Preload Example
    // ========================================================================
    // These signals allow you to preload register values from FPGA internal logic
    logic        preload_en;
    logic [7:0]  preload_addr;
    logic [7:0]  preload_data;

    // Example state machine to preload registers at startup
    localparam PRELOAD_IDLE  = 3'd0;
    localparam PRELOAD_REG0  = 3'd1;
    localparam PRELOAD_REG1  = 3'd2;
    localparam PRELOAD_REG2  = 3'd3;
    localparam PRELOAD_REG3  = 3'd4;
    localparam PRELOAD_DONE  = 3'd5;

    logic [2:0] preload_state;
    logic preload_complete;

    // State machine to preload all 4 registers with initial values
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            preload_state <= PRELOAD_IDLE;
            preload_en    <= 1'b0;
            preload_addr  <= 8'd0;
            preload_data  <= 8'd0;
            preload_complete <= 1'b0;
        end else begin
            case (preload_state)
                PRELOAD_IDLE: begin
                    preload_state <= PRELOAD_REG0;
                end

                PRELOAD_REG0: begin
                    preload_en    <= 1'b1;
                    preload_addr  <= 8'd0;
                    preload_data  <= 8'hAA;  // Preload register 0 with 0xAA
                    preload_state <= PRELOAD_REG1;
                end

                PRELOAD_REG1: begin
                    preload_en    <= 1'b1;
                    preload_addr  <= 8'd1;
                    preload_data  <= 8'hBB;  // Preload register 1 with 0xBB
                    preload_state <= PRELOAD_REG2;
                end

                PRELOAD_REG2: begin
                    preload_en    <= 1'b1;
                    preload_addr  <= 8'd2;
                    preload_data  <= 8'hCC;  // Preload register 2 with 0xCC
                    preload_state <= PRELOAD_REG3;
                end

                PRELOAD_REG3: begin
                    preload_en    <= 1'b1;
                    preload_addr  <= 8'd3;
                    preload_data  <= 8'hDD;  // Preload register 3 with 0xDD
                    preload_state <= PRELOAD_DONE;
                end

                PRELOAD_DONE: begin
                    preload_en    <= 1'b0;
                    preload_complete <= 1'b1;
                    // Stay in this state - preload is complete
                end

                default: preload_state <= PRELOAD_IDLE;
            endcase
        end
    end

    // ========================================================================
    // I2C Slave Handler Instantiation
    // ========================================================================
    i2c_slave_handler u_i2c_slave_handler (
        // System clock and reset
        .clk            (clk),
        .rst_n          (rst_n),

        // CDC Command Bus Interface
        .cmd_type       (cmd_type),
        .cmd_length     (cmd_length),
        .cmd_data       (cmd_data),
        .cmd_data_index (cmd_data_index),
        .cmd_start      (cmd_start),
        .cmd_data_valid (cmd_data_valid),
        .cmd_done       (cmd_done),
        .cmd_ready      (cmd_ready),

        // CDC Upload Bus Interface
        .upload_active  (upload_active),
        .upload_req     (upload_req),
        .upload_data    (upload_data),
        .upload_source  (upload_source),
        .upload_valid   (upload_valid),
        .upload_ready   (upload_ready),

        // Physical I2C Interface
        .i2c_scl        (i2c_scl),
        .i2c_sda        (i2c_sda),

        // Register Preload Interface
        .preload_en     (preload_en),
        .preload_addr   (preload_addr),
        .preload_data   (preload_data)
    );

endmodule

// ============================================================================
// Usage Instructions
// ============================================================================
//
// 1. REGISTER PRELOAD (FPGA Internal):
//    - Set preload_en = 1
//    - Set preload_addr to target register address (0-3)
//    - Set preload_data to desired 8-bit value
//    - On next clock cycle, register will be updated
//    - This happens before any I2C communication
//
// 2. I2C MASTER WRITE (External I2C Master):
//    - I2C Master sends: [START] [SLAVE_ADDR + W] [REG_ADDR] [DATA] [STOP]
//    - Example: Write 0x55 to register 0
//      Transaction: START, 0x48(W), 0x00, 0x55, STOP
//    - The data written by I2C master will overwrite preloaded values
//
// 3. I2C MASTER READ (External I2C Master):
//    - I2C Master sends: [START] [SLAVE_ADDR + W] [REG_ADDR] [RESTART] [SLAVE_ADDR + R] [READ DATA] [STOP]
//    - Example: Read from register 0
//      Transaction: START, 0x48(W), 0x00, RESTART, 0x49(R), [DATA], STOP
//    - I2C master will read the current register value (either preloaded or previously written)
//
// 4. CDC COMMANDS (from CDC Module):
//    - Command 0x34: Set I2C slave address dynamically
//    - Command 0x35: Write to registers via CDC bus
//    - Command 0x36: Read from registers and upload via CDC bus
//
// ============================================================================
// Register Map
// ============================================================================
// Address  | Description          | Default (Preloaded)
// ---------|----------------------|--------------------
//   0x00   | Register 0           | 0xAA (in this example)
//   0x01   | Register 1           | 0xBB (in this example)
//   0x02   | Register 2           | 0xCC (in this example)
//   0x03   | Register 3           | 0xDD (in this example)
//
// ============================================================================
// I2C Transaction Examples
// ============================================================================
//
// Example 1: Read preloaded value from register 0
//   Master: START
//   Master: 0x48 (Slave Address 0x24, Write bit)
//   Slave:  ACK
//   Master: 0x00 (Register address 0)
//   Slave:  ACK
//   Master: RESTART
//   Master: 0x49 (Slave Address 0x24, Read bit)
//   Slave:  ACK
//   Slave:  0xAA (Preloaded data)
//   Master: NACK
//   Master: STOP
//
// Example 2: Write new value to register 1
//   Master: START
//   Master: 0x48 (Slave Address 0x24, Write bit)
//   Slave:  ACK
//   Master: 0x01 (Register address 1)
//   Slave:  ACK
//   Master: 0x12 (New data to write)
//   Slave:  ACK
//   Master: STOP
//
// Example 3: Read the updated value from register 1
//   Master: START
//   Master: 0x48 (Slave Address 0x24, Write bit)
//   Slave:  ACK
//   Master: 0x01 (Register address 1)
//   Slave:  ACK
//   Master: RESTART
//   Master: 0x49 (Slave Address 0x24, Read bit)
//   Slave:  ACK
//   Slave:  0x12 (Previously written data)
//   Master: NACK
//   Master: STOP
//
// ============================================================================
