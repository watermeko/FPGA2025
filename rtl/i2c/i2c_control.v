module i2c_control(
	Clk, Rst_n,
	
	wrreg_req,
	rd_start_req,       // <--- 修改: 替换 rdreg_req
	rd_continue_req,    // <--- 新增: 继续读请求

	addr, addr_mode, wrdata, rddata, device_id, RW_Done, ack,
    is_last_byte,       // <--- 保留: 仍然需要它来决定发ACK还是NACK
	
	dly_cnt_max, i2c_sclk, i2c_sdat
);

	input Clk;
	input Rst_n;
	
	input wrreg_req;
    input rd_start_req;
    input rd_continue_req;
	input [15:0]addr;
	input addr_mode;
	input [7:0]wrdata;
	output reg[7:0]rddata;
	input [7:0]device_id;
	output reg RW_Done;
	
	output reg ack;
    input is_last_byte;

    input [31:0]dly_cnt_max;
    
	output i2c_sclk;
	inout i2c_sdat;
	reg [5:0]Cmd;
	reg [7:0]Tx_DATA;
	wire Trans_Done;
	wire ack_o;
	reg Go;
	wire [15:0] reg_addr;
	
	assign reg_addr = addr_mode?addr:{addr[7:0],addr[15:8]};
	
	wire [7:0]Rx_DATA;
	
	localparam 
		WR   = 6'b000001,   //写请求
		STA  = 6'b000010,   //起始位请求
		RD   = 6'b000100,   //读请求
		STO  = 6'b001000,   //停止位请求
		ACK  = 6'b010000,   //应答位请求
		NACK = 6'b100000;   //无应答请求
	
	i2c_bit_shift i2c_bit_shift(
		.Clk(Clk),
		.Rst_n(Rst_n),
		.Cmd(Cmd),
		.Go(Go),
		.Rx_DATA(Rx_DATA),
		.Tx_DATA(Tx_DATA),
		.Trans_Done(Trans_Done),
		.ack_o(ack_o),
		.i2c_sclk(i2c_sclk),
		.i2c_sdat(i2c_sdat)
	);
	
	reg [7:0]state;
	reg [7:0]cnt;
	reg [31:0]dly_cnt;
	
	localparam
		IDLE         = 8'h01,   //空闲状态
		WR_REG       = 8'h02,   //写寄存器状态
		WAIT_WR_DONE = 8'h04,   //等待写寄存器完成状态
		WR_REG_DONE  = 8'h08,   //写寄存器完成状态
		RD_REG       = 8'h10,   //读寄存器状态
		WAIT_RD_DONE = 8'h20,   //等待读寄存器完成状态
		RD_REG_DONE  = 8'h40,   //读寄存器完成状态
		WAIT_DLY     = 8'h80;   //等待延迟完成
	
	always@(posedge Clk or negedge Rst_n)
	if(!Rst_n)begin
		Cmd <= 6'd0;
		Tx_DATA <= 8'd0;
		Go <= 1'b0;
		rddata <= 0;
		state <= IDLE;
		ack <= 0;
		dly_cnt <= 0;
		cnt <= 0;
	end
	else begin
		case(state)
			IDLE:
				begin
					cnt <= 0;
					dly_cnt <= 0;
					ack <= 0;
					RW_Done <= 1'b0;					
					if(wrreg_req)
						state <= WR_REG;
                    else if (rd_start_req) begin // <--- 响应新的开始读请求
                        cnt <= 0; // 从地址设置开始
                        state <= RD_REG;
                    end
                    else if (rd_continue_req) begin // <--- 响应继续读请求
                        cnt <= 4; // 直接跳到读数据步骤
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
						3:write_byte(WR | STO, wrdata);
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
				
			RD_REG:
				begin
					state <= WAIT_RD_DONE;
					case(cnt)
						// 阶段1 & 2: 地址设置和模式切换 (仅在 rd_start_req 时执行)
						0: write_byte(WR | STA, device_id);
						1: write_byte(WR, reg_addr[15:8]);
						2: write_byte(WR, reg_addr[7:0]);
						3: write_byte(WR | STA, device_id | 8'h01);
						// 阶段3: 读取数据 (rd_start_req 和 rd_continue_req 都会执行)
						4: begin
                            if (is_last_byte)
                                read_byte(RD | NACK | STO); // 最后字节: 读+NACK+STOP
                            else
                                read_byte(RD | ACK);        // 非最后字节: 读+ACK
                        end
						default:;
					endcase
				end
				
			WAIT_RD_DONE:
				begin
					Go <= 1'b0; 
					if(Trans_Done)begin
						if(cnt <= 3)
							ack <= ack | ack_o;
						case(cnt)
							0: begin cnt <= 1; state <= RD_REG; end
							1: begin 
                                state <= RD_REG;
                                if(addr_mode) cnt <= 2; 
                                else cnt <= 3;
							   end
							2: begin cnt <= 3; state <= RD_REG; end
							3: begin cnt <= 4; state <= RD_REG; end
							4: state <= RD_REG_DONE; // 读完一个字节就进入DONE
							default: state <= IDLE;
						endcase
					end
				end
				
			RD_REG_DONE:
				begin
					rddata <= Rx_DATA;
					state <= WAIT_DLY; // 进入延迟并置位 RW_Done
				end

			WAIT_DLY:
			     begin
			         if(dly_cnt < dly_cnt_max)begin
			             dly_cnt <= dly_cnt + 1'b1;
			             state <= WAIT_DLY;
			         end
			         else begin
			             dly_cnt <= 0;
			             RW_Done <= 1'b1;
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