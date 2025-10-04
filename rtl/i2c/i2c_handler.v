/******************************************************************
*   Copyright (C) 2025 Google Inc.
*   
*   Module: i2c_handler
*   Description: 
*       Handles I2C commands from the command_processor.
*       - Parses configuration, write, and read commands.
*       - Drives the i2c_control module to perform single-byte I2C transactions.
*       - Sequences multiple single-byte transactions to handle multi-byte read/write requests.
*       - Uploads read data back to the host via the command_processor.
*
******************************************************************/
module i2c_handler #(
        parameter WRITE_BUFFER_SIZE = 128  // 定义一个用于缓存I2C写数据的缓冲区大小
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
        output reg          upload_req,
        output reg [7:0]    upload_data,
        output reg [7:0]    upload_source,
        output reg          upload_valid,
        input  wire         upload_ready
    );

    //================================================================
    // I2C Command Codes
    //================================================================
    localparam CMD_I2C_CONFIG = 8'h04;
    localparam CMD_I2C_WRITE  = 8'h05;
    localparam CMD_I2C_READ   = 8'h06;
    
    //================================================================
    // State Machine Definition
    //================================================================
    localparam [3:0]
        S_IDLE              = 4'd0,
        S_PARSE_CONFIG      = 4'd1,
        S_PARSE_WRITE       = 4'd2,
        S_PARSE_READ        = 4'd3,
        S_EXEC_WRITE_START  = 4'd4,
        S_EXEC_WRITE_WAIT   = 4'd5,
        S_EXEC_READ_START   = 4'd6,
        S_EXEC_READ_WAIT    = 4'd7,
        S_UPLOAD_START      = 4'd8,
        S_UPLOAD_WAIT       = 4'd9;

    reg [3:0] state;

    //================================================================
    // Internal Registers and Wires
    //================================================================
    // Configuration Registers
    reg [7:0] device_addr_reg;

    // Transaction Registers
    reg [15:0]  reg_addr_reg;
    reg [15:0]  data_len_reg;
    reg [15:0]  data_ptr_reg;
    reg [7:0]   write_buffer [0:WRITE_BUFFER_SIZE-1];
    
    // I2C Control signals
    wire        i2c_rw_done;
    wire [7:0]  i2c_rddata;
    wire        i2c_ack;

    reg         wrreg_req_pulse;
    reg         rdreg_req_pulse;
    reg [7:0]   wrdata_reg;
    
    // Latched read data for upload
    reg [7:0]   latched_rddata;

    //================================================================
    // Instantiate I2C Controller
    //================================================================
    i2c_control u_i2c_control (
        .Clk        (clk),
        .Rst_n      (rst_n),
        .wrreg_req  (wrreg_req_pulse),
        .rdreg_req  (rdreg_req_pulse),
        .addr       (reg_addr_reg + data_ptr_reg), // 地址自动增加
        .addr_mode  (1'b0), // 协议定义为1字节寄存器地址, 故固定为8-bit模式
        .wrdata     (wrdata_reg),
        .rddata     (i2c_rddata),
        .device_id  ({device_addr_reg, 1'b0}), // 7位地址 + W/R位(0)
        .RW_Done    (i2c_rw_done),
        .ack        (i2c_ack),
        .i2c_sclk   (i2c_scl),
        .i2c_sdat   (i2c_sda)
    );
    
    //================================================================
    // Main State Machine
    //================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            cmd_ready <= 1'b1;
            device_addr_reg <= 8'h00;
            reg_addr_reg <= 16'h0000;
            data_len_reg <= 16'h0000;
            data_ptr_reg <= 16'h0000;
            wrreg_req_pulse <= 1'b0;
            rdreg_req_pulse <= 1'b0;
            upload_req <= 1'b0;
            upload_valid <= 1'b0;
            upload_data <= 8'h00;
            upload_source <= 8'h00;
        end else begin
            // 默认将脉冲信号拉低
            wrreg_req_pulse <= 1'b0;
            rdreg_req_pulse <= 1'b0;
            upload_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    cmd_ready <= 1'b1;
                    upload_req <= 1'b0;
                    if (cmd_start) begin
                        case (cmd_type)
                            CMD_I2C_CONFIG: begin
                                state <= S_PARSE_CONFIG;
                            end
                            CMD_I2C_WRITE: begin
                                if (cmd_length > 1 && cmd_length - 1 <= WRITE_BUFFER_SIZE) begin
                                    cmd_ready <= 1'b0; // 准备接收数据，暂时不接受新指令
                                    state <= S_PARSE_WRITE;
                                end
                            end
                            CMD_I2C_READ: begin
                                if (cmd_length == 3) begin // 1B Addr + 2B Len
                                    cmd_ready <= 1'b0;
                                    state <= S_PARSE_READ;
                                end
                            end
                            default: begin
                                // Not an I2C command
                            end
                        endcase
                    end
                end

                // --- Configuration Parsing ---
                S_PARSE_CONFIG: begin
                    cmd_ready <= 1'b1; // 持续接收数据
                    if (cmd_data_valid && cmd_data_index == 4) begin // Index 0-3=Freq, 4=Addr
                        device_addr_reg <= cmd_data;
                    end
                    if (cmd_done) begin
                        state <= S_IDLE;
                    end
                end

                // --- Write Command Parsing ---
                S_PARSE_WRITE: begin
                    cmd_ready <= 1'b1;
                    if (cmd_data_valid) begin
                        if (cmd_data_index == 0) begin
                            reg_addr_reg <= {8'h00, cmd_data};
                        end else begin
                            // cmd_data_index 从1开始是数据
                            write_buffer[cmd_data_index - 1] <= cmd_data;
                        end
                    end
                    if (cmd_done) begin
                        data_len_reg <= cmd_length - 1; // 实际数据长度
                        data_ptr_reg <= 0;
                        state <= S_EXEC_WRITE_START;
                    end
                end

                // --- Read Command Parsing ---
                S_PARSE_READ: begin
                    cmd_ready <= 1'b1;
                    if (cmd_data_valid) begin
                        case(cmd_data_index)
                            0: reg_addr_reg <= {8'h00, cmd_data};
                            1: data_len_reg[15:8] <= cmd_data;
                            2: data_len_reg[7:0] <= cmd_data;
                        endcase
                    end
                    if (cmd_done) begin
                        data_ptr_reg <= 0;
                        state <= S_EXEC_READ_START;
                    end
                end
                
                // --- Write Execution ---
                S_EXEC_WRITE_START: begin
                    if (data_ptr_reg < data_len_reg) begin
                        wrdata_reg <= write_buffer[data_ptr_reg];
                        wrreg_req_pulse <= 1'b1;
                        state <= S_EXEC_WRITE_WAIT;
                    end else begin
                        // All bytes written
                        state <= S_IDLE;
                    end
                end
                
                S_EXEC_WRITE_WAIT: begin
                    if (i2c_rw_done) begin
                        data_ptr_reg <= data_ptr_reg + 1;
                        state <= S_EXEC_WRITE_START;
                    end
                end

                // --- Read Execution ---
                S_EXEC_READ_START: begin
                    if (data_ptr_reg < data_len_reg) begin
                        rdreg_req_pulse <= 1'b1;
                        state <= S_EXEC_READ_WAIT;
                    end else begin
                        // All bytes read and uploaded
                        state <= S_IDLE;
                    end
                end

                S_EXEC_READ_WAIT: begin
                    if (i2c_rw_done) begin
                        latched_rddata <= i2c_rddata;
                        state <= S_UPLOAD_START;
                    end
                end

                // --- Data Upload Logic ---
                S_UPLOAD_START: begin
                    upload_req <= 1'b1;
                    upload_data <= latched_rddata;
                    upload_source <= CMD_I2C_READ; // 使用功能码作为源ID
                    upload_valid <= 1'b1;
                    state <= S_UPLOAD_WAIT;
                end
                
                S_UPLOAD_WAIT: begin
                    if (upload_ready) begin
                        upload_req <= 1'b0; // 对方已接收，撤销请求
                        data_ptr_reg <= data_ptr_reg + 1;
                        state <= S_EXEC_READ_START; // 返回去读下一个字节
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule