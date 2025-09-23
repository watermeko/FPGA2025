`timescale 1ns / 1ps
module dac_tb;

// 200MHz clock (5ns period)
localparam CLK_PERIOD = 5;
logic clk, rst_n;
logic [31:0] fre_word, pha_word;
logic [13:0] dac_data;
logic dac_clk;

// Clock generation
initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// Reset generation
initial begin
    rst_n = 0;
    #50 rst_n = 1;
end

// Test stimulus
initial begin
    fre_word = 0;
    pha_word = 0;
    
    // Wait for reset release
    wait(rst_n);
    #20;
    
    $display("=== DAC Test Started ===");
    
    // Test 1: 1MHz sine wave, 0° phase
    $display("Test 1: 1MHz, 0° phase");
    fre_word = 32'h028F5C29;  // 1MHz
    pha_word = 32'h00000000;  // 0°
    #5000;
    
    // Test 2: 5MHz sine wave, 90° phase  
    $display("Test 2: 5MHz, 90° phase");
    fre_word = 32'h0D49FB83;  // 5MHz
    pha_word = 32'h40000000;  // 90°
    #2000;
    
    // Test 3: 10MHz sine wave, 180° phase
    $display("Test 3: 10MHz, 180° phase");
    fre_word = 32'h1A93F706;  // 10MHz
    pha_word = 32'h80000000;  // 180°
    #1000;
    
    // Test 4: 25Mhz sine wave, 270° phase
    $display("Test 4: 25MHz, 270° phase");
    fre_word = 32'h3B9ACA00;  // 25MHz
    pha_word = 32'hC0000000;  // 270°
    #1000;

    $display("=== DAC Test Completed ===");
    $finish;
end

// Monitor outputs
always @(posedge clk) begin
    if (rst_n && ($time % 1000 == 0)) begin
        $display("Time %0t: dac_data = %d (0x%h)", $time, $signed(dac_data), dac_data);
    end
end

DAC u_DAC(
    .clk      	(clk       ),
    .rst_n    	(rst_n     ),
    .fre_word 	(fre_word  ),
    .pha_word 	(pha_word  ),
    .dac_data 	(dac_data  ),
    .dac_clk  	(dac_clk   )
);

endmodule