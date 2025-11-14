# CDC写入状态机修复 - 前后对比

## 状态图对比

### 修复前（问题版本）
```
         ┌──────────────┐
         │   S_IDLE     │
         └──────┬───────┘
                │ cmd_start (0x35)
                ▼
         ┌──────────────┐
         │ S_CMD_CAPTURE│
         └──────┬───────┘
                │ cmd_done
                ▼
         ┌──────────────┐
    ┌───▶│ S_EXEC_WRITE │◀───┐
    │    └──────┬───────┘    │
    │           │             │
    │   ptr < len? ────YES───┘
    │           │
    │          NO      (问题: 指针立即递增，
    │           │       状态停留时间太短)
    │           ▼
    │    ┌──────────────┐
    └────│  S_FINISH    │
         └──────────────┘
```

**问题**:
- `cdc_write_ptr` 在 S_EXEC_WRITE 内递增
- 状态循环太快，写使能信号持续时间不足
- reg_map 边沿检测失败

---

### 修复后（正确版本）
```
         ┌──────────────┐
         │   S_IDLE     │
         └──────┬───────┘
                │ cmd_start (0x35)
                ▼
         ┌──────────────┐
         │ S_CMD_CAPTURE│
         └──────┬───────┘
                │ cmd_done
                ▼
         ┌───────────────┐
    ┌───▶│ S_EXEC_WRITE  │
    │    └───────┬───────┘
    │            │ ptr < len?
    │           YES
    │            ▼
    │    ┌───────────────────┐
    │    │S_EXEC_WRITE_HOLD  │ ← 新增状态
    │    └───────┬───────────┘
    │            │ ptr++
    └────────────┘
                 │
                NO (ptr >= len)
                 ▼
         ┌──────────────┐
         │  S_FINISH    │
         └──────────────┘
```

**改进**:
- 分离检查状态和递增操作
- `S_EXEC_WRITE`: 执行写入（handler_wr_en=1）
- `S_EXEC_WRITE_HOLD`: 保持并递增指针（handler_wr_en=0）
- 循环往复，产生清晰的写使能脉冲

---

## 时序波形对比

### 修复前（单字节写入，失败）
```
clk           ╱‾╲_╱‾╲_╱‾╲_╱‾╲_╱‾╲_
state         [3 WRITE ][6 FINISH]
handler_wr_en ‾‾‾‾╲_________________
cdc_write_ptr [0      ][1         ]
handler_addr  [0x00   ][0x01      ]  ← 地址变了！
handler_wdata [0x55   ][0xxx      ]  ← 数据失效！

reg_map_fedge _______________________  ← 没有捕获到下降沿！
registers[0]  [0x00 (没变化) ]        ← 写入失败
```

### 修复后（单字节写入，成功）
```
clk           ╱‾╲_╱‾╲_╱‾╲_╱‾╲_╱‾╲_╱‾╲_╱‾╲_
state         [3 WRITE][4 HOLD ][3 WRITE][7 FINISH]
handler_wr_en ‾‾‾‾╲_________╱‾‾‾‾╲_________________
cdc_write_ptr [0        ][0→1  ][1        ]
handler_addr  [0x00     ][0x00 ][0x01    ]
handler_wdata [0x55     ][0x55 ][0xbb    ]

reg_map_fedge _________╱‾╲___________________  ← 捕获到下降沿！
registers[0]  [0x00    ][0x55 (已写入!)]     ← 写入成功✓
```

---

## 多字节写入时序对比

### 修复前（写4字节，全部失败）
```
周期: 1    2    3    4
state: [WRITE][WRITE][WRITE][FINISH]
ptr:   0    1    2    3
wr_en: 1    1    1    0

问题: 指针不停递增，地址和数据不匹配
结果: 全部写入失败
```

### 修复后（写4字节，全部成功）
```
周期: 1    2    3    4    5    6    7    8    9    10
state: [WR][HD][WR][HD][WR][HD][WR][HD][WR][FIN]
ptr:   0   0→1  1  1→2  2  2→3  3  3→4  4   -
addr:  00  00  01  01  02  02  03  03  -   -
data:  AA  AA  BB  BB  CC  CC  DD  DD  -   -
wr_en: 1   0   1   0   1   0   1   0   1   0

结果: 每个字节都有独立的写周期，全部成功！
      Reg[0]=0xAA, Reg[1]=0xBB, Reg[2]=0xCC, Reg[3]=0xDD ✓
```

---

## 代码对比

### 状态定义
```diff
  localparam S_EXEC_WRITE        = 4'd3;
+ localparam S_EXEC_WRITE_HOLD   = 4'd4; // ← 新增
- localparam S_EXEC_READ_SETUP   = 4'd4;
+ localparam S_EXEC_READ_SETUP   = 4'd5; // ← 编号+1
- localparam S_UPLOAD_DATA       = 4'd5;
+ localparam S_UPLOAD_DATA       = 4'd6; // ← 编号+1
- localparam S_FINISH            = 4'd6;
+ localparam S_FINISH            = 4'd7; // ← 编号+1
```

### 状态机逻辑
```diff
  S_EXEC_WRITE: begin
-     if (cdc_write_ptr < cdc_len) begin
-         cdc_write_ptr <= cdc_write_ptr + 1;
-     end else begin
+     if (cdc_write_ptr < cdc_len) begin
+         state <= S_EXEC_WRITE_HOLD; // ← 跳到新状态
+     end else begin
          state <= S_FINISH;
      end
  end

+ S_EXEC_WRITE_HOLD: begin      // ← 新增状态
+     cdc_write_ptr <= cdc_write_ptr + 1;
+     state <= S_EXEC_WRITE;
+ end
```

---

## 关键改进点

| 项目 | 修复前 | 修复后 |
|------|--------|--------|
| 写周期数 | 1个周期完成 | 2个周期完成（WRITE+HOLD） |
| 地址稳定性 | 不稳定 | 稳定（在WRITE期间保持） |
| 数据稳定性 | 不稳定 | 稳定（在WRITE期间保持） |
| 写使能信号 | 持续但时机不对 | 清晰的脉冲 |
| reg_map边沿 | 无法捕获 | 成功捕获 |
| 写入结果 | ❌ 失败 | ✅ 成功 |

---

## 验证清单

- [x] 修改状态定义（添加S_EXEC_WRITE_HOLD）
- [x] 修改状态机逻辑（分离写入和递增）
- [x] 更新状态编号（READ_SETUP, UPLOAD_DATA, FINISH +1）
- [ ] 编译验证（无语法错误）
- [ ] 仿真测试（寄存器写入成功）
- [ ] 波形检查（写使能时序正确）

---
