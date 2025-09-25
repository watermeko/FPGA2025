`timescale 1ns/1ps

`define IF_DATA_WIDTH 8
   
module I2C (
    input wire  clk,
    input	    rst_n,
    input	    key2,
    inout	    scl,
    inout	    sda,
    output      scl_pull,
    output      sda_pull,	
    output      error_flag,
         
    output reg cstate_flag=1'b0,
    output     interrupt
);

/////////////////////////////////////////////////////////////////////
/*reg/wire 												 		   */
 
 wire                        I_TX_EN;
 wire [2:0]                  I_WADDR;
 wire [`IF_DATA_WIDTH-1:0]   I_WDATA;
 wire                        I_RX_EN;
 wire [2:0]                  I_RADDR;
 wire [`IF_DATA_WIDTH-1:0]   O_RDATA;
 
 wire                        rstn1;
 wire                        start;
 reg [7:0]                   delay_rst=0;
 reg [7:0]                   delay=0;
 reg [15:0]                  counter0=0;
 reg                         clk_en=0; 
 
 wire                        cstate_flag_temp;
 reg                         cstate_flag_temp1;  
///////////////////////////////////////////////////////////////////////////////////////////////////
 wire                        clk_sys;

Gowin_PLL_i2c u_pll_i2c(
    .clkin(clk),
    .clkout0(clk_sys),
    .mdclk(clk)
);


assign rstn1=&{delay_rst[5],!delay_rst[4],!delay_rst[3],!delay_rst[2],!delay_rst[1],!delay_rst[0]};

assign start=&{delay[5],!delay[4],!delay[3],!delay[2],!delay[1],!delay[0]};

always @(posedge clk_sys) 
     if(counter0==16'd49999) begin
	    counter0 <= 16'd0;
		clk_en <= 1'b1;
	 end
	 else begin
	    counter0 <= counter0 + 16'd1;
		clk_en <= 1'b0;	 
	 end

always @(posedge clk_sys)
     if(clk_en==1'b1) begin
        delay[7:1] <= delay[6:0];
        delay[0] <= key2;	 
	 
        delay_rst[7:1] <= delay_rst[6:0];
        delay_rst[0] <= rst_n;
     end
	 
always @(posedge clk_sys)
     begin
        cstate_flag_temp1 <= cstate_flag_temp;
     end

always @(posedge clk_sys)
     if(cstate_flag_temp1 == 1'b0 && cstate_flag_temp == 1'b1) begin
        cstate_flag <= ~cstate_flag;
     end	 
	 
/////////////////////////////////////////////////////////////////////
  master_sram_iic 	    u_master_sram_iic
  (
      .I_CLK              ( clk_sys                 ),
      .I_RESETN           ( ~rstn1                  ),
	  .start              ( start                   ),
      .I_TX_EN            ( I_TX_EN                 ),
      .I_WADDR            ( I_WADDR                 ),
      .I_WDATA            ( I_WDATA                 ),
      .I_RX_EN            ( I_RX_EN                 ),
      .I_RADDR            ( I_RADDR                 ),
      .O_RDATA            ( O_RDATA                 ),
      .cstate_flag        ( cstate_flag_temp        ),
      .error_flag         ( error_flag              )
  );

  I2C_MASTER        u_i2c_master
  (
      .I_CLK              ( clk_sys                 ),
      .I_RESETN           ( ~rstn1                  ),
      .I_TX_EN            ( I_TX_EN                 ),
      .I_WADDR            ( I_WADDR                 ),
      .I_WDATA            ( I_WDATA                 ),
      .I_RX_EN            ( I_RX_EN                 ),
      .I_RADDR            ( I_RADDR                 ),
      .O_RDATA            ( O_RDATA                 ),
      .O_IIC_INT          ( interrupt                ),
      .SCL                ( scl                     ),
      .SDA                ( sda                     )
  );               
    
assign scl_pull =1'b1;	
assign sda_pull =1'b1;

endmodule
  

