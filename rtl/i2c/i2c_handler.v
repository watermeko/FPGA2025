/******************************************************************
*   i2c_handler.v (最终修正版)
*   Description:
*       - 支持连续多字节读操作。
******************************************************************/
`define DO_SIM 1 // 取消注释以用于仿真 板级验证请注释掉 仿真跑不起来一定要检查这个
module i2c_handler #(
        parameter WRITE_BUFFER_SIZE = 128
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
    // I2C Command Codes & State Machine
    //================================================================
    localparam CMD_I2C_CONFIG = 8'h04;
    localparam CMD_I2C_WRITE  = 8'h05;
    localparam CMD_I2C_READ   = 8'h06;
    
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
    // Internal Registers
    //================================================================
    reg [7:0] device_addr_reg;
    reg [15:0]  reg_addr_reg;
    reg [15:0]  data_len_reg;
    reg [15:0]  data_ptr_reg;
    reg [7:0]   write_buffer [0:WRITE_BUFFER_SIZE-1];
    
    wire        i2c_rw_done;
    wire [7:0]  i2c_rddata;
    wire        i2c_ack;

    reg         wrreg_req_pulse;
    //reg       rdreg_req_pulse; // 已废弃
    reg         rd_start_req_pulse;
    reg         rd_continue_req_pulse;
    reg [7:0]   wrdata_reg;
    reg         is_last_byte_reg;
    
    reg [7:0]   latched_rddata;

    //================================================================
    // Instantiate I2C Controller
    //================================================================
    i2c_control i2c_control(
        .Clk(clk), 
        .Rst_n(rst_n), 
        
        .wrreg_req(wrreg_req_pulse),
        // .rdreg_req(rdreg_req_pulse), // <--- 已删除
        .rd_start_req(rd_start_req_pulse),
        .rd_continue_req(rd_continue_req_pulse),
        .addr(reg_addr_reg),
        .addr_mode(1'b1),
        .wrdata(wrdata_reg),
        .rddata(i2c_rddata),
        .device_id({device_addr_reg[6:0], 1'b0}),
        .RW_Done(i2c_rw_done),
        .ack(i2c_ack),
        .is_last_byte(is_last_byte_reg),
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
            // rdreg_req_pulse <= 1'b0; // <--- 已删除
            rd_start_req_pulse <= 1'b0;
            rd_continue_req_pulse <= 1'b0;
            upload_req <= 1'b0;
            upload_valid <= 1'b0;
            upload_data <= 8'h00;
            upload_source <= 8'h00;
            is_last_byte_reg <= 1'b0;
        end else begin
            // 默认将脉冲信号拉低
            wrreg_req_pulse <= 1'b0;
            rd_start_req_pulse <= 1'b0;
            rd_continue_req_pulse <= 1'b0;
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
                    if (cmd_data_valid) begin 
                        device_addr_reg <= cmd_data;
                    end
                    if (cmd_done) begin
                        state <= S_IDLE;
                    end
                end

                S_PARSE_WRITE: begin
                    cmd_ready <= 1'b1;
                    if (cmd_data_valid) begin
                        case(cmd_data_index)
                            0: reg_addr_reg[15:8] <= cmd_data;
                            1: reg_addr_reg[7:0]  <= cmd_data;
                            default: begin
                                if (cmd_data_index - 2 < WRITE_BUFFER_SIZE) begin
                                    write_buffer[cmd_data_index - 2] <= cmd_data;
                                end
                            end
                        endcase
                    end
                    if (cmd_done) begin
                        data_len_reg <= cmd_length - 2;
                        data_ptr_reg <= 0;
                        state <= S_EXEC_WRITE_START;
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
                        $display("TIME=%0t : Read command parsed, data_len_reg=%0d", $time, data_len_reg);
                        state <= S_EXEC_READ_START;
                    end
                end

                S_EXEC_WRITE_START: begin
                    if (data_ptr_reg < data_len_reg) begin
                        wrdata_reg <= write_buffer[data_ptr_reg];
                        wrreg_req_pulse <= 1'b1;
                        state <= S_EXEC_WRITE_WAIT;
                    end else begin
                        state <= S_IDLE;
                    end
                end
                
                S_EXEC_WRITE_WAIT: begin
                    if (i2c_rw_done) begin
                        data_ptr_reg <= data_ptr_reg + 1;
                        state <= S_EXEC_WRITE_START;
                    end
                end

                S_EXEC_READ_START: begin
                    if(data_ptr_reg < data_len_reg) begin
                        is_last_byte_reg <= (data_ptr_reg == data_len_reg - 1);
                        
                        if (data_ptr_reg == 0) begin
                            rd_start_req_pulse <= 1'b1;
                            $display("TIME=%0t : I2C_HANDLER: Starting READ transaction for %0d bytes.", $time, data_len_reg);
                        end else begin
                            rd_continue_req_pulse <= 1'b1;
                            $display("TIME=%0t : I2C_HANDLER: Continuing READ for byte %0d.", $time, data_ptr_reg);
                        end
                        
                        state <= S_EXEC_READ_WAIT;
                    end else begin
                        $display("TIME=%0t : I2C_HANDLER: All %0d bytes read. Returning to IDLE.", $time, data_len_reg);
                        state <= S_IDLE;
                    end
                end

                S_EXEC_READ_WAIT: begin
                    if(i2c_rw_done) begin
                        if(i2c_ack && data_ptr_reg == 0) begin
                            $error("[%0t] I2C Read failed. ACK error during address setup.", $time);
                            latched_rddata <= 8'hEE;
                        end else begin
                            latched_rddata <= i2c_rddata;
                        end
                        state <= S_UPLOAD_START;
                    end
                end

                S_UPLOAD_START: begin
                    upload_req <= 1'b1;
                    upload_data <= latched_rddata;
                    upload_source <= CMD_I2C_READ;
                    upload_valid <= 1'b1;
                    state <= S_UPLOAD_WAIT;
                end
                
                S_UPLOAD_WAIT: begin
                    if (upload_ready) begin
                        upload_req <= 1'b0;
                        data_ptr_reg <= data_ptr_reg + 1;
                        state <= S_EXEC_READ_START;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule