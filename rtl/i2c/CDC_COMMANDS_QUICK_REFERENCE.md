# I2C Slave CDC Commands - Quick Reference Guide

## 命令总览

| 命令码 | 命令名称 | 功能描述 |
|--------|---------|---------|
| **0x34** | SET_I2C_ADDR | 设置I2C从机地址 |
| **0x35** | WRITE_REGS | CDC预装寄存器数据 |
| **0x36** | READ_REGS | CDC读取寄存器值 |

---

## 0x34 - 设置I2C从机地址

### 指令格式
```
cmd_type = 0x34
captured_data[0] = 新的I2C从机地址(7位)
```

### 使用示例
```systemverilog
// 设置I2C从机地址为0x50
cmd_type = 8'h34;
cmd_start = 1'b1;
cmd_data_valid = 1'b1;

cmd_data_index = 0;  cmd_data = 8'h50;  // 新地址0x50

cmd_done = 1'b1;
```

### 测试用例
```
示例1：设置地址为0x24（默认）
  指令：0x34, 0x24

示例2：设置地址为0x50
  指令：0x34, 0x50

示例3：设置地址为0x3C（常用OLED地址）
  指令：0x34, 0x3C
```

---

## 0x35 - CDC预装寄存器数据

### 指令格式
```
cmd_type = 0x35
captured_data[0] = 起始寄存器地址 (0-3)
captured_data[1] = 写入长度 (1-4)
captured_data[2] = 数据字节0
captured_data[3] = 数据字节1 (可选)
captured_data[4] = 数据字节2 (可选)
captured_data[5] = 数据字节3 (可选)
```

### 使用示例

#### 示例1：预装单个寄存器
```systemverilog
// 预装寄存器0为0x55
cmd_type = 8'h35;
cmd_start = 1'b1;
cmd_data_valid = 1'b1;

cmd_data_index = 0;  cmd_data = 8'h00;  // 地址0
cmd_data_index = 1;  cmd_data = 8'h01;  // 长度1
cmd_data_index = 2;  cmd_data = 8'h55;  // 数据0x55

cmd_done = 1'b1;
```

#### 示例2：预装两个连续寄存器
```systemverilog
// 预装寄存器1和2为0x12, 0x34
cmd_type = 8'h35;
cmd_start = 1'b1;
cmd_data_valid = 1'b1;

cmd_data_index = 0;  cmd_data = 8'h01;  // 起始地址1
cmd_data_index = 1;  cmd_data = 8'h02;  // 长度2
cmd_data_index = 2;  cmd_data = 8'h12;  // 寄存器1 = 0x12
cmd_data_index = 3;  cmd_data = 8'h34;  // 寄存器2 = 0x34

cmd_done = 1'b1;
```

#### 示例3：预装所有4个寄存器
```systemverilog
// 预装所有寄存器为0xAA, 0xBB, 0xCC, 0xDD
cmd_type = 8'h35;
cmd_start = 1'b1;
cmd_data_valid = 1'b1;

cmd_data_index = 0;  cmd_data = 8'h00;  // 起始地址0
cmd_data_index = 1;  cmd_data = 8'h04;  // 长度4
cmd_data_index = 2;  cmd_data = 8'hAA;  // 寄存器0 = 0xAA
cmd_data_index = 3;  cmd_data = 8'hBB;  // 寄存器1 = 0xBB
cmd_data_index = 4;  cmd_data = 8'hCC;  // 寄存器2 = 0xCC
cmd_data_index = 5;  cmd_data = 8'hDD;  // 寄存器3 = 0xDD

cmd_done = 1'b1;
```

### 测试用例表
```
用例1：写寄存器0 = 0x11
  指令：0x35, 0x00, 0x01, 0x11

用例2：写寄存器3 = 0xFF
  指令：0x35, 0x03, 0x01, 0xFF

用例3：写寄存器0-1 = 0xAA, 0xBB
  指令：0x35, 0x00, 0x02, 0xAA, 0xBB

用例4：写寄存器2-3 = 0x12, 0x34
  指令：0x35, 0x02, 0x02, 0x12, 0x34

用例5：写所有寄存器 = 0x11, 0x22, 0x33, 0x44
  指令：0x35, 0x00, 0x04, 0x11, 0x22, 0x33, 0x44
```

---

## 0x36 - CDC读取寄存器值

### 指令格式
```
cmd_type = 0x36
captured_data[0] = 起始寄存器地址 (0-3)
captured_data[1] = 读取长度 (1-4)

返回数据：
  upload_data[7:0] = 寄存器值（按顺序输出）
  upload_source = 0x36
  upload_valid = 1（数据有效时）
```

### 使用示例

#### 示例1：读取单个寄存器
```systemverilog
// 读取寄存器0
cmd_type = 8'h36;
cmd_start = 1'b1;
cmd_data_valid = 1'b1;

cmd_data_index = 0;  cmd_data = 8'h00;  // 地址0
cmd_data_index = 1;  cmd_data = 8'h01;  // 长度1

cmd_done = 1'b1;

// 监听返回数据
// upload_data = 寄存器0的值
// upload_source = 0x36
// upload_valid = 1
```

#### 示例2：读取两个连续寄存器
```systemverilog
// 读取寄存器1和2
cmd_type = 8'h36;
cmd_start = 1'b1;
cmd_data_valid = 1'b1;

cmd_data_index = 0;  cmd_data = 8'h01;  // 起始地址1
cmd_data_index = 1;  cmd_data = 8'h02;  // 长度2

cmd_done = 1'b1;

// 监听返回数据（按顺序）
// 周期1: upload_data = 寄存器1的值, upload_valid = 1
// 周期2: upload_data = 寄存器2的值, upload_valid = 1
```

#### 示例3：读取所有4个寄存器
```systemverilog
// 读取所有寄存器
cmd_type = 8'h36;
cmd_start = 1'b1;
cmd_data_valid = 1'b1;

cmd_data_index = 0;  cmd_data = 8'h00;  // 起始地址0
cmd_data_index = 1;  cmd_data = 8'h04;  // 长度4

cmd_done = 1'b1;

// 监听返回数据（按顺序）
// 周期1: upload_data = 寄存器0的值, upload_valid = 1
// 周期2: upload_data = 寄存器1的值, upload_valid = 1
// 周期3: upload_data = 寄存器2的值, upload_valid = 1
// 周期4: upload_data = 寄存器3的值, upload_valid = 1
```

### 测试用例表
```
用例1：读寄存器0
  指令：0x36, 0x00, 0x01
  返回：1个字节

用例2：读寄存器3
  指令：0x36, 0x03, 0x01
  返回：1个字节

用例3：读寄存器0-1
  指令：0x36, 0x00, 0x02
  返回：2个字节（按顺序）

用例4：读寄存器2-3
  指令：0x36, 0x02, 0x02
  返回：2个字节（按顺序）

用例5：读所有寄存器
  指令：0x36, 0x00, 0x04
  返回：4个字节（按顺序）
```

---

## 完整测试序列

### 测试场景1：预装并验证单个寄存器
```systemverilog
// 步骤1：预装寄存器0为0xA5
cmd_type = 8'h35;
cmd_data[0] = 8'h00;  cmd_data[1] = 8'h01;  cmd_data[2] = 8'hA5;

// 步骤2：读取寄存器0验证
cmd_type = 8'h36;
cmd_data[0] = 8'h00;  cmd_data[1] = 8'h01;
// 期望返回：upload_data = 0xA5
```

### 测试场景2：预装并验证所有寄存器
```systemverilog
// 步骤1：预装所有寄存器
cmd_type = 8'h35;
cmd_data[0] = 8'h00;  // 地址0
cmd_data[1] = 8'h04;  // 长度4
cmd_data[2] = 8'h11;  // reg0 = 0x11
cmd_data[3] = 8'h22;  // reg1 = 0x22
cmd_data[4] = 8'h33;  // reg2 = 0x33
cmd_data[5] = 8'h44;  // reg3 = 0x44

// 步骤2：读取所有寄存器验证
cmd_type = 8'h36;
cmd_data[0] = 8'h00;  // 地址0
cmd_data[1] = 8'h04;  // 长度4
// 期望返回：0x11, 0x22, 0x33, 0x44
```

### 测试场景3：部分修改后读取
```systemverilog
// 步骤1：初始化所有寄存器为0x00
cmd_type = 8'h35;
cmd_data[0] = 8'h00;  cmd_data[1] = 8'h04;
cmd_data[2] = 8'h00;  cmd_data[3] = 8'h00;
cmd_data[4] = 8'h00;  cmd_data[5] = 8'h00;

// 步骤2：只修改寄存器2为0xFF
cmd_type = 8'h35;
cmd_data[0] = 8'h02;  cmd_data[1] = 8'h01;  cmd_data[2] = 8'hFF;

// 步骤3：读取所有寄存器验证
cmd_type = 8'h36;
cmd_data[0] = 8'h00;  cmd_data[1] = 8'h04;
// 期望返回：0x00, 0x00, 0xFF, 0x00
```

### 测试场景4：动态修改I2C地址
```systemverilog
// 步骤1：设置I2C地址为0x50
cmd_type = 8'h34;
cmd_data[0] = 8'h50;

// 步骤2：预装寄存器（使用新地址）
cmd_type = 8'h35;
cmd_data[0] = 8'h00;  cmd_data[1] = 8'h01;  cmd_data[2] = 8'hAA;

// 步骤3：外部I2C主机使用地址0x50访问
// I2C事务：START, 0xA0(W), 0x00, RESTART, 0xA1(R), [0xAA], STOP
```

---

## 时序图示例

### CDC写指令时序
```
         ___     ___     ___     ___     ___     ___
clk     |   |___|   |___|   |___|   |___|   |___|   |___
             ___________
cmd_start ___|           |___________________________
                     _____________________________
cmd_valid ___________|                             |___
                     ____ ____ ____ ____ ____ ____
cmd_data  XXXXXXXXXX|_0__|_1__|_2__|_3__|_4__|_5__|XXX
                     ____ ____ ____ ____ ____ ____
cmd_index XXXXXXXXXX|_0__|_1__|_2__|_3__|_4__|_5__|XXX
                                                 ___
cmd_done  ______________________________________|   |___
```

### CDC读指令时序
```
         ___     ___     ___     ___     ___     ___
clk     |   |___|   |___|   |___|   |___|   |___|   |___
             ___________
cmd_start ___|           |___________________________
                     ___________
cmd_valid ___________|           |___________________
                     ____ ____
cmd_data  XXXXXXXXXX|_0__|_1__|XXXXXXXXXXXXXXXXXXXXXXX
                     ____ ____
cmd_index XXXXXXXXXX|_0__|_1__|XXXXXXXXXXXXXXXXXXXXXXX
                           ___
cmd_done  _________________|   |_______________________
                                     ___ ___ ___ ___
upload_req __________________________|               |__
                                     ___ ___ ___ ___
upload_valid ________________________|   |   |   |   |__
                                     ___ ___ ___ ___
upload_data XXXXXXXXXXXXXXXXXXXXXXXX|D0_|D1_|D2_|D3_|XXX
```

---

## 寄存器映射

| 地址 | 名称 | 复位值 | 读写属性 | 描述 |
|------|------|--------|---------|------|
| 0x00 | REG0 | 0x00 | R/W | 通用寄存器0 |
| 0x01 | REG1 | 0x00 | R/W | 通用寄存器1 |
| 0x02 | REG2 | 0x00 | R/W | 通用寄存器2 |
| 0x03 | REG3 | 0x00 | R/W | 通用寄存器3 |

---

## 常见错误与解决方案

### 错误1：地址越界
```
问题：起始地址 + 长度 > 3
解决：确保 addr + len <= 4
示例：addr=2, len=3 会越界（2+3=5>4）
      改为：addr=1, len=3 或 addr=2, len=2
```

### 错误2：命令未完成就发送下一条
```
问题：cmd_ready = 0 时发送新命令
解决：等待 cmd_ready = 1 后再发送
代码：wait(cmd_ready == 1'b1);
      // 然后发送新命令
```

### 错误3：读取数据未等待upload_ready
```
问题：upload_ready = 0 但继续读取
解决：握手协议 - 同时检查 upload_valid 和 upload_ready
代码：if (upload_valid && upload_ready) begin
        data = upload_data;
      end
```

### 错误4：长度为0
```
问题：captured_data[1] = 0
解决：长度必须 >= 1
最小值：0x01（单字节操作）
```

---

## 接口信号说明

### CDC命令输入接口
```systemverilog
input  logic [7:0]  cmd_type;        // 命令类型
input  logic [15:0] cmd_length;      // 命令长度（预留）
input  logic [7:0]  cmd_data;        // 命令数据
input  logic [15:0] cmd_data_index;  // 数据索引
input  logic        cmd_start;       // 命令开始标志
input  logic        cmd_data_valid;  // 数据有效标志
input  logic        cmd_done;        // 命令完成标志
output logic        cmd_ready;       // 准备接收新命令
```

### CDC上传输出接口
```systemverilog
output logic        upload_active;   // 上传活跃标志
output logic        upload_req;      // 上传请求
output logic [7:0]  upload_data;     // 上传数据
output logic [7:0]  upload_source;   // 上传源ID（0x36）
output logic        upload_valid;    // 上传数据有效
input  logic        upload_ready;    // 上传准备好（握手）
```

---

## 注意事项

1. **命令执行顺序**：必须等待 `cmd_ready = 1` 才能发送下一条命令
2. **数据索引**：`cmd_data_index` 从0开始，必须连续递增
3. **握手协议**：读取命令的数据上传使用 `upload_valid` & `upload_ready` 握手
4. **地址范围**：寄存器地址仅支持 0-3（4个8位寄存器）
5. **复位默认**：所有寄存器复位后默认值为 0x00
6. **I2C地址**：默认从机地址为 0x24，可通过0x34命令修改
7. **优先级**：CDC预装（0x35）和I2C主机写入都可以修改寄存器，后写入的生效

---

## 版本信息

- **文档版本**: v1.0
- **创建日期**: 2025-11-03
- **命令版本**: 0x34/0x35/0x36
- **模块**: i2c_slave_handler.sv
- **作者**: Claude Code

---
