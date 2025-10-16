// ============================================================================
// Module: upload_adapter
// Description: 协议适配器 - 将"每字节一个req脉冲"转换为"数据包期间req保持高"
//
// 功能：
//   - 输入：handler的每字节脉冲式上传 (upload_active信号指示上传期间)
//   - 输出：packer需要的数据包式上传 (req在整个数据包期间保持高)
//
// 工作原理：
//   1. 当 upload_active=1 时，输出 req=1
//   2. 当 upload_active=0 时，输出 req=0
//   3. 数据和valid信号直接透传
//
// 接口说明：
//   upload_active: 由handler提供，表示正在上传数据包（主状态机在UPLOAD状态）
//
// 作者: Claude Code
// 日期: 2025-10-05
// ============================================================================

module upload_adapter (
    input wire clk,
    input wire rst_n,

    // 输入：来自handler的上传信号
    input wire       handler_upload_active,  // 上传活跃信号（handler在UPLOAD状态）
    input wire [7:0] handler_upload_data,
    input wire [7:0] handler_upload_source,
    input wire       handler_upload_valid,
    output wire      handler_upload_ready,

    // 输出：到packer的上传信号
    output reg       packer_upload_req,
    output reg [7:0] packer_upload_data,
    output reg [7:0] packer_upload_source,
    output reg       packer_upload_valid,
    input wire       packer_upload_ready
);

    // 简单透传逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            packer_upload_req <= 1'b0;
            packer_upload_data <= 8'h00;
            packer_upload_source <= 8'h00;
            packer_upload_valid <= 1'b0;
        end else begin
            // req信号：跟随upload_active
            packer_upload_req <= handler_upload_active;

            // 数据和source：直接透传
            packer_upload_data <= handler_upload_data;
            packer_upload_source <= handler_upload_source;

            // valid信号：直接透传
            packer_upload_valid <= handler_upload_valid;
        end
    end

    // ready信号：反向透传
    assign handler_upload_ready = packer_upload_ready;

endmodule
