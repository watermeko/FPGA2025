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
        S_UPLOAD_WAIT       = 4'd9,
        S_EXEC_WRITE_UPDATE = 4'd10; // <--- 新增状态

    localparam DELAY_CYCLES = 250;

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
    reg         rdreg_req_pulse; // <--- 修改: 替换 rd_start 和 rd_continue
    reg [7:0]   wrdata_reg;
    
    reg [7:0]   latched_rddata;
    reg [7:0]   delay_counter;
    

    //================================================================
    // Instantiate I2C Controller
    //================================================================
    i2c_control i2c_control(
        .Clk(clk), 
        .Rst_n(rst_n), 
        
        .wrreg_req(wrreg_req_pulse),
        .rdreg_req(rdreg_req_pulse), // <--- 修改: 使用新的单次读请求
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
            rdreg_req_pulse <= 1'b0; // <--- 修改: 初始化新信号
            upload_req <= 1'b0;
            upload_valid <= 1'b0;
            upload_data <= 8'h00;
            upload_source <= 8'h00;
            delay_counter <= 0; // <--- 在复位逻辑中初始化计数器
        end else begin
            // 默认将脉冲信号拉低
            wrreg_req_pulse <= 1'b0;
            rdreg_req_pulse <= 1'b0; // <--- 修改: 默认拉低
            upload_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    cmd_ready <= 1'b1;
                    upload_req <= 1'b0;
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
                    // ... (无变化)
                    cmd_ready <= 1'b1; 
                    if (cmd_data_valid) device_addr_reg <= cmd_data;
                    if (cmd_done) state <= S_IDLE;
                end

                S_PARSE_WRITE: begin
                    // ... (无变化)
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
                        state <= S_EXEC_WRITE_START;
                    end
                end

                S_PARSE_READ: begin
                    // ... (无变化)
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
                        state <= S_EXEC_READ_START;
                    end
                end

                S_EXEC_WRITE_START: begin
                    if (data_ptr_reg < data_len_reg) begin
                        // 在启动写操作时，确保计数器不会意外增加
                        delay_counter <= 0; // (可选但良好的习惯)
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
                        reg_addr_reg <= reg_addr_reg + 1;
                        delay_counter <= 0; // <--- 复位/启动延时计数器
                        state <= S_EXEC_WRITE_UPDATE; // 跳转到延时状态
                    end
                end

                S_EXEC_WRITE_UPDATE: begin
                    // 逻辑无变化，但由于参数和位宽已修改，此处将产生更长的延时
                    if (delay_counter < DELAY_CYCLES - 1) begin
                        delay_counter <= delay_counter + 1;
                        state <= S_EXEC_WRITE_UPDATE; // 保持在当前状态，继续等待
                    end else begin
                        state <= S_EXEC_WRITE_START; // 延时结束，跳转到下一个操作
                    end
                end

                // --- 读逻辑重构部分 ---
                S_EXEC_READ_START: begin
                    if(data_ptr_reg < data_len_reg) begin
                        rdreg_req_pulse <= 1'b1; // <--- 修改: 发送简单的单次读请求
                        state <= S_EXEC_READ_WAIT;
                    end else begin
                        state <= S_IDLE;
                    end
                end

                S_EXEC_READ_WAIT: begin
                    if (i2c_rw_done) begin      // <--- 修改: 等待整个事务完成信号，与写逻辑一致
                        latched_rddata <= i2c_rddata;
                        state <= S_UPLOAD_START;
                    end
                end
                // --- 读逻辑重构结束 ---

                S_UPLOAD_START: begin
                    upload_req <= 1'b1;
                    upload_data <= latched_rddata;
                    upload_source <= CMD_I2C_READ;
                    upload_valid <= 1'b1;
                    state <= S_UPLOAD_WAIT;
                end
                
                S_UPLOAD_WAIT: begin
                    if (1'b1) begin // 简化，无条件进入下一状态
                        upload_req <= 1'b0;
                        data_ptr_reg <= data_ptr_reg + 1;
                        reg_addr_reg <= reg_addr_reg + 1; // <--- 新增这一行
                        state <= S_EXEC_READ_START;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule