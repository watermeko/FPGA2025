module i2c_control(
	Clk, Rst_n,
	
	wr_req, // <<< MODIFIED: Renamed
	rd_req, // <<< MODIFIED: Renamed
	
	// addr, addr_mode, // <<< MODIFIED: Removed
    wrdata, rddata, device_id, RW_Done, ack,
	dly_cnt_max, i2c_sclk, i2c_sdat
);
	input Clk;
	input Rst_n;
	
	input wr_req;
    input rd_req;
	// input [15:0]addr; // <<< MODIFIED: Removed
	// input addr_mode; // <<< MODIFIED: Removed
	input [7:0]wrdata;
	output reg[7:0]rddata;
	input [7:0]device_id; // Note: This should contain the 7-bit address shifted left by 1
	output reg RW_Done;
	output reg ack;
    input [31:0]dly_cnt_max;
    
	output i2c_sclk;
	inout i2c_sdat;
	reg [5:0]Cmd;
	reg [7:0]Tx_DATA;
	wire Trans_Done;

	wire ack_o;
	reg Go;
	
    // --- MODIFIED: Removed address latching registers ---
    reg [7:0] wrdata_reg;

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
		.i2c_sclk(i2c_sclk),
		.i2c_sdat(i2c_sdat)
	);
	
	reg [7:0]state;
	reg [7:0]cnt;
	reg [31:0]dly_cnt;
	
	localparam
		IDLE              = 8'h01,
		WR_OP             = 8'h02, // <<< MODIFIED: Renamed state
		WAIT_WR_DONE      = 8'h04,
		WR_OP_DONE        = 8'h08, // <<< MODIFIED: Renamed state
		RD_OP             = 8'h10, // <<< MODIFIED: Renamed state
		WAIT_RD_DONE      = 8'h20,
		RD_OP_DONE        = 8'h40, // <<< MODIFIED: Renamed state
		WAIT_DLY          = 8'h80;

	always@(posedge Clk or negedge Rst_n)
	if(!Rst_n)begin
		Cmd <= 6'd0; Tx_DATA <= 8'd0; Go <= 1'b0; rddata <= 0;
		state <= IDLE; ack <= 0; dly_cnt <= 0; cnt <= 0;
        wrdata_reg <= 8'd0;
	end
	else begin
		case(state)
			IDLE:
				begin
					cnt <= 0; dly_cnt <= 0; ack <= 0; RW_Done <= 1'b0;					
					if(wr_req) begin
                        wrdata_reg <= wrdata; // Latch data at the beginning
						state <= WR_OP;
                    end
                    else if (rd_req) begin
                        cnt <= 0;
                        state <= RD_OP;
                    end
					else
						state <= IDLE;
				end
			
			// <<< MODIFIED: Simplified Write Operation State Machine
			WR_OP:
				begin
					state <= WAIT_WR_DONE;
					case(cnt)
						0: write_byte(WR | STA, device_id);      // Start + Device Address + Write Bit
						1: write_byte(WR | STO, wrdata_reg);     // Data + Stop
						default:;
					endcase
				end
			
			WAIT_WR_DONE:
				begin
					Go <= 1'b0; 
					if(Trans_Done)begin
						ack <= ack | ack_o;
						case(cnt)
							0: begin cnt <= 1; state <= WR_OP; end
							1: state <= WR_OP_DONE;
							default: state <= IDLE;
						endcase
					end
				end
			
			WR_OP_DONE:
				begin
					state <= WAIT_DLY;
				end
				
			// <<< MODIFIED: Simplified Read Operation State Machine
			RD_OP: begin
				state <= WAIT_RD_DONE;
				case(cnt)
					0: write_byte(WR | STA, device_id | 8'h01); // Start + Device Address + Read Bit
					1: read_byte(RD | NACK | STO);              // Read Data + NACK + Stop
					default:;
				endcase
			end
				
			WAIT_RD_DONE: begin
				Go <= 1'b0;
				if (Trans_Done) begin
					if (cnt == 0) ack <= ack | ack_o; // Only check ACK for address phase
					case (cnt)
						0: begin cnt <= 1; state <= RD_OP; end
						1: begin
							rddata <= Rx_DATA;
							state <= RD_OP_DONE;
						end
						default: state <= IDLE;
					endcase
				end
			end
							
			RD_OP_DONE: begin
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