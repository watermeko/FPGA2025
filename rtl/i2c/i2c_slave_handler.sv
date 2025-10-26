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
    inout wire          i2c_scl,
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

    assign sda_in = i2c_sda;

    bidir u_sda ( .pad(i2c_sda), .to_pad(sda_out), .oe(~sda_out) );

    // Instantiate the modified i2c_slave with the configurable address
    i2c_slave u_i2c_slave (
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
        .register_0    (),
        .register_1    (),
        .register_2    (),
        .register_3    ()
    );

    //================================================================
    // Handler State Machine and Logic (FINAL REVISION)
    //================================================================
    localparam S_IDLE              = 4'd0;
    localparam S_CMD_CAPTURE       = 4'd1;
    localparam S_CMD_EXEC_ADDR     = 4'd2;
    localparam S_CMD_EXEC_WRITE_SETUP = 4'd3; // New
    localparam S_CMD_EXEC_WRITE_PULSE = 4'd4; // New
    localparam S_CMD_READ_SETUP    = 4'd5;
    localparam S_UPLOAD_DATA       = 4'd6;
    localparam S_FINISH            = 4'd7;

    logic [3:0] state;
    logic [1:0] byte_counter;
    logic [1:0] transfer_len;
    logic [7:0] captured_data [0:2];
    logic [7:0] upload_buffer [0:1];

    // --- State Machine ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; i2c_slave_address <= 7'h24; byte_counter <= '0; transfer_len <= '0;
        end else begin
            case (state)
                S_IDLE:             if (cmd_start) state <= S_CMD_CAPTURE;
                
                S_CMD_CAPTURE:      if (cmd_done) case (cmd_type)
                                        8'h14: state <= S_CMD_EXEC_ADDR;
                                        8'h15: state <= S_CMD_EXEC_WRITE_SETUP; // Go to write setup
                                        8'h16: state <= S_CMD_READ_SETUP;
                                        default: state <= S_FINISH;
                                    endcase
                
                S_CMD_EXEC_ADDR:    begin i2c_slave_address <= captured_data[0][6:0]; state <= S_FINISH; end
                
                // Setup the first byte write
                S_CMD_EXEC_WRITE_SETUP: begin
                    transfer_len <= captured_data[0];
                    byte_counter <= '0;
                    if (captured_data[0] > 0) state <= S_CMD_EXEC_WRITE_PULSE; else state <= S_FINISH;
                end
                
                // Generate a single-cycle write pulse. Then, decide what's next.
                S_CMD_EXEC_WRITE_PULSE: begin
                    if (byte_counter < transfer_len - 1) begin
                        byte_counter <= byte_counter + 1;
                        state <= S_CMD_EXEC_WRITE_PULSE; // Loop to write the next byte
                    end else begin
                        state <= S_FINISH; // All bytes written
                    end
                end

                S_CMD_READ_SETUP:   begin
                                        upload_buffer[0] <= u_reg_map.registers[2];
                                        upload_buffer[1] <= u_reg_map.registers[3];
                                        transfer_len <= captured_data[0];
                                        byte_counter <= '0;
                                        state <= S_UPLOAD_DATA;
                                    end
                
                S_UPLOAD_DATA:      if ((transfer_len > 0) && (upload_req && upload_ready))
                                        if (byte_counter == (transfer_len - 1'b1)) state <= S_FINISH; else byte_counter <= byte_counter + 1;
                                    else if (transfer_len == 0) state <= S_FINISH;
                
                S_FINISH:           state <= S_IDLE;
                
                default:            state <= S_IDLE;
            endcase
        end
    end

    // --- Data Capture Logic ---
    always_ff @(posedge clk) begin
        if (state == S_CMD_CAPTURE && cmd_data_valid) begin
            if (cmd_data_index < 3) captured_data[cmd_data_index] <= cmd_data;
        end
    end

    // --- Write Execution Logic ---
    // <<< CRITICAL FIX: The write enable is ONLY active in the PULSE state >>>
    assign handler_wr_en = (state == S_CMD_EXEC_WRITE_PULSE);
    assign handler_addr  = byte_counter;
    assign handler_wdata = (byte_counter == 0) ? captured_data[1] : captured_data[2];

    // ... [ The rest of the module (control signals, upload logic) remains the same as the previous correct version ] ...
    assign cmd_ready = (state == S_IDLE);
    assign upload_active = (state == S_UPLOAD_DATA);
    assign upload_req    = upload_active && (byte_counter < transfer_len);
    assign upload_source = 8'h07;
    assign upload_valid  = upload_req && upload_ready;
    assign upload_data   = upload_buffer[byte_counter];

endmodule