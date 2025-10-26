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

    // // CDC Upload Bus Interface
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
    // Handler State Machine and Logic (FINAL REVISION 2)
    //================================================================
    localparam S_IDLE              = 4'd0;
    localparam S_CMD_CAPTURE       = 4'd1;
    localparam S_EXEC_ADDR         = 4'd2;
    localparam S_EXEC_WRITE_SETUP  = 4'd3;
    localparam S_EXEC_WRITE        = 4'd4; // Renamed from PULSE for clarity
    localparam S_EXEC_READ_SETUP   = 4'd5;
    localparam S_UPLOAD_DATA       = 4'd6;
    localparam S_FINISH            = 4'd7;

    logic [3:0] state;
    logic [1:0] byte_counter;
    logic [1:0] transfer_len;
    logic [7:0] captured_data [0:2];
    // logic [7:0] upload_buffer [0:1];
// --- State Machine (FIXED with explicit begin...end blocks) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            i2c_slave_address <= 7'h24;
            byte_counter <= '0;
            transfer_len <= '0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (cmd_start) state <= S_CMD_CAPTURE;
                end
                
                S_CMD_CAPTURE: begin
                    if (cmd_done) begin
                        case (cmd_type)
                            8'h14: state <= S_EXEC_ADDR;
                            8'h15: state <= S_EXEC_WRITE_SETUP;
                            // Re-enable this line if you are testing upload
                            // 8'h16: state <= S_EXEC_READ_SETUP;
                            default: state <= S_FINISH;
                        endcase
                    end
                end
                
                S_EXEC_ADDR: begin
                    i2c_slave_address <= captured_data[0][6:0];
                    state <= S_FINISH;
                end
                
                S_EXEC_WRITE_SETUP: begin
                    transfer_len <= captured_data[0];
                    byte_counter <= '0;
                    if (captured_data[0] > 0) begin
                        state <= S_EXEC_WRITE;
                    end else begin
                        state <= S_FINISH;
                    end
                end
                
                S_EXEC_WRITE: begin
                    if (byte_counter < transfer_len - 1) begin
                        byte_counter <= byte_counter + 1;
                        state <= S_EXEC_WRITE;
                    end else begin
                        state <= S_FINISH;
                    end
                end

                // This block is disabled if you are not testing upload
                // S_EXEC_READ_SETUP: begin
                //     upload_buffer[0] <= reg_val_2;
                //     upload_buffer[1] <= reg_val_3;
                //     transfer_len <= captured_data[0];
                //     if (captured_data[0] > 0) begin
                //         state <= S_UPLOAD_DATA;
                //     end else begin
                //         state <= S_FINISH;
                //     end
                // end
                
                // S_UPLOAD_DATA: begin
                //     if ((transfer_len > 0) && (upload_req && upload_ready)) begin
                //         if (byte_counter == (transfer_len - 1'b1)) begin
                //             state <= S_FINISH;
                //         end else begin
                //             byte_counter <= byte_counter + 1;
                //         end
                //     end else if (transfer_len == 0) begin
                //         state <= S_FINISH;
                //     end
                // end
                
                S_FINISH: begin
                    state <= S_IDLE;
                end
                
                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end


    // --- Data Capture Logic ---
    always_ff @(posedge clk) begin
        if (state == S_CMD_CAPTURE && cmd_data_valid) begin
            if (cmd_data_index < 3) captured_data[cmd_data_index] <= cmd_data;
        end
    end

    // <<< CRITICAL: Write enable is a PULSE, active for one cycle per byte >>>
    // We are in S_EXEC_WRITE for N cycles, so this will generate N pulses.
    assign handler_wr_en = (state == S_EXEC_WRITE);
    assign handler_addr  = byte_counter;
    assign handler_wdata = (byte_counter == 0) ? captured_data[1] : captured_data[2];

    // ... (Control and Upload signals' assign statements are now correct because the state machine loop is fixed) ...
    assign cmd_ready = (state == S_IDLE);
    // assign upload_active = (state == S_UPLOAD_DATA);
    // assign upload_req    = upload_active; // Simpler req logic
    // assign upload_source = 8'h07;
    // assign upload_valid  = upload_req && upload_ready;
    // assign upload_data   = upload_buffer[byte_counter];

endmodule