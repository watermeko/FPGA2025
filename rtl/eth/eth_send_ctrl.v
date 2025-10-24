
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
module eth_send_ctrl(
  input clk125M,
  input reset_n,  //模块的复位信号
  input eth_tx_done,    //以太网一个包发送完毕信号
  input restart_req,
  input stream_mode,
  input [11:0]fifo_rd_cnt, //从FIFO中读取的数据个数(字节数)
  input [31:0]total_data_num,  //需要发送的数据总数

  output reg pkt_tx_en ,   //以太网发送使能信号
  output reg [15:0]pkt_length  //以太网需要发送的数据的长度
); 
  
  //采集数据最大字节数：1500-IP报文头部（20字节）-UDP报文头部（8字节）= 1472字节

  localparam ST_IDLE          = 4'd0;
  localparam ST_BURST_WAIT    = 4'd1;
  localparam ST_BURST_SEND    = 4'd2;
  localparam ST_BURST_GAP     = 4'd3;
  localparam ST_BURST_LENGTH  = 4'd4;
  localparam ST_STREAM_WAIT   = 4'd5;
  localparam ST_STREAM_SEND   = 4'd6;
  localparam ST_STREAM_DONE   = 4'd7;
  localparam ST_STREAM_GAP    = 4'd8;

  localparam [15:0] STREAM_PKT_BYTES = 16'd1472;

  reg[3:0]state;
  reg [31:0]data_num;
  
  reg [28:0]cnt_dly_time;

  parameter cnt_dly_min = 16'd128;

  wire [15:0]fifo_even_length = {4'd0, fifo_rd_cnt[11:1], 1'b0};
    
  always@(posedge clk125M or negedge reset_n)
  if(!reset_n) begin
    pkt_tx_en <= 1'd0;
    pkt_length <= 16'd0;
    data_num <= 32'd0;
    state <= ST_IDLE;
    cnt_dly_time <= 28'd0;
  end
  else begin
    case(state)
        ST_IDLE:
            begin
                pkt_tx_en <= 1'd0;
                cnt_dly_time <= 28'd0;
                if(stream_mode)begin
                    pkt_length <= STREAM_PKT_BYTES;
                    state <= ST_STREAM_WAIT;
                end
                else if(restart_req)begin
                    data_num <= total_data_num;
                    if((total_data_num << 1) >= 32'd1472)begin
                        pkt_length <= 16'd1472;	//一个数据2个字节
                        state <= ST_BURST_WAIT;
                    end
                    else if((total_data_num << 1) > 32'd0)begin
                        pkt_length <= total_data_num << 1; //一个数据2个字节
                        state <= ST_BURST_WAIT;
                    end
                    else begin
                        state <= ST_IDLE;
                    end
				end
            end
         ST_BURST_WAIT:
            begin
                pkt_tx_en <= 1'd0;
                if(fifo_rd_cnt >= (pkt_length - 2)) begin
                    pkt_tx_en <= 1'd1;
                    state <= ST_BURST_SEND;
                end
                else begin
                    state <= ST_BURST_WAIT;
                    pkt_tx_en <= 1'd0;
                end
            end
         ST_BURST_SEND:
            begin
                pkt_tx_en <= 1'd0;
                if(eth_tx_done)begin
					data_num <= data_num - pkt_length/2;
					state <= ST_BURST_GAP;
				end
            end

        ST_BURST_GAP:
			if(cnt_dly_time >= cnt_dly_min)begin
               state <= ST_BURST_LENGTH;
               cnt_dly_time <= 28'd0;
            end
            else begin
               cnt_dly_time <= cnt_dly_time + 1'b1;
			   state <= ST_BURST_GAP;
            end
         ST_BURST_LENGTH:
            begin
                if((data_num << 1) >= 32'd1472)begin
					pkt_length <= 16'd1472;
					state <= ST_BURST_WAIT;
				end
				else if((data_num << 1) > 32'd0)begin
					pkt_length <= data_num << 1;
					state <= ST_BURST_WAIT;
				end
				else if(stream_mode)begin
                    pkt_length <= STREAM_PKT_BYTES;
                    state <= ST_STREAM_WAIT;
                end
                else begin
					state <= ST_IDLE;
				end
            end

        ST_STREAM_WAIT:
            begin
                pkt_tx_en <= 1'd0;
                if(stream_mode)begin
                    if(fifo_rd_cnt >= STREAM_PKT_BYTES)begin
                        pkt_length <= STREAM_PKT_BYTES;
                        state <= ST_STREAM_SEND;
                    end
                    else
                        state <= ST_STREAM_WAIT;
                end
                else if(fifo_rd_cnt >= 12'd2)begin
                    if(fifo_even_length != 16'd0)begin
                        if(fifo_even_length > STREAM_PKT_BYTES)
                            pkt_length <= STREAM_PKT_BYTES;
                        else
                            pkt_length <= fifo_even_length;
                        state <= ST_STREAM_SEND;
                    end
                    else begin
                        state <= ST_IDLE;
                    end
                end
                else begin
                    state <= ST_IDLE;
                end
            end

        ST_STREAM_SEND:
            begin
                pkt_tx_en <= 1'd1;
                state <= ST_STREAM_DONE;
            end

        ST_STREAM_DONE:
            begin
                pkt_tx_en <= 1'd0;
                if(eth_tx_done)
                    state <= ST_STREAM_GAP;
            end

        ST_STREAM_GAP:
            begin
                pkt_tx_en <= 1'd0;
                if(cnt_dly_time >= cnt_dly_min)begin
                    cnt_dly_time <= 28'd0;
                    if(stream_mode || fifo_rd_cnt >= 12'd2)
                        state <= ST_STREAM_WAIT;
                    else
                        state <= ST_IDLE;
                end
                else begin
                    cnt_dly_time <= cnt_dly_time + 1'b1;
                    state <= ST_STREAM_GAP;
                end
            end

          default:state <= ST_IDLE;

    endcase
  end
    
endmodule
