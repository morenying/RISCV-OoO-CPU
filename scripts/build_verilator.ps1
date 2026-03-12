# Verilator Build Script for RISC-V OoO CPU
# Usage: .\scripts\build_verilator.ps1

$ErrorActionPreference = "Stop"

# Setup environment
$env:PATH = "E:\download\MSYS32\mingw64\bin;$env:PATH"
$env:VERILATOR_ROOT = "E:\download\MSYS32\mingw64\share\verilator"

Write-Host "=== Building RISC-V OoO CPU with Verilator ===" -ForegroundColor Cyan

# Step 1: Generate C++ from Verilog
Write-Host "`n[1/3] Running Verilator..." -ForegroundColor Yellow
& E:\download\MSYS32\mingw64\bin\verilator_bin.exe `
    --cc --exe -j 0 `
    -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL `
    -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-LATCH -Wno-INITIALDLY `
    -Wno-BLKSEQ -Wno-MULTIDRIVEN -Wno-SYNCASYNCNET -Wno-UNDRIVEN `
    -Wno-UNUSEDPARAM -Wno-PINMISSING -Wno-IMPLICIT -Wno-CMPCONST `
    -Wno-UNSIGNED -Wno-SELRANGE `
    -y rtl/common -y rtl/core -y rtl/cache -y rtl/bpu -y rtl/mem -y rtl/bus `
    --top-module cpu_core_top -o sim_cpu `
    rtl/core/cpu_core_top.v tb/verilator/sim_main.cpp

if ($LASTEXITCODE -ne 0) { throw "Verilator failed" }

# Step 2: Compile C++ files
Write-Host "`n[2/3] Compiling C++ files..." -ForegroundColor Yellow

$cppFiles = @(
    "sim_main",
    "Vcpu_core_top",
    "Vcpu_core_top__Syms",
    "Vcpu_core_top__ConstPool_0",
    "Vcpu_core_top___024root__DepSet_h4501bf78__0",
    "Vcpu_core_top___024root__DepSet_h4501bf78__0__Slow",
    "Vcpu_core_top___024root__DepSet_hac1617a1__0",
    "Vcpu_core_top___024root__DepSet_hac1617a1__0__Slow",
    "Vcpu_core_top___024root__DepSet_hac1617a1__1",
    "Vcpu_core_top___024root__Slow"
)

foreach ($file in $cppFiles) {
    $src = if ($file -eq "sim_main") { "tb/verilator/sim_main.cpp" } else { "obj_dir/$file.cpp" }
    Write-Host "  Compiling $file..." -ForegroundColor Gray
    & g++ -std=c++17 -I obj_dir -I "$env:VERILATOR_ROOT/include" -O2 -c -o "obj_dir/$file.o" $src
    if ($LASTEXITCODE -ne 0) { throw "Compilation of $file failed" }
}

# Step 3: Link
Write-Host "`n[3/3] Linking..." -ForegroundColor Yellow
$objs = $cppFiles | ForEach-Object { "obj_dir/$_.o" }
$objs += "obj_dir/verilated.o", "obj_dir/verilated_threads.o"

& g++ -o obj_dir/sim_cpu.exe @objs -lpthread
if ($LASTEXITCODE -ne 0) { throw "Linking failed" }

Write-Host "`n=== Build Complete ===" -ForegroundColor Green
Write-Host "Run: .\obj_dir\sim_cpu.exe" -ForegroundColor Cyan
