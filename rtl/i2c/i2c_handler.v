// `define DO_SIM 1 // 取消注释以用于仿真 板级验证请注释掉 仿真跑不起来一定要检查这个

module i2c_handler #(
        parameter WRITE_BUFFER_SIZE = 128,
        parameter READ_BUFFER_SIZE  = 128
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
        output wire         upload_active,
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
    
    localparam [2:0]
        S_IDLE              = 3'd0,
        S_PARSE_CONFIG      = 3'd1,
        S_PARSE_WRITE       = 3'd2,
        S_PARSE_READ        = 3'd3,
        S_EXEC_WRITE        = 3'd4,
        S_EXEC_READ         = 3'd5,
        S_UPLOAD_DATA       = 3'd6;

    reg [2:0] state;

    // Upload sub-state machine
    localparam [1:0]
        UP_IDLE = 2'd0,
        UP_SEND = 2'd1,
        UP_WAIT = 2'd2;

    reg [1:0] upload_state;

    //================================================================
    // Internal Registers
    //================================================================
    reg [7:0]   device_addr_reg;
    // reg [15:0]  reg_addr_reg; // <<< MODIFIED: Removed register address
    reg [15:0]  data_len_reg;
    reg [15:0]  data_ptr_reg;
    reg [7:0]   write_buffer [0:WRITE_BUFFER_SIZE-1];
    reg [7:0]   read_buffer  [0:READ_BUFFER_SIZE-1];

    wire        i2c_rw_done;
    wire [7:0]  i2c_rddata;
    wire        i2c_ack;

    reg         wr_req_pulse; // <<< MODIFIED: Renamed for clarity
    reg         rd_req_pulse; // <<< MODIFIED: Renamed for clarity
    reg [7:0]   wrdata_reg;
    reg         i2c_busy;

    //================================================================
    // Upload Active Signal - Combinational Logic
    //================================================================
    assign upload_active = (state == S_UPLOAD_DATA);

    //================================================================
    // Instantiate I2C Controller
    //================================================================
    i2c_control i2c_control(
        .Clk(clk), 
        .Rst_n(rst_n), 
        
        .wr_req(wr_req_pulse), // <<< MODIFIED: Renamed
        .rd_req(rd_req_pulse), // <<< MODIFIED: Renamed
        // .addr(reg_addr_reg), // <<< MODIFIED: Removed
        // .addr_mode(1'b1),    // <<< MODIFIED: Removed
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
            upload_state <= UP_IDLE;
            cmd_ready <= 1'b1;
            // reg_addr_reg <= 16'h0000; // <<< MODIFIED: Removed
            data_len_reg <= 16'h0000;
            data_ptr_reg <= 16'h0000;
            wr_req_pulse <= 1'b0;
            rd_req_pulse <= 1'b0;
            upload_req <= 1'b0;
            upload_valid <= 1'b0;
            upload_data <= 8'h00;
            upload_source <= 8'h06;
            i2c_busy <= 1'b0;
        end else begin
            // Default assignments
            wr_req_pulse <= 1'b0;
            rd_req_pulse <= 1'b0;
            upload_valid <= 1'b0;

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
                                // <<< MODIFIED: Write command no longer contains register address.
                                // Length must be > 0.
                                if (cmd_length > 0 && cmd_length <= WRITE_BUFFER_SIZE) begin
                                    cmd_ready <= 1'b0; 
                                    state <= S_PARSE_WRITE;
                                end
                            end
                            CMD_I2C_READ: begin
                                // Read command payload is 2 bytes (length only)
                                if (cmd_length == 2) begin 
                                    cmd_ready <= 1'b0;
                                    state <= S_PARSE_READ;
                                end
                            end
                        endcase
                    end
                end

                S_PARSE_CONFIG: begin
                    cmd_ready <= 1'b1; 
                    if (cmd_data_valid) begin
                        case(cmd_data_index)
                            0: device_addr_reg <= cmd_data;
                            default: ;
                        endcase
                    end
                    if (cmd_done) state <= S_IDLE;
                end

                S_PARSE_WRITE: begin
                    cmd_ready <= 1'b1;
                    if (cmd_data_valid) begin
                        // <<< MODIFIED: No register address, all data goes to write_buffer
                        if (cmd_data_index < WRITE_BUFFER_SIZE) begin
                            write_buffer[cmd_data_index] <= cmd_data;
                        end
                    end
                    if (cmd_done) begin
                        // <<< MODIFIED: data_len is the total command length
                        data_len_reg <= cmd_length;
                        data_ptr_reg <= 0;
                        state <= S_EXEC_WRITE;
                    end
                end

                S_PARSE_READ: begin
                    cmd_ready <= 1'b1;
                    if (cmd_data_valid) begin
                        // Parse 2-byte length directly.
                        case(cmd_data_index)
                            0: data_len_reg[15:8] <= cmd_data; // Byte 0 is length[15:8]
                            1: data_len_reg[7:0]  <= cmd_data; // Byte 1 is length[7:0]
                            default: ;
                        endcase
                    end
                    if (cmd_done) begin
                        data_ptr_reg <= 0;
                        state <= S_EXEC_READ;
                    end
                end

                S_EXEC_WRITE: begin
                    if (!i2c_busy) begin
                        if (data_ptr_reg < data_len_reg) begin
                            wrdata_reg <= write_buffer[data_ptr_reg];
                            wr_req_pulse <= 1'b1;
                            i2c_busy <= 1'b1;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else if (i2c_rw_done) begin
                        data_ptr_reg <= data_ptr_reg + 1;
                        // reg_addr_reg <= reg_addr_reg + 1; // <<< MODIFIED: Removed address auto-increment
                        i2c_busy <= 1'b0;
                    end
                end
                
                S_EXEC_READ: begin
                    if (!i2c_busy) begin
                        if (data_ptr_reg < data_len_reg) begin
                            rd_req_pulse <= 1'b1;
                            i2c_busy <= 1'b1;
                        end else begin
                            data_ptr_reg <= 0;
                            state <= S_UPLOAD_DATA;
                        end
                    end else if (i2c_rw_done) begin
                        if (data_ptr_reg < READ_BUFFER_SIZE) begin
                            read_buffer[data_ptr_reg] <= i2c_rddata;
                        end
                        data_ptr_reg <= data_ptr_reg + 1;
                        // reg_addr_reg <= reg_addr_reg + 1; // <<< MODIFIED: Removed address auto-increment
                        i2c_busy <= 1'b0;
                    end
                end

                S_UPLOAD_DATA: begin
                    if (data_ptr_reg >= data_len_reg) begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase

            // ================================================================
            // Upload Sub-State Machine
            // ================================================================
            case (upload_state)
                UP_IDLE: begin
                    if ((state == S_UPLOAD_DATA) && (data_ptr_reg < data_len_reg) && upload_ready) begin
                        upload_req <= 1'b1;
                        upload_data <= read_buffer[data_ptr_reg];
                        upload_source <= CMD_I2C_READ;
                        upload_valid <= 1'b1;
                        upload_state <= UP_SEND;
                    end else begin
                        upload_req <= 1'b0;
                        upload_valid <= 1'b0;
                    end
                end

                UP_SEND: begin
                    upload_valid <= 1'b0;
                    if (upload_ready) begin
                        data_ptr_reg <= data_ptr_reg + 1;
                        upload_state <= UP_WAIT;
                    end
                end

                UP_WAIT: begin
                    upload_req <= 1'b0;
                    upload_valid <= 1'b0;
                    if ((state == S_UPLOAD_DATA) && (data_ptr_reg < data_len_reg) && upload_ready) begin
                        upload_state <= UP_IDLE;
                    end else if (data_ptr_reg >= data_len_reg) begin
                        upload_state <= UP_IDLE;
                    end
                end

                default: upload_state <= UP_IDLE;
            endcase
        end
    end

endmodule