// =======================================================================================
// i2c_control: 最终整合版 - 通用多字节引擎
// - 通过 wr_req/rd_req 触发
// - 通过 use_reg_addr 信号选择是否带寄存器地址
// =======================================================================================
module i2c_control #(
    parameter WRITE_BUFFER_SIZE = 32,
    parameter READ_BUFFER_SIZE  = 32
)(
	Clk, Rst_n,
	
    // --- 统一的触发和模式选择 ---
	wr_req,
	rd_req,
    use_reg_addr, // <<< NEW: 1'b1 = 带地址模式, 1'b0 = 无地址模式

    // --- 统一的数据和地址接口 ---
    addr,
    addr_mode,
    data_len,
    write_buffer,
    read_buffer,
	i2c_sdat,
	i2c_sclk,
    // --- 公共接口 ---
    device_id, RW_Done, ack,
	scl_cnt_max  // <<< NEW: 新增端口
);
	input                           Clk;
	input                           Rst_n;
	
    // Control Signals
	input                           wr_req;
    input                           rd_req;
    input                           use_reg_addr;

    // Data and Address
	input      [15:0]               addr;
	input                           addr_mode;
	input      [15:0]               data_len;
	input      [7:0]                write_buffer [0:WRITE_BUFFER_SIZE-1];
	output reg [7:0]                read_buffer  [0:READ_BUFFER_SIZE-1];
    input      [19:0]               scl_cnt_max; // <<< NEW: 端口定义
    // Common I/O
	input      [7:0]                device_id;
	output reg                      RW_Done;
	output reg                      ack;
    
    // Internal timing - assuming i2c_bit_shift handles this
	inout                           i2c_sdat;
    output                          i2c_sclk;


	// --- 内部信号 ---
	reg        [5:0]                Cmd;
	reg        [7:0]                Tx_DATA;
	wire                            Trans_Done;
	wire                            ack_o;
	reg                             Go;
	wire       [7:0]                Rx_DATA;
	
	localparam 
		WR   = 6'b000001, STA  = 6'b000010, RD   = 6'b000100,
		STO  = 6'b001000, ACK  = 6'b010000, NACK = 6'b100000;
	
	i2c_bit_shift i2c_bit_shift(
		.Clk(Clk), .Rst_n(Rst_n), .Cmd(Cmd), .Go(Go), .Rx_DATA(Rx_DATA),
		.Tx_DATA(Tx_DATA), .Trans_Done(Trans_Done), .ack_o(ack_o),
		.i2c_sclk(i2c_sclk), .i2c_sdat(i2c_sdat),
		.scl_cnt_max(scl_cnt_max)
	);
	
	reg [7:0]  state;
    // Internal latched registers to hold transaction parameters
    reg        use_reg_addr_reg;
    reg [15:0] addr_reg;
    reg        addr_mode_reg;
    wire [15:0] reg_addr;
	assign reg_addr = addr_mode_reg ? addr_reg : {addr_reg[7:0], addr_reg[15:8]};

    // Universal counters
    reg [15:0] byte_ptr; // For data buffer
    reg [1:0]  addr_ptr; // For register address bytes (max 2 bytes)
	
	// --- 统一的状态机状态定义 ---
	localparam
		IDLE                  = 8'h01,
		// Write Flow
		WR_START_DEV_ADDR     = 8'h02,
        WR_WAIT_DEV_ADDR_ACK  = 8'h03,
        WR_SEND_REG_ADDR      = 8'h04,
        WR_WAIT_REG_ADDR_ACK  = 8'h05,
        WR_SEND_DATA_BYTE     = 8'h06,
        WR_WAIT_DATA_ACK      = 8'h07,
        WR_STOP               = 8'h08,
		// Read Flow
		RD_START_DEV_ADDR_W   = 8'h10, // For address setup
        RD_WAIT_DEV_ADDR_W_ACK= 8'h11,
        RD_SEND_REG_ADDR      = 8'h12,
        RD_WAIT_REG_ADDR_ACK  = 8'h13,
        RD_REPEATED_START     = 8'h14, // The crucial repeated start
        RD_WAIT_RESTART_ACK   = 8'h15,
        RD_READ_DATA_BYTE     = 8'h16,
        RD_WAIT_DATA          = 8'h17,
		// Common State
		WAIT_DLY              = 8'h80;

	always@(posedge Clk or negedge Rst_n)
	if(!Rst_n)begin
		Cmd <= 6'd0; Tx_DATA <= 8'd0; Go <= 1'b0; 
		state <= IDLE; ack <= 0; byte_ptr <= 0; addr_ptr <= 0;
        use_reg_addr_reg <= 1'b0; addr_reg <= 16'd0; addr_mode_reg <= 1'b0;
	end
	else begin
		case(state)
			IDLE: begin
				ack <= 0; RW_Done <= 1'b0; byte_ptr <= 0; addr_ptr <= 0;
				if(wr_req) begin
                    // Latch all parameters for this transaction
                    use_reg_addr_reg <= use_reg_addr;
                    addr_reg <= addr;
                    addr_mode_reg <= addr_mode;
                    state <= WR_START_DEV_ADDR;
                end
                else if (rd_req) begin
                    use_reg_addr_reg <= use_reg_addr;
                    addr_reg <= addr;
                    addr_mode_reg <= addr_mode;
                    // If we need to send reg addr first, we must start with a WRITE command
                    if (use_reg_addr) state <= RD_START_DEV_ADDR_W;
                    // Otherwise, we can start directly with a READ command
                    else state <= RD_REPEATED_START; 
                end
			end
			
			// =========================================================
			// --- 统一写操作流程 ---
			// =========================================================
			WR_START_DEV_ADDR: begin
                write_byte(WR | STA, device_id);
                state <= WR_WAIT_DEV_ADDR_ACK;
            end
            WR_WAIT_DEV_ADDR_ACK: begin
                Go <= 1'b0;
                if(Trans_Done) begin
                    ack <= ack | ack_o;
                    // Decision point: send reg address or go directly to data?
                    if (use_reg_addr_reg) state <= WR_SEND_REG_ADDR;
                    else state <= WR_SEND_DATA_BYTE;
                end
            end
            WR_SEND_REG_ADDR: begin
                // Handle 8-bit or 16-bit register address
                case(addr_ptr)
                    0: write_byte(WR, reg_addr[15:8]);
                    1: write_byte(WR, reg_addr[7:0]);
                endcase
                state <= WR_WAIT_REG_ADDR_ACK;
            end
            WR_WAIT_REG_ADDR_ACK: begin
                Go <= 1'b0;
                if(Trans_Done) begin
                    ack <= ack | ack_o;
                    addr_ptr <= addr_ptr + 1;
                    // If addr is 16-bit (addr_mode=1) and we've only sent 1 byte, send the second
                    if (addr_mode_reg && addr_ptr < 1) state <= WR_SEND_REG_ADDR;
                    // Otherwise, address phase is done, move to data phase
                    else state <= WR_SEND_DATA_BYTE;
                end
            end
            WR_SEND_DATA_BYTE: begin
                write_byte(WR, write_buffer[byte_ptr]);
                state <= WR_WAIT_DATA_ACK;
            end
            WR_WAIT_DATA_ACK: begin
                Go <= 1'b0;
                if(Trans_Done) begin
                    ack <= ack | ack_o;
                    byte_ptr <= byte_ptr + 1;
                    if (byte_ptr + 1 < data_len) state <= WR_SEND_DATA_BYTE;
                    else state <= WR_STOP;
                end
            end
            WR_STOP: begin
                write_byte(STO, 8'h00); 
                state <= WAIT_DLY;
            end

			// =========================================================
			// --- 统一读操作流程 ---
			// =========================================================
            RD_START_DEV_ADDR_W: begin // Step 1: Send Dev Addr + W for setting the reg addr
                write_byte(WR | STA, device_id);
                state <= RD_WAIT_DEV_ADDR_W_ACK;
            end
            RD_WAIT_DEV_ADDR_W_ACK: begin
                Go <= 1'b0;
                if(Trans_Done) begin
                    ack <= ack | ack_o;
                    state <= RD_SEND_REG_ADDR;
                end
            end
            RD_SEND_REG_ADDR: begin // Step 2: Send the register address
                case(addr_ptr)
                    0: write_byte(WR, reg_addr[15:8]);
                    1: write_byte(WR, reg_addr[7:0]);
                endcase
                state <= RD_WAIT_REG_ADDR_ACK;
            end
            RD_WAIT_REG_ADDR_ACK: begin
                Go <= 1'b0;
                if(Trans_Done) begin
                    ack <= ack | ack_o;
                    addr_ptr <= addr_ptr + 1;
                    if (addr_mode_reg && addr_ptr < 1) state <= RD_SEND_REG_ADDR;
                    else state <= RD_REPEATED_START; // Address sent, now do repeated start
                end
            end
            RD_REPEATED_START: begin // Step 3: Send Repeated Start + Dev Addr + R
                write_byte(WR | STA, device_id | 8'h01); // Note: STA flag for Repeated Start
                state <= RD_WAIT_RESTART_ACK;
            end
            RD_WAIT_RESTART_ACK: begin
                Go <= 1'b0;
                if (Trans_Done) begin
                    ack <= ack | ack_o;
                    state <= RD_READ_DATA_BYTE; // Now we are ready to read data
                end
            end
            RD_READ_DATA_BYTE: begin // Step 4: The actual data reading loop
                if (byte_ptr == data_len - 1) read_byte(RD | NACK | STO);
                else read_byte(RD | ACK);
                state <= RD_WAIT_DATA;
            end
			RD_WAIT_DATA: begin
				Go <= 1'b0;
				if (Trans_Done) begin
                    read_buffer[byte_ptr] <= Rx_DATA;
                    if (byte_ptr == data_len - 1) state <= WAIT_DLY;
                    else begin
                        byte_ptr <= byte_ptr + 1;
                        state <= RD_READ_DATA_BYTE;
                    end
				end
			end
			
			// =========================================================
			// --- 公共结束状态 ---
			// =========================================================
			WAIT_DLY: begin
                RW_Done <= 1'b1;
                state <= IDLE;
            end
            default: state <= IDLE;
		endcase
	end
	
	task read_byte;
		input [5:0]Ctrl_Cmd;
		begin Cmd <= Ctrl_Cmd; Go <= 1'b1; end
	endtask
	
	task write_byte;
		input [5:0]Ctrl_Cmd;
		input [7:0]Wr_Byte_Data;
		begin Cmd <= Ctrl_Cmd; Tx_DATA <= Wr_Byte_Data; Go <= 1'b1; end
	endtask

endmodule