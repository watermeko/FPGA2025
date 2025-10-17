//`define DO_SIM 1 // 取消注释以用于仿真 板级验证请注释掉 仿真跑不起来一定要检查这个

module i2c_handler #(
        parameter WRITE_BUFFER_SIZE = 128,
        parameter READ_BUFFER_SIZE  = 128  // <<< NEW: Added parameter for read buffer
    )(
        // System Signals
        input wire          clk,
        input wire          rst_n,

        // Command Interface from command_processor
        input wire [7:0]    cmd_type,
        input wire [15:0]   cmd_length,
        input wire [7:0]    cmd_data,
        input wire [15:0]   cmd_data_index,
        input wire          cmd_start,
        input wire          cmd_data_valid,
        input wire          cmd_done,
        output reg          cmd_ready,

        // I2C Physical Interface
        output wire         i2c_scl,
        inout  wire         i2c_sda,

        // Data Upload Interface to command_processor
        output reg          upload_active, 
        output reg          upload_req,
        output reg [7:0]    upload_data,
        output reg [7:0]    upload_source,
        output reg          upload_valid,
        input  wire         upload_ready
    );

    //================================================================
    // I2C Command Codes & State Machine
    //================================================================
    localparam CMD_I2C_CONFIG = 8'h04;
    localparam CMD_I2C_WRITE  = 8'h05;
    localparam CMD_I2C_READ   = 8'h06;
    
    // <<< CHANGED: Simplified state machine
    localparam [2:0]
        S_IDLE              = 3'd0,
        S_PARSE_CONFIG      = 3'd1,
        S_PARSE_WRITE       = 3'd2,
        S_PARSE_READ        = 3'd3,
        S_EXEC_WRITE        = 3'd4, // Handles all bytes in a write command
        S_EXEC_READ         = 3'd5, // Handles all bytes in a read command
        S_UPLOAD_DATA       = 3'd6; // Uploads all read data in a block

    reg [2:0] state;

    //================================================================
    // Internal Registers
    //================================================================
    reg [7:0]   device_addr_reg;
    reg [15:0]  reg_addr_reg;
    reg [15:0]  data_len_reg;
    reg [15:0]  data_ptr_reg;
    reg [7:0]   write_buffer [0:WRITE_BUFFER_SIZE-1];
    reg [7:0]   read_buffer  [0:READ_BUFFER_SIZE-1]; // <<< NEW: Buffer for read data

    wire        i2c_rw_done;
    wire [7:0]  i2c_rddata;
    wire        i2c_ack;

    reg         wrreg_req_pulse;
    reg         rdreg_req_pulse;
    reg [7:0]   wrdata_reg;
    reg         i2c_busy; // <<< NEW: Flag to track I2C core status

    //================================================================
    // Instantiate I2C Controller
    //================================================================
    i2c_control i2c_control(
        .Clk(clk), 
        .Rst_n(rst_n), 
        
        .wrreg_req(wrreg_req_pulse),
        .rdreg_req(rdreg_req_pulse),
        .addr(reg_addr_reg),
        .addr_mode(1'b1),
        .wrdata(wrdata_reg),
        .rddata(i2c_rddata),
        .device_id({device_addr_reg[6:0], 1'b0}),
        .RW_Done(i2c_rw_done),
        .ack(i2c_ack),
        
    `ifdef DO_SIM
        .dly_cnt_max(250-1),
    `else   
        .dly_cnt_max(250000-1),
    `endif
        .i2c_sclk(i2c_scl),
        .i2c_sdat(i2c_sda)
    );
    
    //================================================================
    // Main State Machine
    //================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            cmd_ready <= 1'b1;
            device_addr_reg <= 8'h50;
            reg_addr_reg <= 16'h0000;
            data_len_reg <= 16'h0000;
            data_ptr_reg <= 16'h0000;
            wrreg_req_pulse <= 1'b0;
            rdreg_req_pulse <= 1'b0;
            upload_req <= 1'b0;
            upload_valid <= 1'b0;
            upload_data <= 8'h00;
            upload_source <= 8'h00;
            upload_active <= 1'b0;
            i2c_busy <= 1'b0;
        end else begin
            // Default assignments
            wrreg_req_pulse <= 1'b0;
            rdreg_req_pulse <= 1'b0;
            upload_valid <= 1'b0;
            upload_active <= 1'b0;

            case (state)
                S_IDLE: begin
                    cmd_ready <= 1'b1;
                    upload_req <= 1'b0;
                    i2c_busy <= 1'b0;
                    data_ptr_reg <= 0;

                    if (cmd_start) begin
                        case (cmd_type)
                            CMD_I2C_CONFIG: state <= S_PARSE_CONFIG;
                            CMD_I2C_WRITE: begin
                                if (cmd_length > 2 && cmd_length - 2 <= WRITE_BUFFER_SIZE) begin
                                    cmd_ready <= 1'b0; 
                                    state <= S_PARSE_WRITE;
                                end
                            end
                            CMD_I2C_READ: begin
                                if (cmd_length == 4) begin 
                                    cmd_ready <= 1'b0;
                                    state <= S_PARSE_READ;
                                end
                            end
                        endcase
                    end
                end

                S_PARSE_CONFIG: begin
                    cmd_ready <= 1'b1; 
                    if (cmd_data_valid) device_addr_reg <= cmd_data;
                    if (cmd_done) state <= S_IDLE;
                end

                S_PARSE_WRITE: begin
                    cmd_ready <= 1'b1;
                    if (cmd_data_valid) begin
                        case(cmd_data_index)
                            0: reg_addr_reg[15:8] <= cmd_data;
                            1: reg_addr_reg[7:0]  <= cmd_data;
                            default: if (cmd_data_index - 2 < WRITE_BUFFER_SIZE) write_buffer[cmd_data_index - 2] <= cmd_data;
                        endcase
                    end
                    if (cmd_done) begin
                        data_len_reg <= cmd_length - 2;
                        data_ptr_reg <= 0;
                        state <= S_EXEC_WRITE; // Transition to the consolidated write state
                    end
                end

                S_PARSE_READ: begin
                    cmd_ready <= 1'b1;
                    if (cmd_data_valid) begin
                        case(cmd_data_index)
                            0: reg_addr_reg[15:8] <= cmd_data;
                            1: reg_addr_reg[7:0]  <= cmd_data;
                            2: data_len_reg[15:8] <= cmd_data;
                            3: data_len_reg[7:0]  <= cmd_data;
                        endcase
                    end
                    if (cmd_done) begin
                        data_ptr_reg <= 0;
                        state <= S_EXEC_READ; // Transition to the consolidated read state
                    end
                end

                // <<< NEW: Consolidated state to write all bytes
                S_EXEC_WRITE: begin
                    if (!i2c_busy) begin
                        if (data_ptr_reg < data_len_reg) begin
                            wrdata_reg <= write_buffer[data_ptr_reg];
                            wrreg_req_pulse <= 1'b1;
                            i2c_busy <= 1'b1;
                        end else begin
                            // All bytes have been written
                            state <= S_IDLE;
                        end
                    end else if (i2c_rw_done) begin
                        // Previous write finished, prepare for next
                        data_ptr_reg <= data_ptr_reg + 1;
                        reg_addr_reg <= reg_addr_reg + 1;
                        i2c_busy <= 1'b0;
                    end
                end
                
                // <<< NEW: Consolidated state to read all bytes into a buffer
                S_EXEC_READ: begin
                    if (!i2c_busy) begin
                        if (data_ptr_reg < data_len_reg) begin
                            rdreg_req_pulse <= 1'b1;
                            i2c_busy <= 1'b1;
                        end else begin
                            // All bytes have been read, reset pointer for upload
                            data_ptr_reg <= 0;
                            state <= S_UPLOAD_DATA;
                        end
                    end else if (i2c_rw_done) begin
                        if (data_ptr_reg < READ_BUFFER_SIZE) begin
                            read_buffer[data_ptr_reg] <= i2c_rddata;
                        end
                        data_ptr_reg <= data_ptr_reg + 1;
                        reg_addr_reg <= reg_addr_reg + 1;
                        i2c_busy <= 1'b0;
                    end
                end

                // <<< NEW: State to upload all collected data
                S_UPLOAD_DATA: begin
                    upload_req <= 1'b1;
                    upload_active <= 1'b1;
                    
                    if (data_ptr_reg < data_len_reg) begin
                        upload_data <= read_buffer[data_ptr_reg];
                        upload_source <= CMD_I2C_READ;
                        upload_valid <= 1'b1;

                        if (upload_ready) begin
                            data_ptr_reg <= data_ptr_reg + 1;
                        end
                    end else begin
                        // All data uploaded
                        upload_req <= 1'b0;
                        upload_active <= 1'b0;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule