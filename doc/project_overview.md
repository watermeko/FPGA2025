# FPGA2025 工程综述

## 1. 项目定位与目标
- **目标器件**：GOWIN GW5A-25（封装 UG324C2/I1），详见 `constraints/pin_cons.cst`。
- **系统角色**：面向实验室与嵌入式调试场景的多协议通信与信号发生平台，核心接口为 USB CDC。
- **功能覆盖**：UART / I2C / SPI / 1-Wire 等串行协议，双通道 DAC 输出，自定义波形、DDS、PWM，数字信号测量（DSM）与 8 通道逻辑捕获，以及基于 DDR3 + RGMII 的高速数据通道。
- **上位机生态**：`software/` 内的 Python/PowerShell 工具实现指令帧(`0xAA55 | CMD | LEN | … | CHECKSUM`)的快速生成与调试。

## 2. 硬件平台与外设
- **时钟源**：外部 50 MHz 输入经多级 PLL 生成 24 MHz、60 MHz、120 MHz、480 MHz 及 400 MHz（DDR）等时钟，相关 IP 位于 `rtl/clk/`。
- **模数链路**：`rtl/eth/acm9238_ddr3_rgmii.v` 集成 AD9238 ADC、板载多路模拟复用、DDR3 缓冲与 RGMII 以太网发送。
- **数模链路**：`rtl/dds/` 下的 `dac_driver.sv`、`dac_handler.sv`、`custom_waveform_handler.sv` 支持双通道 DAC（200 MHz 时钟域）。
- **外设接口**：USB PHY、UART 扩展、I2C 主/从、SPI 主机、1-Wire 主机、8 路 PWM、数字输入（DSM/DC）等在 `rtl/top.v` 中全部引出。

## 3. 系统顶层结构
### 3.1 模块互连
```
USB PHY → rtl/usb/usb_cdc.v → rtl/cdc.v
          │                      │
          └→ protocol_parser → command_processor → 功能模块 (UART / SPI / I2C / PWM / DAC / DSM / DC / One-Wire …)
                                                   │
                                         upload_adapter → upload_packer → upload_arbiter → usb_cdc (EP2/EP3 FIFO)
```
- `rtl/top.v` 负责时钟、复位、USB CDC、CDC 主控与高速采集 (`acm9238_ddr3_rgmii`) 的集成。
- `rtl/cdc.v` 是指令/上传的中枢，协调所有 handler、上传打包与 USB 回写。
- 高速数字捕获通过 `dc_usb_upload_*` 直通 USB EP3 通道，支持背压信号 `dc_fifo_afull`。

### 3.2 命令处理流程
1. `protocol_parser.v` 在 60 MHz SYSCLK 下解析帧结构并缓存 Payload（最大 1024 B）。
2. `command_processor.v` 将 Payload 逐字节广播给各 handler，并处理心跳等无数据指令。
3. 各 handler 根据指令号进入状态机，执行配置、采集或回传，并通过上传总线报告状态。

## 4. 核心 RTL 模块一览

### 4.1 基础框架
- `rtl/top.v`：顶层装配、PLL、USB CDC、CDC、DAC 驱动与以太网模块实例化。
- `rtl/cdc.v`：命令路由、上传仲裁、DAC/ADC 接口连接及调试信号输出。
- `rtl/protocol_parser.v`：SOF、长度、校验处理及 Payload RAM。
- `rtl/command_processor.v`：多周期 Payload 读取、指令广播与 USB 回传接口。

### 4.2 通信与控制
- `rtl/uart/uart_handler.v` + `uart.v`：波特率、数据位可配置，内建 TX/RX FIFO。
- `rtl/spi/spi_handler.v` + `simple_spi_master.v`：主机模式时序驱动与回读上传。
- `rtl/i2c/i2c_handler.v`、`i2c_slave_handler.sv`：主从指令解析，文档位于 `rtl/i2c/*.md`。
- `rtl/one_wire/one_wire_master.v`、`one_wire_handler.v`：1-Wire 主机时序与命令桥接。

### 4.3 信号生成
- `rtl/pwm/pwm_handler.v` + `pwm_multi_channel.sv`：8 通道 PWM，16 位分辨率。
- `rtl/dds/DDS.v`、`rtl/dds/dac_handler.sv`：DDS 相位累加器与幅度控制。
- `rtl/dds/custom_waveform_handler.sv`：两路 256×14 bit SDPB，自定义波形、循环与播放控制。

### 4.4 信号测量与捕获
- `rtl/logic/digital_signal_measure.sv`、`dsm_multichannel_handler.sv`：多通道脉宽/周期测量。
- `rtl/logic/digital_capture_handler.v`：8 位打包、采样分频、内部同步 FIFO、实时上传。
- `rtl/digital_signal_measure.v`：单通道测量核心，供 DSM/自测使用。

### 4.5 高速数据链路
- `rtl/eth/acm9238_ddr3_rgmii.v`：ADC 采样、DDR3 缓冲、UDP/RGMII 发送、动态 PLL 调谐。
- `rtl/eth/ddr3_memory_interface/`、`rtl/eth/gmii_rgmii_gmii/`：厂商 IP 与协议桥接。
- `rtl/upload_arbiter.v`、`rtl/upload_packer_0.v`、`rtl/upload_adapter_0.v`：上传打包/仲裁。

### 4.6 支撑模块
- `rtl/clk/`：`Gowin_PLL_24`, `gowin_pll`, `ad_ddr_eth_pll` 及动态重配置接口。
- `rtl/usb/usb_cdc.v`：Soft PHY、USB 描述符(`usb_descriptor.v`)及 EP FIFO。
- `src/pll_init.v`：DDR3 初始化微程序。

## 5. 时钟与复位策略
- 主复位输入经 `rst_n_sync*` 同步到主时钟、24 MHz 与 400 MHz 域，确保 PLL 锁定后释放。
- `Gowin_PLL_24`、`Gowin_PLL` 级联生成 CDC（60 MHz）与 DAC（120 MHz/200 MHz）时钟。
- `ad_ddr_eth_pll` + `pll_mDRP_intf` 支持运行时重配置 DDR/以太网频点。
- `cdc.v` 内部对异步输入（数字捕获、DSM）使用双触发器同步，关键路径配合背压信号防止数据丢失。

## 6. 数据上传与缓冲体系
- 每个 handler 通过 `upload_adapter` 规范化上传请求（active/req/data/source/valid）。
- `upload_packer` 将多个数据源复用并添加帧头 (`0xAA44`)，`upload_arbiter` 依据固定优先级调度，FIFO 深度当前设为 32。
- Digital Capture 结果可旁路仲裁器，直接写入 USB EP3 FIFO，依赖 `dc_fifo_afull` 反馈。
- I2C 从机 handler 已连入指令总线，但上传路径在 `rtl/cdc.v` 中仍被注释，后续需要补充适配器。

## 7. 仿真与验证环境
- `tb/` 提供单元与集成 testbench，通用任务集中在 `tb/utils.sv`。
- 每个 bench 在 `sim/<bench_name>/` 拥有独立 ModelSim 工程、`run_sim.do`、引导脚本与日志。
- 重点环境：
  | Testbench | 覆盖内容 | 位置 |
  |-----------|----------|------|
  | `upload_full_integration_tb.v` | USB 指令→上传→仲裁全链路 | `tb/upload_full_integration_tb.v`, `sim/upload_full_integration_tb/` |
  | `cdc_dc_tb.v` | CDC 主控 + Digital Capture 高频上传 | `tb/cdc_dc_tb.v`, `sim/cdc_dc_tb/` |
  | `dsm_multichannel_tb.sv` | 多通道 DSM 指令与测量 | `tb/dsm_multichannel_tb.sv` |
  | `i2c_slave_tb.sv` | I2C 从机状态机 | `tb/i2c_slave_tb.sv`, `sim/i2c_slave_tb/` |
  | `dds_tb.sv` / `dac_tb.sv` | DDS 输出、DAC 装载流程 | `tb/dds_tb.sv`, `tb/dac_tb.sv` |
- 运行方式：`vsim -c -do sim/<bench>/run_sim.do`，脚本会自动编译 Gowin 库并执行 `cmd_*.do`。

## 8. 上位机软件工具
- **命令生成**：`pwm_command_generator.py`, `dac_command_generator.py`, `custom_waveform_tool.py` 按硬件约束计算并输出十六进制帧。
- **调试与监控**：`dc_command_tool.py`, `dc_realtime_viewer.py`, `diagnose_dc.py` 聚焦数字捕获数据；`i2c_command_tool.py`, `spi_loopback_test.py`, `uart_command.py` 覆盖协议调试。
- **自动化脚本**：`monitor.ps1`、部分 Python 工具提供批量操作与波形注入。
- 所有脚本默认使用 60 MHz 系统时钟参数，修改硬件设计时需同步更新。

## 9. 构建、约束与部署
- 打开 `fpga_project.gprj` 可在 Gowin FPGA Designer 中完成综合、布局布线与比特流生成；IDE 将在 `impl/` 子目录生成临时产物。
- 命令行构建：在仓库根目录执行 `gowinsh -batch fpga_project.gprj`。
- 约束与时序：`constraints/pin_cons.cst`（引脚、电压银行设置）、`constraints/timing.sdc`（时序约束）。
- 运行前确保 USB CDC 描述符与端点配置与上位机工具一致，必要时更新 `rtl/usb/usb_descriptor.v`。

## 10. 文档与参考资料
- `doc/USB-CDC通信协议.md`：指令帧、端点、命令号定义。
- `doc/自定义波形上传说明.md`：自定义波形报文格式与软件操作。
- `doc/引脚对照表-自制板子.xlsx`：板级连接关系。
- `sim/COMPARISON_OVERVIEW.md`、`sim/INTEGRATION_SUMMARY.md`：上传管线各版本对比与调试记录。
- 根目录 `README.md`：目录约定与开发提示。

## 11. 当前状态与后续建议
- `rtl/cdc.v` 仍使用 `upload_adapter_0.v` / `upload_packer_0.v` 版本，若要引入新版（支持更深 FIFO 与动态优先级），需同步更新实例与仿真脚本。
- I2C 从机上传链路暂未接入仲裁器，待完成 `upload_adapter` 对接以及命令测试。
- Digital Capture 直通 USB EP3，必须持续监控 `dc_fifo_afull` 信号；建议在上位机侧处理背压以避免丢采样。
- `acm9238_ddr3_rgmii` 与 USB 命令路径尚未打通，若计划通过 USB 配置/读取高速链路，需设计额外的控制寄存器与上传协议。
- 建议在 `gowinsh -batch` 前运行 `vlog -sv` 对修改过的文件做语法检查，并在相关 `sim/` 工程中补充回归脚本。

---

**文档版本**：v1.0  
**整理日期**：2025-03-01  
**整理人**：Codex（自动生成，依据仓库当前内容）
