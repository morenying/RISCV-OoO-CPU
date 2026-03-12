/*
 * RISC-V Bootloader Linker Script
 *
 * Memory Layout:
 * - Boot ROM: 0x0000_0000 - 0x0000_3FFF (16KB)
 * - Main RAM: 0x8000_0000 - 0x8003_FFFF (256KB)
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 256K
}

SECTIONS
{
    /* Code section in ROM */
    .text : {
        *(.text.start)
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
    } > ROM

    /* Read-only data */
    .rodata : {
        *(.srodata)
        *(.srodata.*)
    } > ROM

    /* Data section - initialized data copied to RAM */
    .data : {
        _data_start = .;
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        _data_end = .;
    } > RAM AT > ROM

    _data_load = LOADADDR(.data);

    /* BSS section - uninitialized data in RAM */
    .bss : {
        _bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        _bss_end = .;
    } > RAM

    /* Stack at top of RAM */
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);

    /* Heap between BSS and stack */
    _heap_start = _bss_end;
    _heap_end = _stack_top - 4K;  /* Reserve 4K for stack */
}
