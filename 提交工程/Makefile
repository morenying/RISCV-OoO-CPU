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

# Create directory structure (cross-platform)
dirs:
ifeq ($(OS),Windows_NT)
	@if not exist "$(RTL_DIR)\common" mkdir "$(RTL_DIR)\common"
	@if not exist "$(RTL_DIR)\core" mkdir "$(RTL_DIR)\core"
	@if not exist "$(RTL_DIR)\cache" mkdir "$(RTL_DIR)\cache"
	@if not exist "$(RTL_DIR)\bpu" mkdir "$(RTL_DIR)\bpu"
	@if not exist "$(RTL_DIR)\mem" mkdir "$(RTL_DIR)\mem"
	@if not exist "$(TB_DIR)\unit" mkdir "$(TB_DIR)\unit"
	@if not exist "$(TB_DIR)\integration" mkdir "$(TB_DIR)\integration"
	@if not exist "$(TB_DIR)\system" mkdir "$(TB_DIR)\system"
	@if not exist "$(TB_DIR)\common" mkdir "$(TB_DIR)\common"
	@if not exist "$(TB_DIR)\wave" mkdir "$(TB_DIR)\wave"
	@if not exist "$(TB_DIR)\perf" mkdir "$(TB_DIR)\perf"
	@if not exist "$(WAVE_DIR)" mkdir "$(WAVE_DIR)"
	@if not exist "$(LOG_DIR)" mkdir "$(LOG_DIR)"
else
	@mkdir -p $(RTL_DIR)/common
	@mkdir -p $(RTL_DIR)/core
	@mkdir -p $(RTL_DIR)/cache
	@mkdir -p $(RTL_DIR)/bpu
	@mkdir -p $(RTL_DIR)/mem
	@mkdir -p $(TB_DIR)/unit
	@mkdir -p $(TB_DIR)/integration
	@mkdir -p $(TB_DIR)/system
	@mkdir -p $(TB_DIR)/common
	@mkdir -p $(TB_DIR)/wave
	@mkdir -p $(TB_DIR)/perf
	@mkdir -p $(WAVE_DIR)
	@mkdir -p $(LOG_DIR)
endif
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
# Cache Property Tests
#==============================================================================

.PHONY: test_cache
test_cache: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_cache.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/cache/icache.v \
		$(RTL_DIR)/cache/dcache.v \
		$(TB_DIR)/unit/tb_cache.v
	$(VVP) $(SIM_DIR)/test_cache.vvp | tee $(LOG_DIR)/test_cache.log
endif

#==============================================================================
# LSQ Property Tests
#==============================================================================

.PHONY: test_lsq
test_lsq: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_lsq.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/mem/load_queue.v \
		$(RTL_DIR)/mem/store_queue.v \
		$(RTL_DIR)/mem/lsq.v \
		$(TB_DIR)/unit/tb_lsq.v
	$(VVP) $(SIM_DIR)/test_lsq.vvp | tee $(LOG_DIR)/test_lsq.log
endif

#==============================================================================
# Exception Property Tests
#==============================================================================

.PHONY: test_exception
test_exception: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_exception.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/exception_unit.v \
		$(TB_DIR)/unit/tb_exception.v
	$(VVP) $(SIM_DIR)/test_exception.vvp | tee $(LOG_DIR)/test_exception.log
endif

#==============================================================================
# Pipeline Control Property Tests
#==============================================================================

.PHONY: test_pipeline_ctrl
test_pipeline_ctrl: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_pipeline_ctrl.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/pipeline_ctrl.v \
		$(TB_DIR)/unit/tb_pipeline_ctrl.v
	$(VVP) $(SIM_DIR)/test_pipeline_ctrl.vvp | tee $(LOG_DIR)/test_pipeline_ctrl.log
endif

#==============================================================================
# Branch Unit Property Tests
#==============================================================================

.PHONY: test_branch
test_branch: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_branch.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/branch_unit.v \
		$(TB_DIR)/unit/tb_branch_unit.v
	$(VVP) $(SIM_DIR)/test_branch.vvp | tee $(LOG_DIR)/test_branch.log
endif

#==============================================================================
# OoO Dependency Tests
#==============================================================================

.PHONY: test_ooo_deps
test_ooo_deps: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_ooo_deps.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/rat.v \
		$(RTL_DIR)/core/free_list.v \
		$(RTL_DIR)/core/rob.v \
		$(TB_DIR)/unit/tb_ooo_deps.v
	$(VVP) $(SIM_DIR)/test_ooo_deps.vvp | tee $(LOG_DIR)/test_ooo_deps.log
endif

#==============================================================================
# Integration Tests
#==============================================================================

.PHONY: test_instr
test_instr: dirs
ifeq ($(SIM),iverilog)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/test_instr.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/*.v \
		$(RTL_DIR)/cache/*.v \
		$(RTL_DIR)/bpu/*.v \
		$(RTL_DIR)/mem/*.v \
		$(RTL_DIR)/bus/*.v \
		$(TB_DIR)/integration/tb_instr_tests.v
	$(VVP) $(SIM_DIR)/test_instr.vvp | tee $(LOG_DIR)/test_instr.log
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

.PHONY: test_all regression
test_all: test_alu test_mul test_div test_decoder test_branch test_bpu test_cache \
          test_lsq test_exception test_pipeline_ctrl test_ooo_deps test_instr
	@echo ""
	@echo "=============================================="
	@echo "  ALL TESTS COMPLETED"
	@echo "=============================================="

# Regression test (same as test_all)
regression: test_all

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
	@echo "  all              - Create directory structure (default)"
	@echo "  dirs             - Create directory structure"
	@echo ""
	@echo "Unit Tests:"
	@echo "  test_alu         - Run ALU unit test"
	@echo "  test_mul         - Run multiplier unit test"
	@echo "  test_div         - Run divider unit test"
	@echo "  test_decoder     - Run decoder test"
	@echo "  test_branch      - Run branch unit test"
	@echo "  test_bpu         - Run BPU property test"
	@echo "  test_cache       - Run Cache property test"
	@echo "  test_lsq         - Run LSQ property test"
	@echo "  test_exception   - Run Exception property test"
	@echo "  test_pipeline_ctrl - Run Pipeline Control property test"
	@echo "  test_ooo_deps    - Run OoO dependency test"
	@echo ""
	@echo "Wave Tests (Compact, ~15-30 cycles each, with GTKWave configs):"
	@echo "  wave_alu         - ALU wave test (12 ops)"
	@echo "  wave_mul         - MUL wave test (4 ops)"
	@echo "  wave_div         - DIV wave test (5 ops)"
	@echo "  wave_decoder     - Decoder wave test (12 instrs)"
	@echo "  wave_branch      - Branch wave test (9 ops)"
	@echo "  wave_rat         - RAT wave test (rename/checkpoint)"
	@echo "  wave_rob         - ROB wave test (alloc/complete/commit)"
	@echo "  wave_rs          - RS wave test (dispatch/wakeup/issue)"
	@echo "  wave_bpu         - BPU wave test (predict/update/recover)"
	@echo "  wave_lsq         - LSQ wave test (load/store/forward)"
	@echo "  wave_pipeline    - Pipeline ctrl wave test (stall/flush)"
	@echo "  wave_exception   - Exception wave test (all exc types)"
	@echo "  wave_csr         - CSR wave test (read/write/exception)"
	@echo "  wave_cdb         - CDB wave test (priority arbitration)"
	@echo "  wave_agu         - AGU wave test (addr calc/misalign)"
	@echo "  wave_all         - Run all wave tests"
	@echo ""
	@echo "Performance Tests:"
	@echo "  cpi_test         - CPI benchmark (forwarding/OoO/cache/BPU/LSQ)"
	@echo ""
	@echo "Integration Tests:"
	@echo "  test_instr       - Run instruction execution tests"
	@echo "  test_cpu         - Run full CPU system test"
	@echo ""
	@echo "Other:"
	@echo "  test_all         - Run all tests (regression)"
	@echo "  regression       - Run full regression suite"
	@echo "  lint             - Run Verilator lint"
	@echo "  clean            - Clean simulation files"
	@echo "  help             - Show this help"

#==============================================================================
# Wave Tests (Compact tests with GTKWave support)
#==============================================================================

WAVE_TB_DIR := $(TB_DIR)/wave
PERF_TB_DIR := $(TB_DIR)/perf

# ALU Wave Test
.PHONY: wave_alu
wave_alu: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_alu.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/alu_unit.v \
		$(WAVE_TB_DIR)/tb_alu_wave.v
	$(VVP) $(SIM_DIR)/wave_alu.vvp
	@echo "Wave file: sim/waves/alu_wave.vcd"
	@echo "GTKWave config: tb/wave/alu.gtkw"

# MUL Wave Test
.PHONY: wave_mul
wave_mul: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_mul.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/mul_unit.v \
		$(WAVE_TB_DIR)/tb_mul_wave.v
	$(VVP) $(SIM_DIR)/wave_mul.vvp
	@echo "Wave file: sim/waves/mul_wave.vcd"

# DIV Wave Test
.PHONY: wave_div
wave_div: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_div.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/div_unit.v \
		$(WAVE_TB_DIR)/tb_div_wave.v
	$(VVP) $(SIM_DIR)/wave_div.vvp
	@echo "Wave file: sim/waves/div_wave.vcd"

# Decoder Wave Test
.PHONY: wave_decoder
wave_decoder: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_decoder.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/decoder.v \
		$(RTL_DIR)/core/imm_gen.v \
		$(WAVE_TB_DIR)/tb_decoder_wave.v
	$(VVP) $(SIM_DIR)/wave_decoder.vvp
	@echo "Wave file: sim/waves/decoder_wave.vcd"

# Branch Wave Test
.PHONY: wave_branch
wave_branch: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_branch.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/branch_unit.v \
		$(WAVE_TB_DIR)/tb_branch_wave.v
	$(VVP) $(SIM_DIR)/wave_branch.vvp
	@echo "Wave file: sim/waves/branch_wave.vcd"

# RAT Wave Test
.PHONY: wave_rat
wave_rat: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_rat.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/rat.v \
		$(WAVE_TB_DIR)/tb_rat_wave.v
	$(VVP) $(SIM_DIR)/wave_rat.vvp
	@echo "Wave file: sim/waves/rat_wave.vcd"

# ROB Wave Test
.PHONY: wave_rob
wave_rob: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_rob.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/rob.v \
		$(WAVE_TB_DIR)/tb_rob_wave.v
	$(VVP) $(SIM_DIR)/wave_rob.vvp
	@echo "Wave file: sim/waves/rob_wave.vcd"

# RS Wave Test
.PHONY: wave_rs
wave_rs: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_rs.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/reservation_station.v \
		$(WAVE_TB_DIR)/tb_rs_wave.v
	$(VVP) $(SIM_DIR)/wave_rs.vvp
	@echo "Wave file: sim/waves/rs_wave.vcd"

# BPU Wave Test
.PHONY: wave_bpu
wave_bpu: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_bpu.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/bpu/*.v \
		$(WAVE_TB_DIR)/tb_bpu_wave.v
	$(VVP) $(SIM_DIR)/wave_bpu.vvp
	@echo "Wave file: sim/waves/bpu_wave.vcd"

# LSQ Wave Test
.PHONY: wave_lsq
wave_lsq: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_lsq.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/mem/load_queue.v \
		$(RTL_DIR)/mem/store_queue.v \
		$(RTL_DIR)/mem/lsq.v \
		$(WAVE_TB_DIR)/tb_lsq_wave.v
	$(VVP) $(SIM_DIR)/wave_lsq.vvp
	@echo "Wave file: sim/waves/lsq_wave.vcd"

# Pipeline Control Wave Test
.PHONY: wave_pipeline
wave_pipeline: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_pipeline.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/pipeline_ctrl.v \
		$(WAVE_TB_DIR)/tb_pipeline_wave.v
	$(VVP) $(SIM_DIR)/wave_pipeline.vvp
	@echo "Wave file: sim/waves/pipeline_wave.vcd"

# Exception Wave Test
.PHONY: wave_exception
wave_exception: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_exception.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/exception_unit.v \
		$(WAVE_TB_DIR)/tb_exception_wave.v
	$(VVP) $(SIM_DIR)/wave_exception.vvp
	@echo "Wave file: sim/waves/exception_wave.vcd"

# CSR Wave Test
.PHONY: wave_csr
wave_csr: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_csr.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/csr_unit.v \
		$(WAVE_TB_DIR)/tb_csr_wave.v
	$(VVP) $(SIM_DIR)/wave_csr.vvp
	@echo "Wave file: sim/waves/csr_wave.vcd"

# CDB Wave Test
.PHONY: wave_cdb
wave_cdb: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_cdb.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/cdb.v \
		$(WAVE_TB_DIR)/tb_cdb_wave.v
	$(VVP) $(SIM_DIR)/wave_cdb.vvp
	@echo "Wave file: sim/waves/cdb_wave.vcd"

# AGU Wave Test
.PHONY: wave_agu
wave_agu: dirs
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/wave_agu.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(RTL_DIR)/core/agu_unit.v \
		$(WAVE_TB_DIR)/tb_agu_wave.v
	$(VVP) $(SIM_DIR)/wave_agu.vvp
	@echo "Wave file: sim/waves/agu_wave.vcd"

# Run all wave tests
.PHONY: wave_all
wave_all: wave_alu wave_mul wave_div wave_decoder wave_branch wave_rat wave_rob \
          wave_rs wave_bpu wave_lsq wave_pipeline wave_exception wave_csr wave_cdb wave_agu
	@echo ""
	@echo "=============================================="
	@echo "  ALL WAVE TESTS COMPLETED"
	@echo "=============================================="

#==============================================================================
# CPI Performance Benchmark
#==============================================================================

.PHONY: cpi_test
cpi_test: dirs
	@mkdir -p $(PERF_TB_DIR)
	$(IVERILOG) $(IV_FLAGS) -o $(SIM_DIR)/cpi_benchmark.vvp \
		$(RTL_DIR)/common/cpu_defines.vh \
		$(PERF_TB_DIR)/tb_cpi_benchmark.v
	$(VVP) $(SIM_DIR)/cpi_benchmark.vvp | tee $(LOG_DIR)/cpi_benchmark.log
	@echo "Wave file: sim/waves/cpi_benchmark.vcd"
	@echo "GTKWave config: tb/perf/cpi_benchmark.gtkw"

#==============================================================================
# CI/CD Targets
#==============================================================================

.PHONY: ci ci-lint ci-test ci-report

# Full CI pipeline
ci: ci-lint ci-test ci-report
	@echo "CI pipeline completed successfully!"

# CI lint check
ci-lint: dirs
	@echo "Running lint check..."
	$(IVERILOG) $(IV_FLAGS) -o /dev/null $(RTL_SRCS) 2>&1 | tee $(LOG_DIR)/lint.log
	@echo "Lint check completed."

# CI test suite
ci-test: test_all
	@echo "All tests completed."

# CI report generation
ci-report:
	@echo "=== CI Test Report ===" > $(LOG_DIR)/ci_report.txt
	@echo "Date: $$(date)" >> $(LOG_DIR)/ci_report.txt
	@echo "" >> $(LOG_DIR)/ci_report.txt
	@for log in $(LOG_DIR)/test_*.log; do \
		echo "=== $$log ===" >> $(LOG_DIR)/ci_report.txt; \
		grep -E "PASS|FAIL|Total|Passed|Failed" $$log >> $(LOG_DIR)/ci_report.txt 2>/dev/null || true; \
		echo "" >> $(LOG_DIR)/ci_report.txt; \
	done
	@echo "CI report generated: $(LOG_DIR)/ci_report.txt"

#==============================================================================
# Coverage Targets (Verilator)
#==============================================================================

.PHONY: coverage coverage-report

# Run tests with coverage (requires Verilator)
coverage: dirs
	@echo "Coverage collection requires Verilator..."
	@if command -v verilator >/dev/null 2>&1; then \
		$(VERILATOR) --coverage $(VL_FLAGS) $(RTL_SRCS); \
	else \
		echo "Verilator not installed. Skipping coverage."; \
	fi

# Generate coverage report
coverage-report:
	@echo "Coverage report generation requires Verilator..."
	@if [ -d "coverage" ]; then \
		verilator_coverage --annotate coverage_annotate coverage/*.dat; \
	else \
		echo "No coverage data found."; \
	fi

#==============================================================================
# FPGA Targets
#==============================================================================

.PHONY: fpga-synth fpga-impl fpga-program

# FPGA synthesis (requires Vivado)
fpga-synth:
	@echo "FPGA synthesis requires Vivado..."
	@if command -v vivado >/dev/null 2>&1; then \
		cd fpga/synth && vivado -mode batch -source vivado_synth.tcl; \
	else \
		echo "Vivado not installed. Skipping synthesis."; \
	fi

# FPGA implementation (requires Vivado)
fpga-impl:
	@echo "FPGA implementation requires Vivado..."
	@if command -v vivado >/dev/null 2>&1; then \
		cd fpga/synth && vivado -mode batch -source vivado_impl.tcl; \
	else \
		echo "Vivado not installed. Skipping implementation."; \
	fi

# FPGA programming (requires Vivado)
fpga-program:
	@echo "FPGA programming requires Vivado and hardware..."
	@echo "Use Vivado Hardware Manager to program the FPGA."

#==============================================================================
# Documentation Targets
#==============================================================================

.PHONY: docs

docs:
	@echo "Documentation available in doc/ directory:"
	@ls -la doc/*.md 2>/dev/null || echo "No documentation found."

#==============================================================================
# Quick Check Target
#==============================================================================

.PHONY: check

# Quick syntax check without running tests
check: dirs
	@echo "Running quick syntax check..."
	@$(IVERILOG) $(IV_FLAGS) -o /dev/null $(RTL_SRCS) 2>&1 && echo "Syntax check PASSED" || echo "Syntax check FAILED"

