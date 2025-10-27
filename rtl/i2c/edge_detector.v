// edge_detector.v
module edge_detector (
    input  logic clk,       // 高速系统时钟
    input  logic rst_n,     // 系统复位
    input  logic signal_in, // 要检测的异步信号 (如 scl 或 sda)
    output logic posedge_tick, // 上升沿检测脉冲 (同步于clk)
    output logic negedge_tick  // 下降沿检测脉冲 (同步于clk)
);
    logic signal_sync_d1, signal_sync_d2;

    // 2级同步器，防止亚稳态
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            signal_sync_d1 <= 1'b0;
            signal_sync_d2 <= 1'b0;
        end else begin
            signal_sync_d1 <= signal_in;
            signal_sync_d2 <= signal_sync_d1;
        end
    end

    // 边沿检测逻辑
    assign posedge_tick = signal_sync_d1 & ~signal_sync_d2;
    assign negedge_tick = ~signal_sync_d1 & signal_sync_d2;

endmodule