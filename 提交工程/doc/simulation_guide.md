# RISC-V OoO CPU 仿真测试指南

## 环境要求

- Icarus Verilog (`iverilog.exe`, `vvp.exe`)
- GTKWave (波形查看)

Windows安装：从 [Icarus Verilog官网](http://bleyer.org/icarus/) 下载安装包，确保添加到PATH。

---

## 波形测试命令

### ALU (12种操作, ~15周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_alu.vvp rtl/common/cpu_defines.vh rtl/core/alu_unit.v tb/wave/tb_alu_wave.v
vvp sim/wave_alu.vvp
gtkwave sim/waves/alu_wave.vcd tb/wave/alu.gtkw
```

### 乘法器 (4种操作, ~20周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_mul.vvp rtl/common/cpu_defines.vh rtl/core/mul_unit.v tb/wave/tb_mul_wave.v
vvp sim/wave_mul.vvp
gtkwave sim/waves/mul_wave.vcd tb/wave/mul.gtkw
```

### 除法器 (4种操作+除零, ~150周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_div.vvp rtl/common/cpu_defines.vh rtl/core/div_unit.v tb/wave/tb_div_wave.v
vvp sim/wave_div.vvp
gtkwave sim/waves/div_wave.vcd tb/wave/div.gtkw
```

### 分支单元 (6种分支+JAL/JALR, ~15周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_branch.vvp rtl/common/cpu_defines.vh rtl/core/branch_unit.v tb/wave/tb_branch_wave.v
vvp sim/wave_branch.vvp
gtkwave sim/waves/branch_wave.vcd tb/wave/branch.gtkw
```
时间段	op_i	src1	    src2	    操作	     taken_o	结果
~50ns	0	    5	        5	        BEQ (5==5)	1	       ✓ 跳转
~80ns	0	    5	        6	        BEQ (5==6)	0	       ✓ 不跳转
~110ns	1	    5	        6	        BNE (5!=6)	1	       ✓ 跳转
~140ns	4	    FFFFFFFF	1	        BLT (-1<1)	1	       ✓ 跳转
~170ns	5	    5	        3	        BGE (5>=3)	1	       ✓ 跳转
~200ns	6	    1	        FFFFFFFF	BLTU	    1	       ✓ 跳转
~230ns	7	    FFFFFFFF	1	        BGEU	    1	       ✓ 跳转
~260ns	8	    -	        -	        JAL	        1	       ✓ 跳转
~290ns	9	    2000	    -	        JALR	    1	       ✓ 跳转
### 地址生成单元 (对齐检测, ~15周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_agu.vvp rtl/common/cpu_defines.vh rtl/core/agu_unit.v tb/wave/tb_agu_wave.v
vvp sim/wave_agu.vvp
gtkwave sim/waves/agu_wave.vcd tb/wave/agu.gtkw
```
时间	base_i	offset_i	size_i	  addr_o	misaligned_o	说明
~50ns	0x1000	0	        2(Word)	  0x1000	0	            字对齐 ✓
~80ns	0x1001	0	        2(Word)	  0x1001	1	            字未对齐 ✓
~110ns	0x1002	0	        1(Half)	  0x1002	0	            半字对齐 ✓
~140ns	0x1001	0	        1(Half)	  0x1001	1	            半字未对齐 ✓
~170ns	0x1001	0	        0(Byte)	  0x1001	0	            字节访问(无对齐要求) ✓
~200ns	0x1000	0x64	    2(Word)	  0x1064	0	            地址计算 ✓
~230ns	0x2000	4	        2(Word)	  0x2004	0	            Store透传 ✓

### 译码器 (12种指令类型, ~20周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_decoder.vvp rtl/common/cpu_defines.vh rtl/core/decoder.v rtl/core/imm_gen.v tb/wave/tb_decoder_wave.v
vvp sim/wave_decoder.vvp
gtkwave sim/waves/decoder_wave.vcd tb/wave/decoder.gtkw
```
时间	instr_i	             opcode	     funct3	rd	rs1	rs2	imm_o	     指令类型
~20ns	0x003100B3	         0x33	     0	    1	2	3	-	         ADD x1,x2,x3 (R-type)
~30ns	0x06410093	         0x13	     0	    1	2	-	0x64	     ADDI x1,x2,100 (I-type)
~40ns	0x00012083	         0x03	     2	    1	2	-	0	         LW x1,0(x2) (Load)
~50ns	0x00112023	         0x23	     2	    -	2	1	0	         SW x1,0(x2) (Store)
~60ns	0x00208463	         0x63	     0	    -	1	2	8	         BEQ x1,x2,8 (Branch)
~70ns	0x064008EF	         0x6F	     -	    17	-	-	0x64	     JAL x17,100 (Jump)
~80ns	0x000008E7	         0x67	     0	    17	0	-	0	         JALR x17,x0,0
~90ns	0x12345087	         0x37	     -	    1	-	-	0x12345000	 LUI x1,0x12345 (U-type)
~100ns	0x12345097	         0x17	     -	    1	-	-	0x12345000	 AUIPC x1,0x12345
~110ns	0x023100B3	         0x33	     0	    1	2	3	-	         MUL x1,x2,x3 (M-ext)
~120ns	0x023140B3	         0x33	     4	    1	2	3	-	         DIV x1,x2,x3
~130ns	0xFFFFFFFF	         0x7F	     7	    31	31	31	-	         非法指令
### 分支预测 (预测/更新/恢复, ~25周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_bpu.vvp rtl/common/cpu_defines.vh rtl/bpu/bimodal_predictor.v rtl/bpu/tage_table.v rtl/bpu/tage_predictor.v rtl/bpu/btb.v rtl/bpu/ras.v rtl/bpu/loop_predictor.v rtl/bpu/bpu.v tb/wave/tb_bpu_wave.v
vvp sim/wave_bpu.vvp
gtkwave sim/waves/bpu_wave.vcd tb/wave/bpu.gtkw
```
信号	         值	            说明
pred_req_i	     1→0	        预测请求
pred_pc_i	     0x1000	        查询 PC 地址
pred_valid_o	 0→1	        预测结果有效
pred_taken_o	 1	            预测跳转
pred_target_o	 0x100C→0x1004	预测目标地址

信号	                值	          说明
update_valid_i	        1	          更新请求有效
update_taken_i	        1	          实际跳转
update_mispredict_i 	0	          无预测错误
update_pc_i          	0x1000	      更新的 PC
update_target_i	        0x100C	实际目标地址
### 寄存器别名表 (重命名/检查点, ~25周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_rat.vvp rtl/common/cpu_defines.vh rtl/core/rat.v tb/wave/tb_rat_wave.v
vvp sim/wave_rat.vvp
gtkwave sim/waves/rat_wave.vcd tb/wave/rat.gtkw
```
信号	        值	        说明
rs1_arch_i	    1	       查询架构寄存器 x1
rs1_phys_o	    0x20	   映射到物理寄存器 P32
rs1_ready_o	    1	       操作数就绪
rs2_arch_i	    0	       查询架构寄存器 x0
rs2_phys_o	    0	       x0 始终映射到 P0
rs2_ready_o	    1	       操作数就绪

信号	        值	        说明
rename_valid_i	1	        重命名请求有效
rd_arch_i	    1	        目标架构寄存器 x1
rd_phys_new_i	0x20→0x21	分配新物理寄存器 P33
rd_phys_old_o	0x20→0x21	返回旧映射 P32→P33

信号	        值	        说明
recover_i	    1	        触发恢复
recover_id_i	0	        恢复到检查点 0
rs1_phys_o	    0x21→0x20	恢复后映射回 P32

信号	                 值	           说明
checkpoint_create_i      1	           创建检查点
checkpoint_id_i	         0	           检查点 ID=0


信号	               值	     说明
cdb_valid_i	           1	     CDB 广播有效
cdb_preg_i	           0x20	     物理寄存器 P32 完成


### 重排序缓冲 (分配/完成/提交, ~30周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_rob.vvp rtl/common/cpu_defines.vh rtl/core/rob.v tb/wave/tb_rob_wave.v
vvp sim/wave_rob.vvp
gtkwave sim/waves/rob_wave.vcd tb/wave/rob.gtkw
```
时间	alloc_idx_o	    rd_arch	      rd_phys	  count_o	说明
~35ns	0→1	            1	          0x20	      1	        分配 entry 0
~45ns	1→2	            2	          0x21	      2	        分配 entry 1
~55ns	2→3	            3	          0x22	      3	        分配 entry 2

时间	complete_idx	complete_result 	说明
~75ns	0	            0xDEAD          	标记 entry 0 完成
~95ns	1	            0xBEEF          	标记 entry 1 完成
~105ns	2	            0xCAFE          	标记 entry 2 完成


时间	commit_idx_o	commit_result_o	        count_o	       说明
~80ns	0	            0xDEAD              	3→2	提交       entry 0
~100ns	1              	0xBEEF                 	2→1	提交       entry 1
~110ns	2              	0xCAFE               	1→0	提交       entry 2
### 保留站 (分配/唤醒/发射, ~25周期)
```cmd![1768033735802](image/simulation_guide/1768033735802.png)
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_rs.vvp rtl/common/cpu_defines.vh rtl/core/reservation_station.v tb/wave/tb_rs_wave.v
vvp sim/wave_rs.vvp
gtkwave sim/waves/rs_wave.vcd tb/wave/rs.gtkw
```
时间	dispatch_valid	src1_preg	src1_data	src1_ready	src2_preg	src2_data	src2_ready	dst_preg	empty_o	说明
~20ns	0→1         	00→01   	0→0x100  	0→1     	00→02    	0→0x200  	0→1     	00→20    	1   	分配指令1，双操作数就绪
~30ns	1→0          	01      	0x100   	1       	02      	0x200    	1       	20      	1→0	    指令1进入RS

时间	issue_valid_o	issue_src1_data	issue_src2_data	issue_dst_preg	issue_ready_i	empty_o	说明
~35ns	0→1         	0x00000100  	0x00000200   	20          	0           	0   	指令1就绪，等待发射
~45ns	1           	0x00000100  	0x00000200   	20          	0→1         	0      	执行单元就绪
~50ns	1→0          	-           	-           	-           	1→0          	0→1 	指令1发射完成，RS变空

时间	dispatch_valid	src1_preg	src1_data	src1_ready	src2_preg	src2_data	src2_ready	dst_preg	说明
~55ns	0→1         	01→21   	0x100→0 	1→0     	02→00    	0x200→0x50	1       	20→22   	分配指令2，src1未就绪
~65ns	1→0           	21         	0       	0         	00         	0x50     	1         	22       	指令2进入RS，等待P21

时间	cdb_valid_i	cdb_preg	cdb_data	issue_valid_o	issue_src1_data	说明
~70ns	0         	00         	0         	0           	0           	指令2阻塞，等待src1
~90ns	0→1       	00→21   	0→0xABCD	0           	0            	CDB广播P21结果
~100ns	1→0      	21      	0xABCD  	0→1         	0→0x0000ABCD	RS捕获数据，指令2就绪

时间	issue_valid_o	issue_src1_data   	issue_src2_data  	issue_dst_preg  	empty_o  	说明
~100ns	1           	0x0000ABCD       	0x00000050      	22              	0       	指令2就绪可发射






### 公共数据总线 (优先级仲裁, ~15周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_cdb.vvp rtl/common/cpu_defines.vh rtl/core/cdb.v tb/wave/tb_cdb_wave.v
vvp sim/wave_cdb.vvp
gtkwave sim/waves/cdb_wave.vcd tb/wave/cdb.gtkw
```

### Load/Store队列 (转发, ~30周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_lsq.vvp rtl/common/cpu_defines.vh rtl/mem/load_queue.v rtl/mem/store_queue.v rtl/mem/lsq.v tb/wave/tb_lsq_wave.v
vvp sim/wave_lsq.vvp
gtkwave sim/waves/lsq_wave.vcd tb/wave/lsq.gtkw
```
时间	事件    	关键信号变化                                                    	 说明
~20ns	复位释放	rst_n: 0→1                                                      	LSQ 初始化完成
~45ns	Store 分配	st_alloc_valid=1, st_alloc_idx=1                                	分配 Store 队列条目
~55ns	Store 地址	st_addr_valid=1, st_addr=0x00001000, st_data=0xDEADBEEF           	Store 地址和数据就绪
~65ns	Store 写出	dcache_wr_valid=1, dcache_wr_addr=0x00001000                      	向 DCache 发起写请求
~75ns	Load 分配	ld_alloc_valid=1, ld_alloc_idx=1                                	分配 Load 队列条目
~85ns	Load 地址	ld_addr_valid=1, ld_addr=0x00001000                             	Load 地址就绪（同地址）
~95ns	Load 读出	dcache_rd_valid=1, dcache_rd_addr=0x00001000                    	向 DCache 发起读请求
~105ns	Load 完成	ld_complete_valid=1, ld_complete_data=0xDEADBEEF                  	Load 获得 Store 转发数据

功能        	结果        	说明
Store 分配     	✓           	idx 正确分配
Load 分配   	✓           	idx 正确分配
地址匹配检测	 ✓            	检测到 Load/Store 同地址
Store 转发   	✓           	Load 获得 0xDEADBEEF
违例检测     	✓              	violation_o=0，无内存序违例
DCache 接口  	✓           	读写请求正确发出



### 流水线控制 (stall/flush, ~20周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_pipeline.vvp rtl/common/cpu_defines.vh rtl/core/pipeline_ctrl.v tb/wave/tb_pipeline_wave.v
vvp sim/wave_pipeline.vvp
gtkwave sim/waves/pipeline_wave.vcd tb/wave/pipeline.gtkw
```
时间        	触发事件        	 Stall信号       	 Flush信号        	  redirect_pc   	  说明
~35ns        	rob_full=1      	IF/ID/RN=1      	-               	-               	ROB 满，前端暂停
~55ns        	icache_miss=1    	IF=1             	-               	-               	ICache 缺失，取指暂停
~75ns         	branch_mispredict=1	-               	IF/ID/RN/IS/EX=1	0x3000           	分支预测错误，全流水线冲刷
~85ns       	exception=1      	-               	IF/ID/RN/IS/EX=1	0x0000+           	异常触发，全流水线冲刷
~105ns        	mret=1           	-                	IF/ID/RN/IS/EX=1	0x0000+          	异常返回，重定向到 mepc

功能         	            结果
ROB满暂停               	✓
Cache Miss 暂停         	✓
分支误预测恢复          	 ✓
异常处理                  	✓
MRET 返回               	✓







### 异常处理 (各种异常类型, ~20周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_exception.vvp rtl/common/cpu_defines.vh rtl/core/exception_unit.v tb/wave/tb_exception_wave.v
vvp sim/wave_exception.vvp
gtkwave sim/waves/exception_wave.vcd tb/wave/exception.gtkw
```
时间	触发源               exc_code    	 exc_pc 	 redirect_pc	 说明
~25ns	instr_misalign=1	0→2         	0x1000  	mtvec(0x100)	指令地址未对齐
~35ns	-                 	2→0         	-        	-           	异常处理完成
~45ns	ecall=1         	0→B(11)       	0x1000  	mtvec         	环境调用
~55ns	load_misalign=1 	B→4         	0x1000  	mtvec       	Load 地址未对齐
~65ns	illegal_instr=1 	4→2         	0x1000  	mtvec       	非法指令
~75ns	mret=1          	-           	-        	mepc(0x2000)	异常返回




### CSR单元 (读写/异常, ~25周期)
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/wave_csr.vvp rtl/common/cpu_defines.vh rtl/core/csr_unit.v tb/wave/tb_csr_wave.v
vvp sim/wave_csr.vvp
gtkwave sim/waves/csr_wave.vcd tb/wave/csr.gtkw
```
时间	csr_addr	csr_op  	csr_wdata	csr_rdata	事件                    	结果
~35ns	0x305   	1(CSRRW)	0x100    	0x100   	写 mtvec                	mtvec_o=0x100 ✓
~55ns	0x301    	2(CSRRS)	0         	0x40044100	读 misa                 	RV32IM ✓
~75ns	-       	-         	-         	-        	exception=1, code=2     	mepc=0x1000 ✓
~95ns	0x342    	2(CSRRS)	0         	0x00000002	读 mcause               	code=2 ✓
~115ns	-        	-        	-       	-        	mret=1                  	异常返回 ✓
~135ns	0xFFF   	1          	0        	0        	非法 CSR                 	illegal=1 ✓
---

## CPI性能测试

```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/cpi_benchmark.vvp rtl/common/cpu_defines.vh tb/perf/tb_cpi_benchmark.v
vvp sim/cpi_benchmark.vvp
gtkwave sim/waves/cpi_benchmark.vcd tb/perf/cpi_benchmark.gtkw
```

测试场景：
1. 数据前推对比 - 有/无forwarding
2. 动态调度对比 - OoO vs In-Order
3. Cache性能对比 - 0%/20%/50% miss rate
4. 分支预测对比 - 95%/50%准确率
5. LSQ转发对比 - 有/无store-to-load forwarding
6. 综合负载对比 - 基线 vs 全优化

---

## 单元测试命令

### ALU完整测试
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_alu.vvp rtl/common/cpu_defines.vh rtl/core/alu_unit.v tb/unit/tb_alu_unit.v
vvp sim/test_alu.vvp
```

### 乘法器完整测试
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_mul.vvp rtl/common/cpu_defines.vh rtl/core/mul_unit.v tb/unit/tb_mul_unit.v
vvp sim/test_mul.vvp
```
测试	src1	        src2	    op	  result	      运算类型	    验证
1	    00000007	    00000006	0	  0000002A	      MUL	       7×6=42(0x2A) ✓
2	    FFFFFFFF(-1)	00000003	1	  0000+FFFFFFFF	  MULH	       高32位有符号
3	    FFFFFFFF	    FFFFFFFF	2	  -	              MULHSU	   有符号×无符号
4	    00010000	    00010000	3	  -	              MULHU	       无符号高位


### 除法器完整测试
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_div.vvp rtl/common/cpu_defines.vh rtl/core/div_unit.v tb/unit/tb_div_unit.v
vvp sim/test_div.vvp
```
测试	被除数(src1)	 除数(src2)	     结果(result)	  运算	   验证
1	    00000014 (20)	00000003 (3)	00000006 (6)	DIV	     20÷3=6 ✓

### 译码器完整测试
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_decoder.vvp rtl/common/cpu_defines.vh rtl/core/decoder.v rtl/core/imm_gen.v tb/unit/tb_decoder.v
vvp sim/test_decoder.vvp
```

### 分支单元完整测试
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_branch.vvp rtl/common/cpu_defines.vh rtl/core/branch_unit.v tb/unit/tb_branch_unit.v
vvp sim/test_branch.vvp
```

### BPU完整测试
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_bpu.vvp rtl/common/cpu_defines.vh rtl/bpu/bimodal_predictor.v rtl/bpu/tage_table.v rtl/bpu/tage_predictor.v rtl/bpu/btb.v rtl/bpu/ras.v rtl/bpu/loop_predictor.v rtl/bpu/bpu.v tb/unit/tb_bpu.v
vvp sim/test_bpu.vvp
```

### Cache完整测试
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_cache.vvp rtl/common/cpu_defines.vh rtl/cache/icache.v rtl/cache/dcache.v tb/unit/tb_cache.v
vvp sim/test_cache.vvp
```

### LSQ完整测试
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_lsq.vvp rtl/common/cpu_defines.vh rtl/mem/load_queue.v rtl/mem/store_queue.v rtl/mem/lsq.v tb/unit/tb_lsq.v
vvp sim/test_lsq.vvp
```

### 异常完整测试
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_exception.vvp rtl/common/cpu_defines.vh rtl/core/exception_unit.v tb/unit/tb_exception.v
vvp sim/test_exception.vvp
```

### 流水线控制测试
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_pipeline_ctrl.vvp rtl/common/cpu_defines.vh rtl/core/pipeline_ctrl.v tb/unit/tb_pipeline_ctrl.v
vvp sim/test_pipeline_ctrl.vvp
```

### OoO依赖测试
```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_ooo_deps.vvp rtl/common/cpu_defines.vh rtl/core/rat.v rtl/core/free_list.v rtl/core/rob.v tb/unit/tb_ooo_deps.v
vvp sim/test_ooo_deps.vvp
```

---

## 集成测试

```cmd
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_instr.vvp rtl/common/cpu_defines.vh rtl/core/*.v rtl/cache/*.v rtl/bpu/*.v rtl/mem/*.v rtl/bus/*.v tb/integration/tb_instr_tests.v
vvp sim/test_instr.vvp
```

---

## 常见问题

**Q: iverilog命令找不到？**
A: 确保Icarus Verilog安装目录已添加到系统PATH环境变量。

**Q: GTKWave打开后看不到信号？**
A: 使用预配置的.gtkw文件，信号已自动添加。

**Q: 编译报错找不到文件？**
A: 确保在项目根目录下执行命令，路径使用正斜杠(/)。
