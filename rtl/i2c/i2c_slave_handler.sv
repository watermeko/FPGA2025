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
    // output logic        upload_active,
    // output logic        upload_req,
    // output logic [7:0]  upload_data,
    // output logic [7:0]  upload_source,
    // output logic        upload_valid,
    // input  logic        upload_ready,

    // Physical I2C Slave Interface
    input wire          i2c_scl,
    inout wire          i2c_sda
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

    // The shared register map (unchanged)
    reg_map u_reg_map (
        .clk           (clk), 
        .rst_n         (rst_n),
        .addr          (handler_wr_en ? handler_addr : core_addr),
        .wdata         (handler_wr_en ? handler_wdata : core_wdata),
        .wr_en_wdata   (core_wr_en_wdata_sync | handler_wr_en),
        .rdata         (core_rdata),

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
    localparam S_EXEC_SET_ADDR     = 4'd2; // For command 0x14
    localparam S_EXEC_WRITE        = 4'd3; // For command 0x15
    localparam S_EXEC_READ_SETUP   = 4'd4; // For command 0x16
    localparam S_UPLOAD_DATA       = 4'd5;
    localparam S_FINISH            = 4'd6;

    logic [3:0] state;
    
    // Registers for command parameters
    logic [7:0]  captured_data [0:5]; // Buffer for up to 6 bytes of command payload
    logic [7:0]  cdc_start_addr;
    logic [7:0]  cdc_len;
    logic [7:0]  cdc_write_ptr; // Pointer for writing multiple bytes
    logic [7:0]  cdc_read_ptr;  // Pointer for reading multiple bytes
    // logic [7:0]  upload_buffer [0:3]; // Buffer to hold data for upload

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
                    if (cmd_start) state <= S_CMD_CAPTURE;
                end
                
                S_CMD_CAPTURE: begin
                    if (cmd_done) begin
                        // Latch command parameters after capture is done
                        cdc_start_addr <= captured_data[0];
                        cdc_len <= captured_data[1];
                        case (cmd_type)
                            8'h14: state <= S_EXEC_SET_ADDR;
                            8'h15: begin
                                cdc_write_ptr <= '0; // Reset write pointer
                                state <= S_EXEC_WRITE;
                            end
                            8'h16: state <= S_EXEC_READ_SETUP;
                            default: state <= S_FINISH;
                        endcase
                    end
                end
                
                S_EXEC_SET_ADDR: begin
                    // Payload for 0x14 is just the address itself
                    i2c_slave_address <= captured_data[0][6:0];
                    state <= S_FINISH;
                end
                
                S_EXEC_WRITE: begin
                    // This state iterates 'cdc_len' times to write multiple bytes
                    if (cdc_write_ptr < cdc_len) begin
                        cdc_write_ptr <= cdc_write_ptr + 1;
                        // Stay in this state to write the next byte in the next cycle
                    end else begin
                        state <= S_FINISH; // All bytes written
                    end
                end

                S_EXEC_READ_SETUP: begin
                    // Copy data from reg_map outputs to our local upload buffer
                    // upload_buffer[0] <= reg_val_0;
                    // upload_buffer[1] <= reg_val_1;
                    // upload_buffer[2] <= reg_val_2;
                    // upload_buffer[3] <= reg_val_3;
                    cdc_read_ptr <= cdc_start_addr; // Start reading from the specified address
                    state <= S_UPLOAD_DATA;
                end
                
                // S_UPLOAD_DATA: begin
                //     // Wait until the current byte is successfully uploaded
                //     if (upload_req && upload_ready) begin
                //         // Check if we have more bytes to upload
                //         if (cdc_read_ptr < (cdc_start_addr + cdc_len - 1)) begin
                //             cdc_read_ptr <= cdc_read_ptr + 1; // Move to the next byte
                //         end else begin
                //             state <= S_FINISH; // All requested bytes uploaded
                //         end
                //     end
                //     // If we have uploaded everything, but the last byte is still pending
                //     if (cdc_read_ptr >= (cdc_start_addr + cdc_len)) begin
                //          state <= S_FINISH;
                //     end
                // end
                
                S_FINISH: begin
                    state <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

    // --- Combinational Logic for Control and Data ---

    // Data Capture Logic (no changes needed here)
    always_ff @(posedge clk) begin
        if (state == S_CMD_CAPTURE && cmd_data_valid) begin
            if (cmd_data_index < 6) captured_data[cmd_data_index] <= cmd_data;
        end
    end

    // CDC Write Logic (now fully generic)
    assign handler_wr_en = (state == S_EXEC_WRITE); // Active for each byte to be written
    // The address to write to is the start_addr + the current write pointer
    assign handler_addr  = cdc_start_addr + cdc_write_ptr;
    // The data comes from the captured command payload, offset by 2 (addr and len)
    assign handler_wdata = captured_data[cdc_write_ptr + 2];

    // CDC Read (Upload) Logic
    assign cmd_ready     = (state == S_IDLE);
    // assign upload_active = (state == S_UPLOAD_DATA);
    // assign upload_req    = upload_active;
    // assign upload_source = 8'h16; // Source is the CDC read command
    // assign upload_valid  = upload_req && upload_ready;
    // // The data to upload comes from our local buffer, indexed by the read pointer
    // assign upload_data   = upload_buffer[cdc_read_ptr];

endmodule