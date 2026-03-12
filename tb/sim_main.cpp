#include "Vtb_cpu_core_4way.h"
#include "verilated.h"
#include <cstdint>

vluint64_t main_time = 0;
double sc_time_stamp() { return main_time; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    auto contextp = new VerilatedContext;
    contextp->timeunit(-9); // 1 ns
    contextp->timeprecision(-12);

    auto top = new Vtb_cpu_core_4way{contextp};

    const uint64_t max_time = 20ull * 1000 * 1000; // 20 ms @ 1ns steps

    while (!contextp->gotFinish() && main_time < max_time) {
        top->eval();
        main_time += 1; // advance 1 ns
    }

    top->final();
    delete top;
    delete contextp;
    return 0;
}
