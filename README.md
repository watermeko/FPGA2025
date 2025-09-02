# FPGA2025
File Structure:
```
FPGA2025
│
├── 📁constraints // 约束文件
├── 📁rtl // 可综合代码
├── 📁tb // 仿真文件
├── 📁sim // modelsim 仿真工程
├── 📄README.md
├── 📄fpga_project.gprj // 高云工程
│
```
注意：
1. 一个模块对应一个仿真工程，测试新模块请新建工程在sim文件夹下。
2. 在自己的分支上根据自己的需要修改.gitignore，不要提交一堆没用的东西上来
3. tb、rtl目录下均可以新建文件夹来组织源代码
