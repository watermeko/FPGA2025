module i2c_bit_shift(
	Clk,
	Rst_n,
	
	Cmd,
	Go,
	Rx_DATA,
	Tx_DATA,
	Trans_Done,
	ack_o,
	// scl_cnt_max, // <<< REMOVED
	i2c_sclk,
	i2c_sdat
);
	input Clk;
	input Rst_n;
	
	input [5:0]Cmd;
	input Go;
	output reg[7:0]Rx_DATA;
	input [7:0]Tx_DATA;
	output reg Trans_Done;
	output reg ack_o;
	output reg i2c_sclk;
	inout i2c_sdat;
	
	reg i2c_sdat_o;
	// input [19:0] scl_cnt_max; // <<< REMOVED: 端口定义已删除

	//系统时钟采用50MHz
	parameter SYS_CLOCK = 50_000_000;
	//SCL总线时钟采用400kHz
	parameter SCL_CLOCK = 100_000; // <<< MODIFIED: 恢复使用固定的400kHz
	//产生时钟SCL计数器最大值
	localparam SCL_CNT_M = SYS_CLOCK/SCL_CLOCK/4 - 1; // <<< MODIFIED: 恢复参数计算

	reg i2c_sdat_oe;
	
	localparam 
		WR   = 6'b000001,   //写请求
		STA  = 6'b000010,   //起始位请求
		RD   = 6'b000100,   //读请求
		STO  = 6'b001000,   //停止位请求
		ACK  = 6'b010000,   //应答位请求
		NACK = 6'b100000;   //无应答请求
		
	reg [19:0]div_cnt;
	reg en_div_cnt;
	always@(posedge Clk or negedge Rst_n)
	if(!Rst_n)
		div_cnt <= 20'd0;
	else if(en_div_cnt)begin
        if(div_cnt < SCL_CNT_M) // <<< MODIFIED: 使用回固定的参数
            div_cnt <= div_cnt + 1'b1;
		else
			div_cnt <= 0;
	end
	else
		div_cnt <= 0;

	wire sclk_plus = div_cnt == SCL_CNT_M; // <<< MODIFIED: 使用回固定的参数
	
	wire drive_sda_low;
	assign drive_sda_low = i2c_sdat_oe && (i2c_sdat_o == 1'b0);
	assign i2c_sdat = drive_sda_low ? 1'b0 : 1'bz;
		
	reg [7:0]state;
	
	localparam
		IDLE      = 8'b00000001,   //空闲状态
		GEN_STA   = 8'b00000010,   //产生起始信号
		WR_DATA   = 8'b00000100,   //写数据状态
		RD_DATA   = 8'b00001000,   //读数据状态
		CHECK_ACK = 8'b00010000,   //检测应答状态
		GEN_ACK   = 8'b00100000,   //产生应答状态
		GEN_STO   = 8'b01000000;   //产生停止信号
		
	reg [4:0]cnt;
		
	always@(posedge Clk or negedge Rst_n)
	if(!Rst_n)begin
		Rx_DATA <= 0;
		i2c_sdat_oe <= 1'd0;
		en_div_cnt <= 1'b0;
		i2c_sdat_o <= 1'd1;
		Trans_Done <= 1'b0;
		ack_o <= 0;
		state <= IDLE;
		cnt <= 0;
	end
	else begin
		case(state)
			IDLE:
				begin
					Trans_Done <= 1'b0;
					i2c_sdat_oe <= 1'd1;
					if(Go)begin
						en_div_cnt <= 1'b1;
						if(Cmd & STA)
							state <= GEN_STA;
						else if(Cmd & WR)
							state <= WR_DATA;
						else if(Cmd & RD)
							state <= RD_DATA;
						else
							state <= IDLE;
					end
					else begin
						en_div_cnt <= 1'b0;
						state <= IDLE;
					end
				end
				
			GEN_STA: begin
				if(sclk_plus) begin
					if(cnt == 3) cnt <= 0;
					else cnt <= cnt + 1'b1;
					
					case(cnt)
						0: begin i2c_sdat_o <= 1; i2c_sclk <= 1; i2c_sdat_oe <= 1'd1; end // 确保总线空闲 (SDA=1, SCL=1)
						1: begin i2c_sdat_o <= 0; i2c_sclk <= 1; end                     // SCL保持高, SDA拉低 -> START
						2: begin i2c_sdat_o <= 0; i2c_sclk <= 0; end                     // SCL拉低, 准备发送数据
						3: begin i2c_sclk <= 0; end                                      // 保持SCL低, 等待数据设置
						default: ;
					endcase

					if(cnt == 3) begin
						if(Cmd & WR) state <= WR_DATA;
						else if(Cmd & RD) state <= RD_DATA;
					end
				end
			end
				
			WR_DATA:
				begin
					if(sclk_plus)begin
						if(cnt == 31)
							cnt <= 0;
						else
							cnt <= cnt + 1'b1;
						case(cnt)
							0,4,8,12,16,20,24,28:begin i2c_sdat_o <= Tx_DATA[7-cnt[4:2]]; i2c_sdat_oe <= 1'd1;end	//set data;
							1,5,9,13,17,21,25,29:begin i2c_sclk <= 1;end	//sclk posedge
							2,6,10,14,18,22,26,30:begin i2c_sclk <= 1;end	//sclk keep high
							3,7,11,15,19,23,27,31:begin i2c_sclk <= 0;end	//sclk negedge
							default:begin i2c_sdat_o <= 1; i2c_sclk <= 1;end
						endcase
						if(cnt == 31)begin
							state <= CHECK_ACK;
						end
					end
				end
				
			RD_DATA: begin
			if (cnt == 0) begin
				i2c_sdat_oe <= 1'b0; // 主机不驱动 SDA
				i2c_sdat_o  <= 1'b1; // 输出高阻
			end

			if (sclk_plus) begin
				if (cnt == 31)
				cnt <= 0;
				else
				cnt <= cnt + 1'b1;

				case(cnt)
				0,4,8,12,16,20,24,28: begin 
					i2c_sdat_oe <= 1'd0; 
					i2c_sclk <= 0;
				end
				1,5,9,13,17,21,25,29: begin 
					i2c_sclk <= 1; 
				end
				2,6,10,14,18,22,26,30: begin 
					i2c_sclk <= 1; 
					Rx_DATA <= {Rx_DATA[6:0], i2c_sdat}; 
				end
				3,7,11,15,19,23,27,31: begin 
					i2c_sclk <= 0; 
				end
				default: begin 
					i2c_sdat_o <= 1; 
					i2c_sclk <= 1; 
				end
				endcase

				if (cnt == 31) begin
				state <= GEN_ACK;
				end
			end
			end
			
			CHECK_ACK:
				begin
					if(sclk_plus)begin
						if(cnt == 3)
							cnt <= 0;
						else
							cnt <= cnt + 1'b1;
						case(cnt)
							0:begin i2c_sdat_oe <= 1'd0; i2c_sclk <= 0;end
							1:begin i2c_sclk <= 1;end
							2:begin ack_o <= i2c_sdat; i2c_sclk <= 1;end
							3:begin i2c_sclk <= 0;end
							default:begin i2c_sdat_o <= 1; i2c_sclk <= 1;end
						endcase
						if(cnt == 3)begin
							if(Cmd & STO)
								state <= GEN_STO;
							else begin
								state <= IDLE;
								Trans_Done <= 1'b1;
							end								
						end
					end
				end
			
			GEN_ACK:
				begin
					if(sclk_plus)begin
						if(cnt == 3)
							cnt <= 0;
						else
							cnt <= cnt + 1'b1;
						case(cnt)
							0:begin 
									i2c_sdat_oe <= 1'd1;
									i2c_sclk <= 0;
									if(Cmd & ACK)
										i2c_sdat_o <= 1'b0;
									else if(Cmd & NACK)
										i2c_sdat_o <= 1'b1;
								end
							1:begin i2c_sclk <= 1;end
							2:begin i2c_sclk <= 1;end
							3:begin i2c_sclk <= 0;end
							default:begin i2c_sdat_o <= 1; i2c_sclk <= 1;end
						endcase
						if(cnt == 3)begin
							if(Cmd & STO)
								state <= GEN_STO;
							else begin
								state <= IDLE;
								Trans_Done <= 1'b1;
							end
						end
					end
				end
			
			GEN_STO: begin
				if(sclk_plus) begin
					if(cnt == 3) cnt <= 0;
					else cnt <= cnt + 1'b1;

					case(cnt)
						0: begin i2c_sdat_o <= 0; i2c_sclk <= 0; i2c_sdat_oe <= 1'd1; end // 准备Stop (SDA=0, SCL=0)
						1: begin i2c_sdat_o <= 0; i2c_sclk <= 1; end                     // SCL拉高
						2: begin i2c_sdat_o <= 1; i2c_sclk <= 1; end                     // SCL保持高, SDA拉高 -> STOP
						3: begin i2c_sdat_o <= 1; i2c_sclk <= 1; end                     // 保持总线空闲
						default: ;
					endcase

					if(cnt == 3) begin
						Trans_Done <= 1'b1;
						state <= IDLE;
					end
				end
			end
			default:state <= IDLE;
		endcase
	end
endmodule