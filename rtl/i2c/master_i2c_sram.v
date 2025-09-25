`timescale 1ns/1ps

`define IF_DATA_WIDTH 8

module master_sram_iic (
     I_CLK,   
     I_RESETN,
     start,
     I_TX_EN, 
     I_WADDR, 
     I_WDATA, 
     I_RX_EN,
     I_RADDR, 
     O_RDATA,     
     cstate_flag,
     error_flag
);

 input                        I_CLK;
 input                        I_RESETN;
 input                        start; 
 output                       I_TX_EN;
 output [2:0]                 I_WADDR;
 output [`IF_DATA_WIDTH-1:0]  I_WDATA;   
 output                       I_RX_EN;  
 output [2:0]                 I_RADDR;
 input  [`IF_DATA_WIDTH-1:0]  O_RDATA;
 output                       error_flag;
 output                       cstate_flag; 
 
//////////////////////////////////////////////////////////////////////////
//  Internal Wires/Registers
 reg                          I_TX_EN;
 reg [2:0]                    I_WADDR;
 reg [`IF_DATA_WIDTH-1:0]     I_WDATA;
 reg                          I_RX_EN;
 reg [2:0]                    I_RADDR;  

//define reg address of IIC-Master
 parameter     PRERLO      = 3'b000;
 parameter     PRERHI      = 3'b001;
 parameter     CTR         = 3'b010;
 parameter     TXR         = 3'b011; 
 parameter     RXR         = 3'b011; 
 parameter     CR          = 3'b100; 
 parameter     SR          = 3'b100;

 parameter  TX_DATA     = 8'b00000110; 
 
// ---------- PRESCALE: for 50MHz master clock and SCL = 100kHz ----------
// Prescale = (master_clock / (5 * SCL)) - 1
// For master_clock = 50_000_000 Hz and SCL = 100_000 Hz:
// Prescale = (50_000_000 / 500_000) - 1 = 100 - 1 = 99 -> 0x0063
parameter    CLK_Div_L    = 8'h63; // low byte = 0x63 (99)
parameter    CLK_Div_H    = 8'h00; // high byte = 0x00

 parameter    EN_IP        = 8'h80; 
                          
 parameter     STA_WR_CR    = 8'h90; //start+write_ack
 parameter     WR_CR        = 8'h10; //write+ack
 parameter    STP_WR_CR    = 8'h50; //stop+write+ack
 parameter    STP_CR       = 8'h40; //stop+write+ack
                          
 parameter     STA_RD_CR    = 8'hA0; //start+read+ack 
 parameter     RD_CR        = 8'h20; //read+ack
 parameter     RD_NACKCR    = 8'h28; //read+nack
 parameter     STP_NCR      = 8'h40; //stop+nack
 parameter     STP_RD_NCR   = 8'h68; //stop+read+nack
 
 parameter     RD           = 1'b1;
 parameter     WR           = 1'b0;
 
//define the address of IIC-Slave device 
 parameter     DEV_ADDR    = 7'b1010_000;
 
 reg[4:0]    wr_index;
 reg[1:0]    wr_reg;
 reg[1:0]    rd_reg0;
// reg[1:0]    rd_ack;

 reg[1:0]    wr_rd_stop;
 
 reg[2:0]    reg_addr;
 reg[7:0]    reg_data;
 
 reg[7:0]    sr_data0;
// reg[7:0]    sr_ack;     //sr: status register?
  
// reg [7:0]  tx_data;
 reg        error_reg = 0/* synthesis syn_keep=1 */;
 reg        cstate_flag_reg = 0/* synthesis syn_keep=1 */;
 
 reg        start_dl;
//--------------------------------------------------------------------

///////////////////////////////////////////////////////////////////////
//define the reg addr and data
always @(*)
begin
    if(~I_RESETN)
    begin
        reg_addr <=0;
        reg_data <=0;

    end
    else
    begin
    case(wr_index)
        0:
        begin
            reg_addr <= PRERLO;
            reg_data <= CLK_Div_L;  //Write Prescale data low 8bit
        end
        
        1:
        begin
            reg_addr <= PRERHI;
            reg_data <= CLK_Div_H;  //Write Prescale data high 8bit
        end
        
        2:
        begin
            reg_addr <= CTR;     //Write Control Reg 8'h80，enable master
            reg_data <= EN_IP;
        end
        
        3:
        begin
            reg_addr <= TXR;  //Write Slave address + WR bit
            reg_data <= {DEV_ADDR,WR};
        end
        
        4: 
        begin
            reg_addr <= CR;  //Write Command Reg 8'h90，start+write_ack
            reg_data <= STA_WR_CR; 
        end
        
        5:
        begin
            reg_addr <= SR; //Read Status Reg for TIP
            reg_data <= 8'h00;
        end
        
        6:
        begin
            reg_addr <= TXR;  //Write TX REG
            reg_data <= 8'h00; //Slave memory address 
        end
        
        7:
        begin
            reg_addr <= CR;  //Write Command Reg 8'h10，start sending
            reg_data <= WR_CR;
        end
        
        8:
        begin
            reg_addr <= SR;  //Read Status Reg for TIP
            reg_data <= 8'h00;
        end
        
        9:
        begin
            reg_addr <= TXR; //Write TX REG
            reg_data <= TX_DATA; //TX Data
        end
        
        10:
        begin
            reg_addr <= CR;  //Write Command Reg 8'h50，stop+write+ack
            reg_data <= STP_WR_CR;
        end
        
        11:
        begin
            reg_addr <= SR;  //Read Status Reg for TIP
            reg_data <= 8'h00;
        end
        
        12:
        begin
            reg_addr <= TXR;  //Write Slave address + WR bit
            reg_data <= {DEV_ADDR,WR};
        end
        
        13:
        begin
            reg_addr <= CR; //Write Command Reg 8'h90，start+write_ack
            reg_data <= STA_WR_CR;
        end
        
        14:
        begin
            reg_addr <= SR;  //Read Status Reg for TIP
            reg_data <= 8'h00;
        end
        
        15:
        begin
            reg_addr <= TXR; //Write TX REG
            reg_data <= 8'h00; //Slave memory address
        end
        
        16:
        begin
            reg_addr <= CR;  //Write Command Reg 8'h10，start sending
            reg_data <= WR_CR;
        end
        
        17:
        begin
            reg_addr <= SR;  //Read Status Reg for TIP
            reg_data <= 8'h00;
        end
        
        18:
        begin
            reg_addr <= TXR;  //Write Slave address + RD bit
            reg_data <= {DEV_ADDR,RD};
        end
        
        19:
        begin
            reg_addr <= CR; //Write Command Reg 8'h90，start+write_ack
            reg_data <= STA_WR_CR;
        end
        
        20: 
        begin
            reg_addr <= SR; //Read Status Reg for TIP
            reg_data <= 8'h00;
        end
        
        21:
        begin
            reg_addr <= CR; //Write Command Reg 8'h28，read+nack
            reg_data <= RD_NACKCR;
        end
        
        22:
        begin
            reg_addr <= SR; //Read Status Reg for TIP
            reg_data <= 8'h00;
        end
        
        23:
        begin
            reg_addr <= RXR;//read data from Receive_reg
            reg_data <= 8'h00;
        end
        
        24:
        begin
            reg_addr <= CR; //Write Command Reg 8'h40，stop+nack
            reg_data <= STP_NCR;
        end
        
        25:
        begin
            reg_addr <= SR; //Read Status Reg for TIP
            reg_data <= 8'h00;
        end    
        
        default:
        begin
            reg_addr <=0;
            reg_data <=0;
        end
    
    endcase
    end
end
        
        
always @(negedge I_RESETN or posedge I_CLK)
    if(~I_RESETN)
       start_dl <= 1'b0;     
    else
       start_dl <= start;        
        
//Firstly, verify the byte write mode of EEPROM
always @(negedge I_RESETN or posedge I_CLK) 
begin
    if(~I_RESETN)
    begin
        I_TX_EN <= 1'b0; 
        I_WADDR <= {3{1'b0}}; 
        I_WDATA <= {`IF_DATA_WIDTH{1'b0}}; 
        I_RX_EN <= 1'b0;
        I_RADDR <= {3{1'b0}};
        
        wr_index <= 0;
        wr_reg <= 0;
        
        rd_reg0 <=0;
        sr_data0 <=0;
//      rd_ack <=0;    
//      sr_ack <=0;
        wr_rd_stop <=0;

        //tx_data<=8'h08;
        cstate_flag_reg <= 1'b0;        
        error_reg<=0;
    end
    else 
    begin
        if(wr_index==0)
        begin
            case(wr_reg)
            0:
              begin
                 if((start_dl == 1'b0) && (start == 1'b1)) begin //start rising edge
                  I_TX_EN <= 1'b1; 
                  I_WADDR <= reg_addr; 
                  I_WDATA <= reg_data; 
                
                  wr_reg <= 1;
                 end
                 else begin
                  I_TX_EN <= 1'b0; 
                  I_WADDR <= {3{1'b0}}; 
                  I_WDATA <= {`IF_DATA_WIDTH{1'b0}}; 
                  
                  cstate_flag_reg <= 1'b0;
//                error_reg<=0;
                
                  wr_reg <= 0;
                 end            
              end
            1:
              begin
                  I_TX_EN <= 1'b0;
                  I_WADDR <= 1'b0;
                  I_WDATA <= 0;
                            
                  wr_reg <= 2; 
              end
            2:
              begin
                  wr_index <= wr_index + 1;
                  wr_reg <= 0;
              end
            default:
              begin
                  I_TX_EN <= 1'b0;
                  I_WADDR <= 1'b0;
                  I_WDATA <= 0;
                  
                  wr_index <= 0;
                  wr_reg <= 0;
              end                
            endcase    
        end
        
        else if((wr_index < 5) || ((wr_index >5) &&(wr_index < 8)) || ((wr_index >8) &&(wr_index < 11)) || 
               ((wr_index >11) &&(wr_index < 14)) || ((wr_index >14) &&(wr_index < 17))||((wr_index >17) &&(wr_index < 20))||
               (wr_index==21)||(wr_index==24))
        begin
            case(wr_reg)
            0:
              begin
                  I_TX_EN <= 1'b1; 
                  I_WADDR <= reg_addr; 
                  I_WDATA <= reg_data; 
                
                  wr_reg <= 1;
              end
            1:
              begin
                  I_TX_EN <= 1'b0;
                  I_WADDR <= 1'b0;
                  I_WDATA <= 0;
                            
                  wr_reg <= 2; 
              end
            2:
              begin
                  wr_index <= wr_index + 1;
                  wr_reg <= 0;
              end
            default:
              begin
                  I_TX_EN <= 1'b0;
                  I_WADDR <= 1'b0;
                  I_WDATA <= 0;
                  
                  wr_index <= 0;
                  wr_reg <= 0;
              end            
            endcase
        end
        
        else if((wr_index==5)||(wr_index==8)||(wr_index==11)||(wr_index==14)||(wr_index==17)||
               (wr_index==20)||(wr_index==22)||(wr_index==25))
        begin
            case(rd_reg0)
            0:
              begin
                  I_RX_EN <= 1'b1;
                  I_RADDR <= reg_addr;
                
                  rd_reg0 <= 1;
              end
            1:
              begin
                  I_RX_EN <= 1'b0;
                
                  rd_reg0 <= 2; 
              end
            2:
              begin
                  sr_data0 <= O_RDATA;
                    
                  rd_reg0 <= 3;                    
              end    
            3:
              begin
                  if(~sr_data0[1])
                  begin
                      wr_index <= wr_index + 1;
                      rd_reg0 <= 0;
                  end
                  else
                      rd_reg0 <= 0;
              end        
            endcase
        end

        else if(wr_index==14)
        begin
            case(rd_reg0)
            0:
              begin
                  I_RX_EN <= 1'b1;
                  I_RADDR <= reg_addr;
                
                  rd_reg0 <= 1;
              end
            1:
              begin
                  I_RX_EN <= 1'b0;
                
                  rd_reg0 <= 2; 
              end
            2:
              begin
                  sr_data0 <= O_RDATA;
                    
                  rd_reg0 <= 3;                    
              end    
            3:
              begin
                  if(~sr_data0[1])
                  begin
                      wr_index <= 19;
                      rd_reg0 <= 0;
                  end
                  else
                      rd_reg0 <= 0;
              end        
            endcase
        end        
        
        else if(wr_index==23)
        begin
            case(wr_rd_stop)
            0:
              begin
                  I_RX_EN <= 1'b1;
                  I_RADDR <= reg_addr;
                
                  wr_rd_stop <= 1;
              end
            1:
              begin
                  I_RX_EN <= 1'b0;
                
                  wr_rd_stop <= 2; 
              end
            2:
              begin
                  cstate_flag_reg <= 1'b1;
              
                  wr_rd_stop <= 3;    
                  if(O_RDATA != TX_DATA)
                     error_reg<=1; 
              end    
            3:
              begin
                  wr_index <= wr_index + 1;
                  wr_rd_stop <= 0;
              end        
            endcase
        end    

        else if(wr_index==26)
        begin
                wr_index <= 0;        
        end        
    end
end

////////////////////////////////////////////////////
assign error_flag=error_reg;
assign cstate_flag=cstate_flag_reg;
////////////////////////////////////////////////////

endmodule
