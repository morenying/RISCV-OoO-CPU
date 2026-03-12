@echo off
REM Verilator compilation script for RISC-V OoO CPU
set VERILATOR=E:\download\MSYS32\mingw64\bin\verilator_bin.exe
set MINGW_BIN=E:\download\MSYS32\mingw64\bin

echo === Verilating CPU ===
%VERILATOR% --cc --exe --build -j 0 ^
    -Irtl/common -Irtl/core -Irtl/cache -Irtl/bpu -Irtl/mem -Irtl/bus ^
    --top-module cpu_core_top ^
    -Wno-fatal ^
    rtl/core/cpu_core_top.v ^
    rtl/core/if_stage.v rtl/core/id_stage.v rtl/core/rn_stage.v ^
    rtl/core/is_stage.v rtl/core/ex_stage.v rtl/core/mem_stage.v ^
    rtl/core/wb_stage.v rtl/core/decoder.v rtl/core/imm_gen.v ^
    rtl/core/alu_unit.v rtl/core/mul_unit.v rtl/core/div_unit.v ^
    rtl/core/branch_unit.v rtl/core/agu_unit.v rtl/core/csr_unit.v ^
    rtl/core/exception_unit.v rtl/core/pipeline_ctrl.v ^
    rtl/core/rob.v rtl/core/reservation_station.v ^
    rtl/core/rat.v rtl/core/prf.v rtl/core/free_list.v rtl/core/cdb.v ^
    rtl/cache/icache.v rtl/cache/dcache.v ^
    rtl/bpu/bpu.v rtl/bpu/bimodal_predictor.v rtl/bpu/tage_predictor.v ^
    rtl/bpu/tage_table.v rtl/bpu/btb.v rtl/bpu/ras.v rtl/bpu/loop_predictor.v ^
    rtl/mem/lsq.v rtl/mem/load_queue.v rtl/mem/store_queue.v

if %ERRORLEVEL% EQU 0 (
    echo === Verilator compilation successful! ===
) else (
    echo === Verilator compilation failed ===
)
pause