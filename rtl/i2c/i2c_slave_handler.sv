//
// Module: i2c_slave_handler (Revised for robustness)
// Description:
//   - Implements a more robust state machine to handle CDC commands.
//   - Separates command data capture from command execution to avoid timing hazards.
//   - Buffers data for both write and upload operations.
//
module i2c_slave_handler (
    // System Interfaces
    input logic clk,
    input logic rst_n,

    // CDC Command Bus Interface
    input  logic [7:0]  cmd_type,
    input  logic [15:0] cmd_length,
    input  logic [7:0]  cmd_data,
    input  logic [15:0] cmd_data_index,
    input  logic        cmd_start,
    input  logic        cmd_data_valid,
    input  logic        cmd_done,
    output logic        cmd_ready,

    // CDC Upload Bus Interface
    output logic        upload_active,
    output logic        upload_req,
    output logic [7:0]  upload_data,
    output logic [7:0]  upload_source,
    output logic        upload_valid,
    input  logic        upload_ready,

    // Physical I2C Slave Interface
    input wire          i2c_scl,
    inout wire          i2c_sda,

    // Register Preload Interface (for FPGA internal logic to preset register values)
    input  logic        preload_en,      // Enable preload operation
    input  logic [7:0]  preload_addr,    // Register address to preload
    input  logic [7:0]  preload_data     // Data to preload into the register
);

    //================================================================
    // Internal Core Logic (Reused and Modified)
    //================================================================
    logic [6:0]  i2c_slave_address; // Register to hold the configurable slave address
    logic        sda_out;
    logic        sda_in;
    logic [7:0]  core_addr;
    logic [7:0]  core_wdata;
    logic [7:0]  core_rdata;
    logic        core_wr_en_wdata;
    logic        core_wr_en_wdata_sync;
    logic [7:0]  handler_addr;
    logic [7:0]  handler_wdata;
    logic        handler_wr_en;

    // <<< STEP 1: Declare wires to receive register values from reg_map >>>
    wire [7:0]  reg_val_0;
    wire [7:0]  reg_val_1;
    wire [7:0]  reg_val_2;
    wire [7:0]  reg_val_3;

    assign sda_in = i2c_sda;

    bidir u_sda ( .pad(i2c_sda), .to_pad(sda_out), .oe(~sda_out) );

    // Instantiate the modified i2c_slave with the configurable address
    i2c_slave u_i2c_slave (
        .clk           (clk), // <<< NEW: Pass the system clock down
        .slave_id      (i2c_slave_address), // Connect to our address register
        .rst_n         (rst_n),
        .scl           (i2c_scl),
        .sda_in        (sda_in),
        .sda_out       (sda_out),
        .rdata         (core_rdata),
        .addr          (core_addr),
        .wdata         (core_wdata),
        .wr_en_wdata   (core_wr_en_wdata),

        // --- Intentionally leave unused ports unconnected ---
        .i2c_active    (),
        .rd_en         (),
        .wr_en         ()
    );

    synchronizer u_wr_en_sync (
        .clk(clk), .rst_n(rst_n), .data_in(core_wr_en_wdata), .data_out(core_wr_en_wdata_sync)
    );

    // The shared register map (now with preload interface)
    reg_map u_reg_map (
        .clk           (clk),
        .rst_n         (rst_n),
        .addr          (handler_wr_en ? handler_addr : core_addr),
        .wdata         (handler_wr_en ? handler_wdata : core_wdata),
        .wr_en_wdata   (core_wr_en_wdata_sync | handler_wr_en),
        .rdata         (core_rdata),

        // Register preload interface
        .preload_en    (preload_en),
        .preload_addr  (preload_addr),
        .preload_data  (preload_data),

        // --- Intentionally leave unused ports unconnected ---
        // <<< STEP 2: Connect the output ports to our new wires >>>
        .register_0    (reg_val_0),
        .register_1    (reg_val_1),
        .register_2    (reg_val_2),
        .register_3    (reg_val_3)
    );

    //================================================================
    // Handler State Machine and Logic (UPGRADED)
    //================================================================
    // State definitions
    localparam S_IDLE              = 4'd0;
    localparam S_CMD_CAPTURE       = 4'd1;
    localparam S_EXEC_SET_ADDR     = 4'd2; // For command 0x34
    localparam S_EXEC_WRITE        = 4'd3; // For command 0x35
    localparam S_EXEC_WRITE_HOLD   = 4'd4; // Hold state for write to complete
    localparam S_EXEC_READ_SETUP   = 4'd5; // For command 0x36
    localparam S_UPLOAD_DATA       = 4'd6;
    localparam S_FINISH            = 4'd7;

    logic [3:0] state;
    
    // Registers for command parameters
    logic [7:0]  captured_data [0:5]; // Buffer for up to 6 bytes of command payload
    logic [7:0]  cdc_start_addr;
    logic [7:0]  cdc_len;
    logic [7:0]  cdc_write_ptr; // Pointer for writing multiple bytes
    logic [7:0]  cdc_read_ptr;  // Pointer for reading multiple bytes
    logic [7:0]  upload_buffer [0:3]; // Buffer to hold data for upload

    // --- Main State Machine ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            i2c_slave_address <= 7'h24; // Default address
            cdc_write_ptr <= '0;
            cdc_read_ptr <= '0;
        end else begin
            case (state)
                S_IDLE: begin
                    // Only respond to I2C slave specific commands (0x34, 0x35, 0x36)
                    if (cmd_start && (cmd_type == 8'h34 || cmd_type == 8'h35 || cmd_type == 8'h36)) begin
                        state <= S_CMD_CAPTURE;
                    end
                end
                
                S_CMD_CAPTURE: begin
                    if (cmd_done) begin
                        // Latch command parameters after capture is done
                        cdc_start_addr <= captured_data[0];
                        cdc_len <= captured_data[1];
                        case (cmd_type)
                            8'h34: state <= S_EXEC_SET_ADDR;
                            8'h35: begin
                                cdc_write_ptr <= '0; // Reset write pointer
                                state <= S_EXEC_WRITE;
                            end
                            8'h36: state <= S_EXEC_READ_SETUP;
                            default: state <= S_FINISH;
                        endcase
                    end
                end
                
                S_EXEC_SET_ADDR: begin
                    // Payload for 0x34 is just the address itself
                    i2c_slave_address <= captured_data[0][6:0];
                    state <= S_FINISH;
                end
                
                S_EXEC_WRITE: begin
                    // This state checks if we need to write more bytes
                    if (cdc_write_ptr < cdc_len) begin
                        // Go to hold state to allow write to complete
                        state <= S_EXEC_WRITE_HOLD;
                    end else begin
                        state <= S_FINISH; // All bytes written
                    end
                end

                S_EXEC_WRITE_HOLD: begin
                    // Hold state: increment pointer after write completes
                    // This gives reg_map time to capture the write enable edge
                    cdc_write_ptr <= cdc_write_ptr + 1;
                    state <= S_EXEC_WRITE; // Return to check if more writes needed
                end

                S_EXEC_READ_SETUP: begin
                    // Copy data from reg_map outputs to our local upload buffer
                    upload_buffer[0] <= reg_val_0;
                    upload_buffer[1] <= reg_val_1;
                    upload_buffer[2] <= reg_val_2;
                    upload_buffer[3] <= reg_val_3;
                    cdc_read_ptr <= cdc_start_addr; // Start reading from the specified address
                    state <= S_UPLOAD_DATA;
                end

                S_UPLOAD_DATA: begin
                    // Wait until the current byte is successfully uploaded
                    if (upload_req && upload_ready) begin
                        // Check if we have more bytes to upload
                        if (cdc_read_ptr < (cdc_start_addr + cdc_len - 1)) begin
                            cdc_read_ptr <= cdc_read_ptr + 1; // Move to the next byte
                        end else begin
                            state <= S_FINISH; // All requested bytes uploaded
                        end
                    end
                    // If we have uploaded everything, but the last byte is still pending
                    if (cdc_read_ptr >= (cdc_start_addr + cdc_len)) begin
                         state <= S_FINISH;
                    end
                end

                S_FINISH: begin
                    state <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

    // --- Combinational Logic for Control and Data ---

    // Data Capture Logic - Initialize array on reset to avoid X propagation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize data buffers to avoid X propagation
            for (int i = 0; i < 6; i++) begin
                captured_data[i] <= 8'h00;
            end
        end else if (state == S_CMD_CAPTURE && cmd_data_valid) begin
            if (cmd_data_index < 6) captured_data[cmd_data_index] <= cmd_data;
        end
    end

    // CDC Write Logic (now fully generic)
    // Write enable only when in WRITE state AND pointer is within valid range
    assign handler_wr_en = (state == S_EXEC_WRITE) && (cdc_write_ptr < cdc_len);
    // The address to write to is the start_addr + the current write pointer
    assign handler_addr  = cdc_start_addr + cdc_write_ptr;
    // The data comes from the captured command payload, offset by 2 (addr and len)
    // Add boundary check to prevent array out-of-bounds access
    assign handler_wdata = ((cdc_write_ptr + 2) < 6) ? captured_data[cdc_write_ptr + 2] : 8'h00;

    // CDC Read (Upload) Logic
    // cmd_ready: 在IDLE和接收命令/数据的状态时为高，在上传和完成状态时为低
    // 参考UART和SPI handler的实现，使用明确的肯定逻辑
    assign cmd_ready     = (state == S_IDLE) ||
                           (state == S_CMD_CAPTURE) ||
                           (state == S_EXEC_SET_ADDR) ||
                           (state == S_EXEC_WRITE);
    assign upload_active = (state == S_UPLOAD_DATA);
    assign upload_req    = upload_active;
    assign upload_source = 8'h36; // Source is the CDC read command (I2C_SLAVE)
    assign upload_valid  = upload_req && upload_ready;
    // The data to upload comes from our local buffer, indexed by the read pointer
    assign upload_data   = upload_buffer[cdc_read_ptr];

endmodule