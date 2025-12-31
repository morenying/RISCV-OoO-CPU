# RISC-V Out-of-Order CPU Makefile
# Supports Icarus Verilog and Verilator simulation

#==============================================================================
# Configuration
#==============================================================================

# Simulator selection: iverilog or verilator
SIM ?= iverilog

# Directories
RTL_DIR     := rtl
TB_DIR      := tb
SIM_DIR     := sim
WAVE_DIR    := $(SIM_DIR)/waves
LOG_DIR     := $(SIM_DIR)/logs

# RTL source files
RTL_COMMON  := $(wildcard $(RTL_DIR)/common/*.v)
RTL_CORE    := $(wildcard $(RTL_DIR)/core/*.v)
RTL_CACHE   := $(wildcard $(RTL_DIR)/cache/*.v)
RTL_BPU     := $(wildcard $(RTL_DIR)/bpu/*.v)
RTL_MEM     := $(wildcard $(RTL_DIR)/mem/*.v)
RTL_TOP     := $(RTL_DIR)/cpu_core_top.v

RTL_SRCS    := $(RTL_COMMON) $(RTL_CORE) $(RTL_CACHE) $(RTL_BPU) $(RTL_MEM) $(RTL_TOP)

# Include directories
INC_DIRS    := -I$(RTL_DIR)/common -I$(RTL_DIR)

# Testbench files
TB_COMMON   := $(wildcard $(TB_DIR)/common/*.v)

#==============================================================================
# Icarus Verilog Settings
#==============================================================================

IVERILOG    := iverilog
VVP         := vvp
IV_FLAGS    := -g2001 -Wall $(INC_DIRS)

#==============================================================================
# Verilator Settings
#==============================================================================

VERILATOR   := verilator
VL_FLAGS    := --cc --exe --build -Wall $(INC_DIRS)
VL_TRACE    := --trace

#==============================================================================
# Targets
#==============================================================================

.PHONY: all clean dirs help

# Default target
all: dirs

# Create directory structure
dirs:
	@mkdir -p $(RTL_DIR)/common
	@mkdir -p $(RTL_DIR)/core
	@mkdir -p $(RTL_DIR)/cache
	@mkdir -p $(RTL_DIR)/bpu
	@mkdir -p $(RTL_DIR)/mem
	@mkdir -p $(TB_DIR)/unit
	@mkdir -p $(TB_DIR)/integration
	@mkdir -p $(TB_DIR)/system
	@mkdir -p $(TB_DIR)/common
	@mkdir -p $(WAVE_DIR)
	@mkdir -p $(LOG_DIR)
	@echo "Directory structure created."

#==============================================================================
# Unit Tests
#==============================================================================

# ALU Unit Test
.PHONY: test_alu
test_alu: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_alu.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/alu_unit.v \
		$(TB_DIR)/unit/tb_alu_unit.v
	$(VVP) $(SIM_DIR)/test_alu.vvp | tee $(LOG_DIR)/test_alu.log
else
	@echo "Verilator test not implemented yet"
endif

# Multiplier Unit Test
.PHONY: test_mul
test_mul: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_mul.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/mul_unit.v \
		$(TB_DIR)/unit/tb_mul_unit.v
	$(VVP) $(SIM_DIR)/test_mul.vvp | tee $(LOG_DIR)/test_mul.log
endif

# Divider Unit Test
.PHONY: test_div
test_div: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_div.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/div_unit.v \
		$(TB_DIR)/unit/tb_div_unit.v
	$(VVP) $(SIM_DIR)/test_div.vvp | tee $(LOG_DIR)/test_div.log
endif

# Decoder Test
.PHONY: test_decoder
test_decoder: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_decoder.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/decoder.v \
		$(RTL_DIR)/core/imm_gen.v \
		$(TB_DIR)/unit/tb_decoder.v
	$(VVP) $(SIM_DIR)/test_decoder.vvp | tee $(LOG_DIR)/test_decoder.log
endif

# ROB Test
.PHONY: test_rob
test_rob: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_rob.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/rob.v \
		$(TB_DIR)/unit/tb_rob.v
	$(VVP) $(SIM_DIR)/test_rob.vvp | tee $(LOG_DIR)/test_rob.log
endif

# Reservation Station Test
.PHONY: test_rs
test_rs: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_rs.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/reservation_station.v \
		$(TB_DIR)/unit/tb_reservation_station.v
	$(VVP) $(SIM_DIR)/test_rs.vvp | tee $(LOG_DIR)/test_rs.log
endif

# RAT Test
.PHONY: test_rat
test_rat: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_rat.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/rat.v \
		$(RTL_DIR)/core/free_list.v \
		$(TB_DIR)/unit/tb_rat.v
	$(VVP) $(SIM_DIR)/test_rat.vvp | tee $(LOG_DIR)/test_rat.log
endif

#==============================================================================
# Cache Tests
#==============================================================================

.PHONY: test_icache test_dcache

test_icache: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_icache.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/cache/icache.v \
		$(TB_DIR)/unit/tb_icache.v
	$(VVP) $(SIM_DIR)/test_icache.vvp | tee $(LOG_DIR)/test_icache.log
endif

test_dcache: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_dcache.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/cache/dcache.v \
		$(TB_DIR)/unit/tb_dcache.v
	$(VVP) $(SIM_DIR)/test_dcache.vvp | tee $(LOG_DIR)/test_dcache.log
endif

#==============================================================================
# BPU Tests
#==============================================================================

.PHONY: test_bpu test_tage

test_tage: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_tage.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/bpu/bimodal_predictor.v \
		$(RTL_DIR)/bpu/tage_table.v \
		$(RTL_DIR)/bpu/tage_predictor.v \
		$(TB_DIR)/unit/tb_tage_predictor.v
	$(VVP) $(SIM_DIR)/test_tage.vvp | tee $(LOG_DIR)/test_tage.log
endif

test_bpu: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_bpu.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/bpu/*.v \
		$(TB_DIR)/unit/tb_bpu.v
	$(VVP) $(SIM_DIR)/test_bpu.vvp | tee $(LOG_DIR)/test_bpu.log
endif

#==============================================================================
# System Tests
#==============================================================================

.PHONY: test_cpu

test_cpu: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_cpu.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_SRCS) \
		$(TB_DIR)/system/tb_cpu_core.v
	$(VVP) $(SIM_DIR)/test_cpu.vvp | tee $(LOG_DIR)/test_cpu.log
endif

#==============================================================================
# Run All Tests
#==============================================================================

.PHONY: test_all
test_all: test_alu test_mul test_div test_decoder test_rob test_rs test_rat \
          test_icache test_dcache test_tage test_bpu test_cpu
	@echo "All tests completed."

#==============================================================================
# Lint
#==============================================================================

.PHONY: lint
lint:
	$(VERILATOR) --lint-only $(INC_DIRS) $(RTL_SRCS)

#==============================================================================
# Clean
#==============================================================================

clean:
	rm -rf $(SIM_DIR)/*.vvp
	rm -rf $(SIM_DIR)/*.vcd
	rm -rf $(WAVE_DIR)/*
	rm -rf $(LOG_DIR)/*
	rm -rf obj_dir
	@echo "Cleaned simulation files."

#==============================================================================
# Help
#==============================================================================

help:
	@echo "RISC-V Out-of-Order CPU Makefile"
	@echo ""
	@echo "Usage: make [target] [SIM=iverilog|verilator]"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Create directory structure (default)"
	@echo "  dirs         - Create directory structure"
	@echo "  test_alu     - Run ALU unit test"
	@echo "  test_mul     - Run multiplier unit test"
	@echo "  test_div     - Run divider unit test"
	@echo "  test_decoder - Run decoder test"
	@echo "  test_rob     - Run ROB test"
	@echo "  test_rs      - Run reservation station test"
	@echo "  test_rat     - Run RAT test"
	@echo "  test_icache  - Run I-Cache test"
	@echo "  test_dcache  - Run D-Cache test"
	@echo "  test_tage    - Run TAGE predictor test"
	@echo "  test_bpu     - Run BPU test"
	@echo "  test_cpu     - Run full CPU test"
	@echo "  test_all     - Run all tests"
	@echo "  lint         - Run Verilator lint"
	@echo "  clean        - Clean simulation files"
	@echo "  help         - Show this help"
