`timescale 1ns/1ps

`define IF_DATA_WIDTH 8

// ====================================================================
// 顶层模块：i2c_handle (整合了 CDC 接口和 I2C 物理驱动)
// ====================================================================
module i2c_handler (
    // --- 时钟/复位/按键接口 (来自原 I2C 模块) ---
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i2c_clk,
    // input  wire        key2,

    // --- CDC 指令接口 (与 master_i2c_sram 连接) ---
    input  wire [7:0]  cmd_type,
    input  wire [15:0] cmd_length,
    input  wire [7:0]  cmd_data,
    input  wire [15:0] cmd_data_index,
    input  wire        cmd_start,
    input  wire        cmd_data_valid,
    input  wire        cmd_done,
    output wire        cmd_ready,

    // --- CDC 数据上传接口 (与 master_i2c_sram 连接) ---
    output wire        upload_req,
    output wire [7:0]  upload_data,
    output wire [7:0]  upload_source,
    output wire        upload_valid,
    input  wire        upload_ready,

    inout              SCL,
    inout              SDA,

    // --- 状态与中断输出 (来自原 I2C 模块/I2C_MASTER) ---
    output wire        scl_pull,
    output wire        sda_pull,
    output wire        error_flag,
    output reg         cstate_flag,
    output wire        interrupt
);

// --- 内部信号声明 ---
    // SRAM 接口信号 (连接 master_i2c_sram 和 I2C_MASTER)
    wire I_TX_EN_w;
    wire [2:0] I_WADDR_w;
    wire [`IF_DATA_WIDTH-1:0] I_WDATA_w;
    wire I_RX_EN_w;
    wire [2:0] I_RADDR_w;
    wire [`IF_DATA_WIDTH-1:0] O_RDATA_w;

    // I2C IP 核反馈信号
    wire error_flag_w;
    wire interrupt_w;
    wire cstate_flag_temp_w;
    
    // wire start; // key2相关
    reg [7:0] delay_rst=0;
    // reg [7:0] delay=0; // key2相关
    reg [15:0] counter0=0;
    reg clk_en=0;
    reg cstate_flag_temp1; 

    // 映射顶层输出
    assign error_flag = error_flag_w;
    assign interrupt = interrupt_w;

    // 复位同步和延时
    assign rstn1=&{delay_rst[5],!delay_rst[4],!delay_rst[3],!delay_rst[2],!delay_rst[1],!delay_rst[0]};

    // 按键同步和延时  <--- key2相关
    // assign start=&{delay[5],!delay[4],!delay[3],!delay[2],!delay[1],!delay[0]};

    // 50MHz 时钟分频 (50MHz/50000 = 1kHz)
    always @(posedge i2c_clk) 
        if(counter0==16'd49999) begin
            counter0 <= 16'd0;
            clk_en <= 1'b1;
        end
        else begin
            counter0 <= counter0 + 16'd1;
            clk_en <= 1'b0;
        end

    // 慢时钟域下的同步 (仅处理 rst_n)
    always @(posedge i2c_clk)
        if(clk_en==1'b1) begin
            // delay[7:1] <= delay[6:0]; // <--- key2相关
            // delay[0] <= key2; // <--- key2相关
        
            delay_rst[7:1] <= delay_rst[6:0];
            delay_rst[0] <= rst_n;
        end

    // 状态标志同步和跳变捕获
    always @(posedge i2c_clk) begin
        cstate_flag_temp1 <= cstate_flag_temp_w;
    end

    always @(posedge i2c_clk) begin
        if(cstate_flag_temp1 == 1'b0 && cstate_flag_temp_w == 1'b1) begin
            cstate_flag <= ~cstate_flag;
        end
    end
    
    // 物理接口上拉
    assign scl_pull =1'b1;
    assign sda_pull =1'b1;

// --- 2. 实例化 CDC 接口控制逻辑 (master_i2c_sram) ---
    master_i2c_sram u_master_i2c_sram (
        // CDC Command Interface
        .clk             (clk),       // 使用系统时钟
        .rst_n           (rst_n),         // 使用同步复位
        .cmd_type        (cmd_type),
        .cmd_length      (cmd_length),
        .cmd_data        (cmd_data),
        .cmd_data_index  (cmd_data_index),
        .cmd_start       (cmd_start),
        .cmd_data_valid  (cmd_data_valid),
        .cmd_done        (cmd_done),
        .cmd_ready       (cmd_ready),
        
        // CDC Upload Interface
        .upload_req      (upload_req),
        .upload_data     (upload_data),
        .upload_source   (upload_source),
        .upload_valid    (upload_valid),
        .upload_ready    (upload_ready),
        
        // SRAM 接口 (输出到 I2C_MASTER)
        .I_TX_EN         (I_TX_EN_w),
        .I_WADDR         (I_WADDR_w),
        .I_WDATA         (I_WDATA_w),
        .I_RX_EN         (I_RX_EN_w),
        .I_RADDR         (I_RADDR_w),
        .O_RDATA         (O_RDATA_w),       
        .ERROR_FLAG  (error_flag_w),      
        .INTERRUPT   (interrupt_w),      
        .CSTATE_FLAG (cstate_flag_temp_w)
    );

// --- 3. 实例化 I2C IP 核接口包装 (I2C_MASTER) ---
    I2C_MASTER u_i2c_master (
        .I_CLK     (clk),     // 使用系统时钟
        .I_RESETN  (~rst_n),
        .I_TX_EN   (I_TX_EN_w),
        .I_WADDR   (I_WADDR_w),
        .I_WDATA   (I_WDATA_w),
        .I_RX_EN   (I_RX_EN_w),
        .I_RADDR   (I_RADDR_w),
        .O_RDATA   (O_RDATA_w),
        .O_IIC_INT (interrupt_w), // 中断信号
        .SCL       (SCL),
        .SDA       (SDA)
    );

endmodule