module i2c_control(
	Clk, Rst_n,
	
	wrreg_req,
	rdreg_req,
	
	addr, addr_mode, wrdata, rddata, device_id, RW_Done, ack,
	dly_cnt_max, i2c_sclk, i2c_sdat,
	scl_cnt_max // <<< NEW: 新增输入端口

);
	input Clk;
	input Rst_n;
	
	input wrreg_req;
    input rdreg_req;
	input [15:0]addr;
	input addr_mode;
	input [7:0]wrdata;
	output reg[7:0]rddata;
	input [7:0]device_id;
	output reg RW_Done;
	output reg ack;
    input [31:0]dly_cnt_max;

	input [19:0] scl_cnt_max; // 25.10.19
    
	output i2c_sclk;
	inout i2c_sdat;
	reg [5:0]Cmd;
	reg [7:0]Tx_DATA;
	wire Trans_Done;

	wire ack_o;
	reg Go;
	
    // --- 新增：内部锁存寄存器 ---
    reg [15:0] addr_reg;
    reg [7:0]  wrdata_reg;
    // --- 修改结束 ---

	// --- 修改：使用锁存后的地址 ---
	wire [15:0] reg_addr;
	assign reg_addr = addr_mode ? addr_reg : {addr_reg[7:0], addr_reg[15:8]};
    // --- 修改结束 ---
	
	wire [7:0]Rx_DATA;
	
	localparam 
		WR   = 6'b000001, STA  = 6'b000010, RD   = 6'b000100,
		STO  = 6'b001000, ACK  = 6'b010000, NACK = 6'b100000;
	
	i2c_bit_shift i2c_bit_shift(
		.Clk(Clk),
		.Rst_n(Rst_n),
		.Cmd(Cmd),
		.Go(Go),
		.Rx_DATA(Rx_DATA),
		.Tx_DATA(Tx_DATA),
		.Trans_Done(Trans_Done),
		.ack_o(ack_o),
		.scl_cnt_max(scl_cnt_max), // <<< NEW: 连接到 i2c_bit_shift
		.i2c_sclk(i2c_sclk),
		.i2c_sdat(i2c_sdat)
	);
	
	reg [7:0]state;
	reg [7:0]cnt;
	reg [31:0]dly_cnt;
	
	localparam
		IDLE              = 8'h01,
		WR_REG            = 8'h02,
		WAIT_WR_DONE      = 8'h04,
		WR_REG_DONE       = 8'h08,
		RD_REG            = 8'h10,
		WAIT_RD_DONE      = 8'h20,
		RD_REG_DONE       = 8'h40,
		WAIT_DLY          = 8'h80;

	always@(posedge Clk or negedge Rst_n)
	if(!Rst_n)begin
		Cmd <= 6'd0; Tx_DATA <= 8'd0; Go <= 1'b0; rddata <= 0;
		state <= IDLE; ack <= 0; dly_cnt <= 0; cnt <= 0;
        // --- 新增：初始化锁存寄存器 ---
        addr_reg <= 16'd0;
        wrdata_reg <= 8'd0;
        // --- 修改结束 ---
	end
	else begin
		case(state)
			IDLE:
				begin
					cnt <= 0; dly_cnt <= 0; ack <= 0; RW_Done <= 1'b0;					
					if(wrreg_req) begin
                        // --- 新增：在任务开始时锁存地址和数据 ---
                        addr_reg <= addr;
                        wrdata_reg <= wrdata;
                        // --- 修改结束 ---
						state <= WR_REG;
                    end
                    else if (rdreg_req) begin
                        // --- 新增：在任务开始时锁存地址 ---
                        addr_reg <= addr;
                        // --- 修改结束 ---
                        cnt <= 0;
                        state <= RD_REG;
                    end
					else
						state <= IDLE;
				end
			
			WR_REG:
				begin
					state <= WAIT_WR_DONE;
					case(cnt)
						0:write_byte(WR | STA, device_id);
						1:write_byte(WR, reg_addr[15:8]);
						2:write_byte(WR, reg_addr[7:0]);
						// --- 修改：使用内部锁存的数据 ---
						3:write_byte(WR | STO, wrdata_reg);
						// --- 修改结束 ---
						default:;
					endcase
				end
			
			WAIT_WR_DONE:
				begin
					Go <= 1'b0; 
					if(Trans_Done)begin
						ack <= ack | ack_o;
						case(cnt)
							0: begin cnt <= 1; state <= WR_REG;end
							1: 
								begin 
									state <= WR_REG;
									if(addr_mode)
										cnt <= 2; 
									else
										cnt <= 3;
								end
									
							2: begin
									cnt <= 3;
									state <= WR_REG;
								end
							3:state <= WR_REG_DONE;
							default:state <= IDLE;
						endcase
					end
				end
			
			WR_REG_DONE:
				begin
					state <= WAIT_DLY;
				end
				
			RD_REG: begin
				state <= WAIT_RD_DONE;
				case(cnt)
                    // --- 此处使用的 reg_addr 已经是指向内部锁存的 addr_reg，所以逻辑不用改 ---
					0: write_byte(WR | STA, device_id);
					1: write_byte(WR, reg_addr[15:8]);
					2: write_byte(WR, reg_addr[7:0]);
					3: write_byte(WR | STA, device_id | 8'h01);
					4: read_byte(RD | NACK | STO);
					default:;
				endcase
			end
				
			WAIT_RD_DONE: begin
				Go <= 1'b0;
				if (Trans_Done) begin
					if (cnt <= 3) ack <= ack | ack_o;
					case (cnt)
						0: begin cnt <= 1; state <= RD_REG; end
						1: begin 
								state <= RD_REG;
								if (addr_mode) cnt <= 2; 
								else cnt <= 3;
						end
						2: begin cnt <= 3; state <= RD_REG; end
						3: begin cnt <= 4; state <= RD_REG; end
						4: begin
							rddata <= Rx_DATA;
							state <= RD_REG_DONE;
						end
						default:state <= IDLE;
					endcase
				end
			end
							
			RD_REG_DONE: begin
				state <= WAIT_DLY;
			end

			WAIT_DLY:
			     begin
			         if(dly_cnt < dly_cnt_max)begin
			             dly_cnt <= dly_cnt + 1'b1;
			             state <= WAIT_DLY;
			         end
			         else begin
			             dly_cnt <= 0;
			             RW_Done <= 1'b1; // <--- 注意: RW_Done现在在延时后拉高
			             state <= IDLE;
			         end
			     end
            default: state <= IDLE;
		endcase
	end
	
	task read_byte;
		input [5:0]Ctrl_Cmd;
		begin
			Cmd <= Ctrl_Cmd;
			Go <= 1'b1; 
		end
	endtask
	
	task write_byte;
		input [5:0]Ctrl_Cmd;
		input [7:0]Wr_Byte_Data;
		begin
			Cmd <= Ctrl_Cmd;
			Tx_DATA <= Wr_Byte_Data;
			Go <= 1'b1; 
		end
	endtask

endmodule