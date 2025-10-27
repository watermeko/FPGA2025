// author：nanimonai
// page rd/wr
// 这个SCL速率对不齐的话在modelsim的eeprom仿真里面会报错，属正常现象---25.10.27
module i2c_handler #(
        parameter WRITE_BUFFER_SIZE = 32,
        parameter READ_BUFFER_SIZE  = 32
    )(
        // System Signals
        input wire          clk,
        input wire          rst_n,

        // Command Interface
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

        // Data Upload Interface
        output wire         upload_active,
        output reg          upload_req,
        output reg [7:0]    upload_data,
        output reg [7:0]    upload_source,
        output reg          upload_valid,
        input  wire         upload_ready
    );



    //================================================================
    // SCL Frequency Calculation Parameters
    //================================================================
    // 假设系统时钟为 50MHz
    localparam SYS_CLK_FREQ = 50_000_000;
    // SCL_Freq = SYS_CLK_FREQ / (scl_cnt_max + 1) / 4
    // scl_cnt_max = (SYS_CLK_FREQ / SCL_Freq / 4) - 1
    localparam SCL_100KHZ_CNT = (SYS_CLK_FREQ / 100_000 / 4) - 1; // 124
    localparam SCL_400KHZ_CNT = (SYS_CLK_FREQ / 400_000 / 4) - 1; // 30


    //================================================================
    // States and Parameters
    //================================================================
    // <<< MODIFIED: Updated function codes
    localparam CMD_I2C_WRITE_NOADDR   = 8'h02;
    localparam CMD_I2C_READ_NOADDR    = 8'h03;
    localparam CMD_I2C_CONFIG         = 8'h04;
    localparam CMD_I2C_WRITE_ADDR     = 8'h05;
    localparam CMD_I2C_READ_ADDR      = 8'h06;
    
    localparam [3:0] // State vector increased to handle more states
        S_IDLE              = 4'd0, S_PARSE_CONFIG      = 4'd1,
        S_PARSE_WR_NOADDR   = 4'd2, S_PARSE_RD_NOADDR   = 4'd3,
        S_PARSE_WR_ADDR     = 4'd4, S_PARSE_RD_ADDR     = 4'd5,
        S_EXEC_WRITE        = 4'd6, S_EXEC_READ         = 4'd7,
        S_UPLOAD_DATA       = 4'd8;
    reg [3:0] state;

    localparam [1:0] UP_IDLE = 2'd0, UP_SEND = 2'd1, UP_WAIT = 2'd2;
    reg [1:0] upload_state;

    //================================================================
    // Internal Registers
    //================================================================
    reg [7:0]   device_addr_reg;
    reg [15:0]  reg_addr_reg;       // <<< NEW: To store register address
    reg         addr_mode_reg;      // <<< NEW: 1'b1 for 16-bit, 1'b0 for 8-bit
    reg         use_reg_addr_reg;   // <<< NEW: Control signal for i2c_control
    reg [15:0]  data_len_reg;
    reg [15:0]  upload_ptr_reg;
    reg [7:0]   write_buffer [0:WRITE_BUFFER_SIZE-1];
    reg [7:0]   read_buffer  [0:READ_BUFFER_SIZE-1];

    wire        i2c_rw_done;
    wire        i2c_ack;
    reg         wr_req_pulse;
    reg         rd_req_pulse;
    reg         i2c_busy;
    reg [7:0]   upload_source_reg; // To hold the source command for upload
    reg [19:0]  scl_cnt_max_reg;  // <<< NEW: 用于存储SCL分频计数值的寄存器

    assign upload_active = (state == S_UPLOAD_DATA);

    //================================================================
    // Instantiate The Unified I2C Controller
    //================================================================
    i2c_control #(
        .WRITE_BUFFER_SIZE(WRITE_BUFFER_SIZE),
        .READ_BUFFER_SIZE(READ_BUFFER_SIZE)
    ) i2c_control_inst (
        .Clk(clk), 
        .Rst_n(rst_n),
        .i2c_sclk(i2c_scl),
        .i2c_sdat(i2c_sda),
        // --- Unified Interface ---
        .wr_req(wr_req_pulse),
        .rd_req(rd_req_pulse),
        .use_reg_addr(use_reg_addr_reg), // <<< CONNECTED
        .addr(reg_addr_reg),             // <<< CONNECTED
        .addr_mode(addr_mode_reg),       // <<< CONNECTED
        .data_len(data_len_reg),
        .write_buffer(write_buffer),
        .read_buffer(read_buffer),
        // --- Common Interface ---
        .scl_cnt_max(scl_cnt_max_reg), // <<< NEW: 连接SCL配置寄存器
        .device_id({device_addr_reg[6:0], 1'b0}),
        .RW_Done(i2c_rw_done),
        .ack(i2c_ack)
    );
    
    //================================================================
    // Main State Machine
    //================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            upload_state <= UP_IDLE;
            cmd_ready <= 1'b1;
            reg_addr_reg <= 16'h0;
            addr_mode_reg <= 1'b1; // Default to 16-bit address
            use_reg_addr_reg <= 1'b0;
            data_len_reg <= 16'h0;
            upload_ptr_reg <= 16'h0;
            wr_req_pulse <= 1'b0;
            rd_req_pulse <= 1'b0;
            upload_req <= 1'b0;
            upload_valid <= 1'b0;
            upload_data <= 8'h00;
            upload_source <= 8'h00;
            i2c_busy <= 1'b0;
            scl_cnt_max_reg <= SCL_100KHZ_CNT; // <<< NEW: 设置一个安全的默认频率 (100kHz)
        end else begin
            // Default assignments
            wr_req_pulse <= 1'b0;
            rd_req_pulse <= 1'b0;
            upload_valid <= 1'b0;
            cmd_ready <= 1'b0; // Default to busy unless in IDLE

            case (state)
                S_IDLE: begin
                    cmd_ready <= 1'b1;
                    upload_req <= 1'b0;
                    i2c_busy <= 1'b0;
                    upload_ptr_reg <= 0;

                    if (cmd_start) begin
                        case (cmd_type)
                            CMD_I2C_WRITE_NOADDR: state <= S_PARSE_WR_NOADDR;
                            CMD_I2C_READ_NOADDR:  state <= S_PARSE_RD_NOADDR;
                            CMD_I2C_CONFIG:       state <= S_PARSE_CONFIG;
                            CMD_I2C_WRITE_ADDR:   state <= S_PARSE_WR_ADDR;
                            CMD_I2C_READ_ADDR:    state <= S_PARSE_RD_ADDR;
                        endcase
                    end
                end

                S_PARSE_CONFIG: begin
                    cmd_ready <= 1'b1; 
                    if (cmd_data_valid) begin
                        // Payload: [dev_addr, addr_mode, scl_code]
                        case(cmd_data_index)
                            0: device_addr_reg <= cmd_data;
                            1: addr_mode_reg <= (cmd_data == 1); // 1 for 16-bit
                            2: begin // <<< MODIFIED: 处理SCL频率配置
                                case (cmd_data)
                                    8'h01: scl_cnt_max_reg <= SCL_100KHZ_CNT;
                                    8'h02: scl_cnt_max_reg <= SCL_400KHZ_CNT;
                                    default: ; // 对于未知代码，保持当前频率不变
                                endcase
                            end
                        endcase
                    end
                    if (cmd_done) state <= S_IDLE;
                end

                S_PARSE_WR_NOADDR: begin
                    cmd_ready <= 1'b1;
                    if (cmd_data_valid && cmd_data_index < WRITE_BUFFER_SIZE) begin
                        write_buffer[cmd_data_index] <= cmd_data;
                    end
                    if (cmd_done) begin
                        use_reg_addr_reg <= 1'b0; // Set mode to No Address
                        data_len_reg <= cmd_length;
                        state <= S_EXEC_WRITE;
                    end
                end

                S_PARSE_RD_NOADDR: begin
                    cmd_ready <= 1'b1;
                    if (cmd_data_valid) begin
                        // Payload is just 2 bytes of length
                        case(cmd_data_index)
                            0: data_len_reg[15:8] <= cmd_data;
                            1: data_len_reg[7:0]  <= cmd_data;
                        endcase
                    end
                    if (cmd_done) begin
                        upload_source_reg <= CMD_I2C_READ_NOADDR;
                        use_reg_addr_reg <= 1'b0; // Set mode to No Address
                        state <= S_EXEC_READ;
                    end
                end

                S_PARSE_WR_ADDR: begin
                    cmd_ready <= 1'b1;
                    if (cmd_data_valid) begin
                        // Payload: [reg_addr_hi, reg_addr_lo, data0, data1, ...]
                        // Assuming 16-bit address for now, controlled by addr_mode_reg
                        case(cmd_data_index)
                            0: reg_addr_reg[15:8] <= cmd_data;
                            1: reg_addr_reg[7:0]  <= cmd_data;
                            default: if (cmd_data_index - 2 < WRITE_BUFFER_SIZE) begin
                                write_buffer[cmd_data_index - 2] <= cmd_data;
                            end
                        endcase
                    end
                    if (cmd_done) begin
                        use_reg_addr_reg <= 1'b1; // Set mode to Use Address
                        data_len_reg <= cmd_length - 2; // Data length is total length minus address
                        state <= S_EXEC_WRITE;
                    end
                end

                S_PARSE_RD_ADDR: begin
                    cmd_ready <= 1'b1;
                    if (cmd_data_valid) begin
                        // Payload: [reg_addr_hi, reg_addr_lo, len_hi, len_lo]
                        case(cmd_data_index)
                            0: reg_addr_reg[15:8] <= cmd_data;
                            1: reg_addr_reg[7:0]  <= cmd_data;
                            2: data_len_reg[15:8] <= cmd_data;
                            3: data_len_reg[7:0]  <= cmd_data;
                        endcase
                    end
                    if (cmd_done) begin
                        upload_source_reg <= CMD_I2C_READ_ADDR;
                        use_reg_addr_reg <= 1'b1; // Set mode to Use Address
                        state <= S_EXEC_READ;
                    end
                end

                S_EXEC_WRITE: begin
                    if (!i2c_busy) begin
                        wr_req_pulse <= 1'b1;
                        i2c_busy <= 1'b1;
                    end else if (i2c_rw_done) begin
                        state <= S_IDLE;
                    end
                end
                
                S_EXEC_READ: begin
                    if (!i2c_busy) begin
                        rd_req_pulse <= 1'b1;
                        i2c_busy <= 1'b1;
                    end else if (i2c_rw_done) begin
                        upload_ptr_reg <= 0;
                        state <= S_UPLOAD_DATA;
                    end
                end

                S_UPLOAD_DATA: begin
                    if (upload_ptr_reg >= data_len_reg) begin
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
                    if ((state == S_UPLOAD_DATA) && (upload_ptr_reg < data_len_reg) && upload_ready) begin
                        upload_req <= 1'b1;
                        upload_data <= read_buffer[upload_ptr_reg];
                        upload_source <= upload_source_reg; // Use the stored source
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
                        upload_ptr_reg <= upload_ptr_reg + 1;
                        upload_state <= UP_WAIT;
                    end
                end
                UP_WAIT: begin
                    upload_req <= 1'b0;
                    if (state == S_UPLOAD_DATA && upload_ready) begin
                        upload_state <= UP_IDLE;
                    end
                end
                default: upload_state <= UP_IDLE;
            endcase
        end
    end

endmodule