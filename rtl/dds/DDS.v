`timescale 1 ns / 1 ns

/*
*   Date : 2024-07-02
*   Author : nitcloud
*   Module Name:   DDS.v - DDS
*   Target Device: [Target FPGA and ASIC Device]
*   Tool versions: vivado 18.3 & DC 2016
*   Revision Historyc :
*   Revision :
*       Revision 0.01 - File Created
*       Revision 0.02 - Added square wave output support
*   Description : Direct digital frequency synthesis.
*                 Supports sine, triangle, sawtooth, and square wave outputs.
*   Dependencies: accuml + Sin
*   Company : ncai Technology .Inc
*   Copyright(c) 1999, ncai Technology Inc, All right reserved
*/

module DDS #(
        // Output signal width.
        parameter OUTPUT_WIDTH = 12,
        // Phase width.
        parameter PHASE_WIDTH  = 32
    ) (
        // Clock input
        input                       clock,
        // Asynchronous reset with active high
        input                       reset, 

        // Frequency control word.
        // (out clk frequency * 2^PHASE_WIDTH)/clock frequency
        input  [PHASE_WIDTH-1 : 0]  fre_word, 
        
        // Phase control word.
        // (out phase * 2^PHASE_WIDTH) / (clock frequency * 360°)
        input  [PHASE_WIDTH-1 : 0]  pha_word, 

        // Out Sine wave.
        output [OUTPUT_WIDTH-1 : 0] wave_sin,
        // Out Triangle wave.
        output [OUTPUT_WIDTH-1 : 0] wave_tri,
        // Out Sawtooth wave.
        output [OUTPUT_WIDTH-1 : 0] wave_saw,
        // Out Square wave.
        output [OUTPUT_WIDTH-1 : 0] wave_sqr,
        // Out Trapezoidal wave.
        output [OUTPUT_WIDTH-1 : 0] wave_trap
    ); 

    wire [PHASE_WIDTH-1:0] Q;

    accuml #(
        .WIDTH 		( PHASE_WIDTH 		))
    u_accuml(
        //ports
        .clock   		( clock   		),
        .reset   		( reset   		),
        .clr     		( 1'b0     		),
        .add_sub 		( 1'b0  		),
        .D       		( fre_word      ),
        .Q       		( Q       		)
    );

    reg [PHASE_WIDTH-1:0] phase;
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            phase <= 0;
        end
        else begin
            phase <= Q + pha_word;
        end
    end

    reg [9:0] addr;
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            addr <= 0;
        end
        else begin
            addr <= phase[PHASE_WIDTH-1:PHASE_WIDTH-10];
        end
    end

    wire [15:0]	douta;
    Sin u_Sin(
        //ports
        .clka  		( clock  		),
        .rsta  		( reset  		),
        .addra 		( addr  		),
        .douta 		( douta 		)
    );

    assign wave_sin = douta >>> (16-OUTPUT_WIDTH);
    assign wave_saw = phase[PHASE_WIDTH-1:PHASE_WIDTH-OUTPUT_WIDTH];
    assign wave_tri = wave_saw[OUTPUT_WIDTH-1] ? 
                      {{ wave_saw[OUTPUT_WIDTH-2]}, ~wave_saw[OUTPUT_WIDTH-3:0], 1'b0}: 
                      {{~wave_saw[OUTPUT_WIDTH-2]},  wave_saw[OUTPUT_WIDTH-3:0], 1'b0};
    
    assign wave_sqr = phase[PHASE_WIDTH-1] ? 
                  {{1'b1}, {(OUTPUT_WIDTH-1){1'b0}}} :    // -8192 (0x2000)
                  {{1'b0}, {(OUTPUT_WIDTH-1){1'b1}}};     // +8191 (0x1FFF)

    // 梯形波生成逻辑
    // 将一个周期分为4个阶段：上升、平台1、下降、平台2
    // 使用相位的高2位来判断当前阶段
    wire [1:0] trap_phase = phase[PHASE_WIDTH-1:PHASE_WIDTH-2];
    wire [OUTPUT_WIDTH-1:0] phase_segment = phase[PHASE_WIDTH-3:PHASE_WIDTH-OUTPUT_WIDTH-2];
    
    assign wave_trap = (trap_phase == 2'b00) ? {{1'b0}, phase_segment, 1'b0} :      // 上升阶段 (0-25%)
                       (trap_phase == 2'b01) ? {{1'b0}, {(OUTPUT_WIDTH-1){1'b1}}} : // 高平台 (25-50%)
                       (trap_phase == 2'b10) ? {{1'b0}, ~phase_segment, 1'b0} :     // 下降阶段 (50-75%)
                                               {{1'b1}, {(OUTPUT_WIDTH-1){1'b0}}};   // 低平台 (75-100%)



    // 或者更简单的写法：
    // assign wave_sqr = phase[PHASE_WIDTH-1] ? 14'h2000 : 14'h1FFF;
endmodule
