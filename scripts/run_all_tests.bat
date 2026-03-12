@echo off
chcp 65001 >nul
REM ============================================
REM RISC-V OoO CPU Test Runner
REM ============================================

setlocal enabledelayedexpansion

set PASS_COUNT=0
set FAIL_COUNT=0
set TOTAL_COUNT=0
set FAILED_TESTS=

if not exist sim\logs mkdir sim\logs

set REPORT_FILE=sim\logs\test_report.md

echo # RISC-V OoO CPU Test Report > %REPORT_FILE%
echo. >> %REPORT_FILE%
echo Generated: %date% %time% >> %REPORT_FILE%
echo. >> %REPORT_FILE%

echo ============================================
echo   RISC-V OoO CPU Test Runner
echo ============================================
echo.

echo ## Unit Tests >> %REPORT_FILE%
echo. >> %REPORT_FILE%

REM 1. ALU
echo [1/12] ALU Test...
set /a TOTAL_COUNT+=1
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_alu.vvp rtl/common/cpu_defines.vh rtl/core/alu_unit.v tb/unit/tb_alu_unit.v 2>sim\logs\alu_compile.log
if %errorlevel% neq 0 (
    echo   [FAIL] Compile error
    set /a FAIL_COUNT+=1
    set "FAILED_TESTS=!FAILED_TESTS! ALU"
    echo - ALU: **FAIL** compile error >> %REPORT_FILE%
) else (
    vvp sim/test_alu.vvp > sim\logs\alu_run.log 2>&1
    findstr /C:"PASS" sim\logs\alu_run.log >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [PASS]
        set /a PASS_COUNT+=1
        echo - ALU: **PASS** >> %REPORT_FILE%
    ) else (
        echo   [FAIL]
        set /a FAIL_COUNT+=1
        set "FAILED_TESTS=!FAILED_TESTS! ALU"
        echo - ALU: **FAIL** >> %REPORT_FILE%
    )
)

REM 2. MUL
echo [2/12] MUL Test...
set /a TOTAL_COUNT+=1
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_mul.vvp rtl/common/cpu_defines.vh rtl/core/mul_unit.v tb/unit/tb_mul_unit.v 2>sim\logs\mul_compile.log
if %errorlevel% neq 0 (
    echo   [FAIL] Compile error
    set /a FAIL_COUNT+=1
    set "FAILED_TESTS=!FAILED_TESTS! MUL"
    echo - MUL: **FAIL** compile error >> %REPORT_FILE%
) else (
    vvp sim/test_mul.vvp > sim\logs\mul_run.log 2>&1
    findstr /C:"PASS" sim\logs\mul_run.log >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [PASS]
        set /a PASS_COUNT+=1
        echo - MUL: **PASS** >> %REPORT_FILE%
    ) else (
        echo   [FAIL]
        set /a FAIL_COUNT+=1
        set "FAILED_TESTS=!FAILED_TESTS! MUL"
        echo - MUL: **FAIL** >> %REPORT_FILE%
    )
)

REM 3. DIV
echo [3/12] DIV Test...
set /a TOTAL_COUNT+=1
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_div.vvp rtl/common/cpu_defines.vh rtl/core/div_unit.v tb/unit/tb_div_unit.v 2>sim\logs\div_compile.log
if %errorlevel% neq 0 (
    echo   [FAIL] Compile error
    set /a FAIL_COUNT+=1
    set "FAILED_TESTS=!FAILED_TESTS! DIV"
    echo - DIV: **FAIL** compile error >> %REPORT_FILE%
) else (
    vvp sim/test_div.vvp > sim\logs\div_run.log 2>&1
    findstr /C:"PASS" sim\logs\div_run.log >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [PASS]
        set /a PASS_COUNT+=1
        echo - DIV: **PASS** >> %REPORT_FILE%
    ) else (
        echo   [FAIL]
        set /a FAIL_COUNT+=1
        set "FAILED_TESTS=!FAILED_TESTS! DIV"
        echo - DIV: **FAIL** >> %REPORT_FILE%
    )
)

REM 4. DECODER
echo [4/12] DECODER Test...
set /a TOTAL_COUNT+=1
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_decoder.vvp rtl/common/cpu_defines.vh rtl/core/decoder.v rtl/core/imm_gen.v tb/unit/tb_decoder.v 2>sim\logs\decoder_compile.log
if %errorlevel% neq 0 (
    echo   [FAIL] Compile error
    set /a FAIL_COUNT+=1
    set "FAILED_TESTS=!FAILED_TESTS! DECODER"
    echo - DECODER: **FAIL** compile error >> %REPORT_FILE%
) else (
    vvp sim/test_decoder.vvp > sim\logs\decoder_run.log 2>&1
    findstr /C:"PASS" sim\logs\decoder_run.log >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [PASS]
        set /a PASS_COUNT+=1
        echo - DECODER: **PASS** >> %REPORT_FILE%
    ) else (
        echo   [FAIL]
        set /a FAIL_COUNT+=1
        set "FAILED_TESTS=!FAILED_TESTS! DECODER"
        echo - DECODER: **FAIL** >> %REPORT_FILE%
    )
)

REM 5. BRANCH
echo [5/12] BRANCH Test...
set /a TOTAL_COUNT+=1
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_branch.vvp rtl/common/cpu_defines.vh rtl/core/branch_unit.v tb/unit/tb_branch_unit.v 2>sim\logs\branch_compile.log
if %errorlevel% neq 0 (
    echo   [FAIL] Compile error
    set /a FAIL_COUNT+=1
    set "FAILED_TESTS=!FAILED_TESTS! BRANCH"
    echo - BRANCH: **FAIL** compile error >> %REPORT_FILE%
) else (
    vvp sim/test_branch.vvp > sim\logs\branch_run.log 2>&1
    findstr /C:"PASS" sim\logs\branch_run.log >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [PASS]
        set /a PASS_COUNT+=1
        echo - BRANCH: **PASS** >> %REPORT_FILE%
    ) else (
        echo   [FAIL]
        set /a FAIL_COUNT+=1
        set "FAILED_TESTS=!FAILED_TESTS! BRANCH"
        echo - BRANCH: **FAIL** >> %REPORT_FILE%
    )
)

REM 6. BPU
echo [6/12] BPU Test...
set /a TOTAL_COUNT+=1
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_bpu.vvp rtl/common/cpu_defines.vh rtl/bpu/bimodal_predictor.v rtl/bpu/tage_table.v rtl/bpu/tage_predictor.v rtl/bpu/btb.v rtl/bpu/ras.v rtl/bpu/loop_predictor.v rtl/bpu/bpu.v tb/unit/tb_bpu.v 2>sim\logs\bpu_compile.log
if %errorlevel% neq 0 (
    echo   [FAIL] Compile error
    set /a FAIL_COUNT+=1
    set "FAILED_TESTS=!FAILED_TESTS! BPU"
    echo - BPU: **FAIL** compile error >> %REPORT_FILE%
) else (
    vvp sim/test_bpu.vvp > sim\logs\bpu_run.log 2>&1
    findstr /C:"PASS" sim\logs\bpu_run.log >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [PASS]
        set /a PASS_COUNT+=1
        echo - BPU: **PASS** >> %REPORT_FILE%
    ) else (
        echo   [FAIL]
        set /a FAIL_COUNT+=1
        set "FAILED_TESTS=!FAILED_TESTS! BPU"
        echo - BPU: **FAIL** >> %REPORT_FILE%
    )
)

REM 7. CACHE
echo [7/12] CACHE Test...
set /a TOTAL_COUNT+=1
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_cache.vvp rtl/common/cpu_defines.vh rtl/cache/icache.v rtl/cache/dcache.v tb/unit/tb_cache.v 2>sim\logs\cache_compile.log
if %errorlevel% neq 0 (
    echo   [FAIL] Compile error
    set /a FAIL_COUNT+=1
    set "FAILED_TESTS=!FAILED_TESTS! CACHE"
    echo - CACHE: **FAIL** compile error >> %REPORT_FILE%
) else (
    vvp sim/test_cache.vvp > sim\logs\cache_run.log 2>&1
    findstr /C:"PASS" sim\logs\cache_run.log >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [PASS]
        set /a PASS_COUNT+=1
        echo - CACHE: **PASS** >> %REPORT_FILE%
    ) else (
        echo   [FAIL]
        set /a FAIL_COUNT+=1
        set "FAILED_TESTS=!FAILED_TESTS! CACHE"
        echo - CACHE: **FAIL** >> %REPORT_FILE%
    )
)

REM 8. LSQ
echo [8/12] LSQ Test...
set /a TOTAL_COUNT+=1
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_lsq.vvp rtl/common/cpu_defines.vh rtl/mem/load_queue.v rtl/mem/store_queue.v rtl/mem/lsq.v tb/unit/tb_lsq.v 2>sim\logs\lsq_compile.log
if %errorlevel% neq 0 (
    echo   [FAIL] Compile error
    set /a FAIL_COUNT+=1
    set "FAILED_TESTS=!FAILED_TESTS! LSQ"
    echo - LSQ: **FAIL** compile error >> %REPORT_FILE%
) else (
    vvp sim/test_lsq.vvp > sim\logs\lsq_run.log 2>&1
    findstr /C:"PASS" sim\logs\lsq_run.log >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [PASS]
        set /a PASS_COUNT+=1
        echo - LSQ: **PASS** >> %REPORT_FILE%
    ) else (
        echo   [FAIL]
        set /a FAIL_COUNT+=1
        set "FAILED_TESTS=!FAILED_TESTS! LSQ"
        echo - LSQ: **FAIL** >> %REPORT_FILE%
    )
)

REM 9. EXCEPTION
echo [9/12] EXCEPTION Test...
set /a TOTAL_COUNT+=1
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_exception.vvp rtl/common/cpu_defines.vh rtl/core/exception_unit.v tb/unit/tb_exception.v 2>sim\logs\exception_compile.log
if %errorlevel% neq 0 (
    echo   [FAIL] Compile error
    set /a FAIL_COUNT+=1
    set "FAILED_TESTS=!FAILED_TESTS! EXCEPTION"
    echo - EXCEPTION: **FAIL** compile error >> %REPORT_FILE%
) else (
    vvp sim/test_exception.vvp > sim\logs\exception_run.log 2>&1
    findstr /C:"PASS" sim\logs\exception_run.log >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [PASS]
        set /a PASS_COUNT+=1
        echo - EXCEPTION: **PASS** >> %REPORT_FILE%
    ) else (
        echo   [FAIL]
        set /a FAIL_COUNT+=1
        set "FAILED_TESTS=!FAILED_TESTS! EXCEPTION"
        echo - EXCEPTION: **FAIL** >> %REPORT_FILE%
    )
)

REM 10. PIPELINE
echo [10/12] PIPELINE Test...
set /a TOTAL_COUNT+=1
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_pipeline_ctrl.vvp rtl/common/cpu_defines.vh rtl/core/pipeline_ctrl.v tb/unit/tb_pipeline_ctrl.v 2>sim\logs\pipeline_compile.log
if %errorlevel% neq 0 (
    echo   [FAIL] Compile error
    set /a FAIL_COUNT+=1
    set "FAILED_TESTS=!FAILED_TESTS! PIPELINE"
    echo - PIPELINE: **FAIL** compile error >> %REPORT_FILE%
) else (
    vvp sim/test_pipeline_ctrl.vvp > sim\logs\pipeline_run.log 2>&1
    findstr /C:"PASS" sim\logs\pipeline_run.log >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [PASS]
        set /a PASS_COUNT+=1
        echo - PIPELINE: **PASS** >> %REPORT_FILE%
    ) else (
        echo   [FAIL]
        set /a FAIL_COUNT+=1
        set "FAILED_TESTS=!FAILED_TESTS! PIPELINE"
        echo - PIPELINE: **FAIL** >> %REPORT_FILE%
    )
)

REM 11. OOO
echo [11/12] OOO_DEPS Test...
set /a TOTAL_COUNT+=1
iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_ooo_deps.vvp rtl/common/cpu_defines.vh rtl/core/rat.v rtl/core/free_list.v rtl/core/rob.v tb/unit/tb_ooo_deps.v 2>sim\logs\ooo_compile.log
if %errorlevel% neq 0 (
    echo   [FAIL] Compile error
    set /a FAIL_COUNT+=1
    set "FAILED_TESTS=!FAILED_TESTS! OOO"
    echo - OOO_DEPS: **FAIL** compile error >> %REPORT_FILE%
) else (
    vvp sim/test_ooo_deps.vvp > sim\logs\ooo_run.log 2>&1
    findstr /C:"PASS" sim\logs\ooo_run.log >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [PASS]
        set /a PASS_COUNT+=1
        echo - OOO_DEPS: **PASS** >> %REPORT_FILE%
    ) else (
        echo   [FAIL]
        set /a FAIL_COUNT+=1
        set "FAILED_TESTS=!FAILED_TESTS! OOO"
        echo - OOO_DEPS: **FAIL** >> %REPORT_FILE%
    )
)

echo. >> %REPORT_FILE%
echo ## Integration Tests >> %REPORT_FILE%
echo. >> %REPORT_FILE%

REM 12. INTEGRATION - use file list
echo [12/12] INTEGRATION Test...
set /a TOTAL_COUNT+=1

REM Create file list for integration test
echo rtl/common/cpu_defines.vh > sim\logs\instr_files.txt
echo rtl/core/alu_unit.v >> sim\logs\instr_files.txt
echo rtl/core/mul_unit.v >> sim\logs\instr_files.txt
echo rtl/core/div_unit.v >> sim\logs\instr_files.txt
echo rtl/core/branch_unit.v >> sim\logs\instr_files.txt
echo rtl/core/agu_unit.v >> sim\logs\instr_files.txt
echo rtl/core/decoder.v >> sim\logs\instr_files.txt
echo rtl/core/imm_gen.v >> sim\logs\instr_files.txt
echo rtl/core/rat.v >> sim\logs\instr_files.txt
echo rtl/core/free_list.v >> sim\logs\instr_files.txt
echo rtl/core/prf.v >> sim\logs\instr_files.txt
echo rtl/core/rob.v >> sim\logs\instr_files.txt
echo rtl/core/reservation_station.v >> sim\logs\instr_files.txt
echo rtl/core/cdb.v >> sim\logs\instr_files.txt
echo rtl/core/if_stage.v >> sim\logs\instr_files.txt
echo rtl/core/id_stage.v >> sim\logs\instr_files.txt
echo rtl/core/rn_stage.v >> sim\logs\instr_files.txt
echo rtl/core/is_stage.v >> sim\logs\instr_files.txt
echo rtl/core/ex_stage.v >> sim\logs\instr_files.txt
echo rtl/core/mem_stage.v >> sim\logs\instr_files.txt
echo rtl/core/wb_stage.v >> sim\logs\instr_files.txt
echo rtl/core/pipeline_ctrl.v >> sim\logs\instr_files.txt
echo rtl/core/exception_unit.v >> sim\logs\instr_files.txt
echo rtl/core/csr_unit.v >> sim\logs\instr_files.txt
echo rtl/core/clock_gate.v >> sim\logs\instr_files.txt
echo rtl/core/ecc_unit.v >> sim\logs\instr_files.txt
echo rtl/core/dft_wrapper.v >> sim\logs\instr_files.txt
echo rtl/core/debug_ctrl.v >> sim\logs\instr_files.txt
echo rtl/core/debug_csr.v >> sim\logs\instr_files.txt
echo rtl/core/perf_counters.v >> sim\logs\instr_files.txt
echo rtl/core/cpu_core_top.v >> sim\logs\instr_files.txt
echo rtl/cache/icache.v >> sim\logs\instr_files.txt
echo rtl/cache/dcache.v >> sim\logs\instr_files.txt
echo rtl/bpu/bimodal_predictor.v >> sim\logs\instr_files.txt
echo rtl/bpu/tage_table.v >> sim\logs\instr_files.txt
echo rtl/bpu/tage_predictor.v >> sim\logs\instr_files.txt
echo rtl/bpu/btb.v >> sim\logs\instr_files.txt
echo rtl/bpu/ras.v >> sim\logs\instr_files.txt
echo rtl/bpu/loop_predictor.v >> sim\logs\instr_files.txt
echo rtl/bpu/bpu.v >> sim\logs\instr_files.txt
echo rtl/mem/load_queue.v >> sim\logs\instr_files.txt
echo rtl/mem/store_queue.v >> sim\logs\instr_files.txt
echo rtl/mem/lsq.v >> sim\logs\instr_files.txt
echo rtl/bus/axi_master_ibus.v >> sim\logs\instr_files.txt
echo rtl/bus/axi_master_dbus.v >> sim\logs\instr_files.txt
echo tb/integration/tb_instr_tests.v >> sim\logs\instr_files.txt

iverilog -g2001 -Wall -Irtl/common -Irtl -o sim/test_instr.vvp -c sim\logs\instr_files.txt 2>sim\logs\instr_compile.log
if %errorlevel% neq 0 (
    echo   [FAIL] Compile error
    set /a FAIL_COUNT+=1
    set "FAILED_TESTS=!FAILED_TESTS! INTEGRATION"
    echo - INTEGRATION: **FAIL** compile error >> %REPORT_FILE%
) else (
    vvp sim/test_instr.vvp > sim\logs\instr_run.log 2>&1
    findstr /C:"PASS" sim\logs\instr_run.log >nul 2>&1
    if !errorlevel! equ 0 (
        echo   [PASS]
        set /a PASS_COUNT+=1
        echo - INTEGRATION: **PASS** >> %REPORT_FILE%
    ) else (
        echo   [FAIL]
        set /a FAIL_COUNT+=1
        set "FAILED_TESTS=!FAILED_TESTS! INTEGRATION"
        echo - INTEGRATION: **FAIL** >> %REPORT_FILE%
    )
)

echo. >> %REPORT_FILE%
echo ## Summary >> %REPORT_FILE%
echo. >> %REPORT_FILE%
echo - Total: %TOTAL_COUNT% >> %REPORT_FILE%
echo - Passed: %PASS_COUNT% >> %REPORT_FILE%
echo - Failed: %FAIL_COUNT% >> %REPORT_FILE%
echo. >> %REPORT_FILE%

if %FAIL_COUNT% gtr 0 (
    echo Failed tests:%FAILED_TESTS% >> %REPORT_FILE%
    echo. >> %REPORT_FILE%
    echo **Status: SOME TESTS FAILED** >> %REPORT_FILE%
) else (
    echo **Status: ALL TESTS PASSED** >> %REPORT_FILE%
)

echo.
echo ============================================
echo   Test Complete
echo ============================================
echo   Total: %TOTAL_COUNT%
echo   Passed: %PASS_COUNT%
echo   Failed: %FAIL_COUNT%
if %FAIL_COUNT% gtr 0 (
    echo   Failed:%FAILED_TESTS%
)
echo.
echo   Report: %REPORT_FILE%
echo ============================================

endlocal
