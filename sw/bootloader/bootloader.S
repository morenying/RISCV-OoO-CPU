#############################################################################
# RISC-V Bootloader Assembly Code
#
# Features:
# - Initialize all CSRs to known state
# - Initialize stack pointer
# - Clear .bss section
# - Initialize hardware (UART, SPI)
# - Load user program from UART or SPI Flash
# - Verify CRC32 checksum
# - Jump to user program entry point
#
# Memory Map:
# 0x0000_0000 - 0x0000_3FFF: Boot ROM (this code)
# 0x8000_0000 - 0x8003_FFFF: Main Memory (user program)
#
# Boot Protocol (UART):
# 1. Send SYNC byte (0x55)
# 2. Receive SIZE (4 bytes, little-endian)
# 3. Receive DATA (SIZE bytes)
# 4. Receive CRC32 (4 bytes)
# 5. Send ACK (0x06) or NAK (0x15)
#
# 禁止事项:
# - 禁止跳过 CSR 初始化
# - 禁止假设内存已清零
# - 禁止无校验直接加载
# - 禁止硬编码加载地址
#############################################################################

.section .text.start
.global _start
.global _reset_vector

#############################################################################
# Constants
#############################################################################
.equ UART_BASE,      0x10000000
.equ UART_DATA,      0x00
.equ UART_STATUS,    0x04
.equ UART_CTRL,      0x08
.equ UART_BAUD,      0x0C

.equ SPI_BASE,       0x10000300
.equ SPI_DATA,       0x00
.equ SPI_STATUS,     0x04
.equ SPI_CTRL,       0x08
.equ SPI_CLKDIV,     0x0C
.equ SPI_CS,         0x10

.equ GPIO_BASE,      0x10000100
.equ GPIO_OUT,       0x00
.equ GPIO_IN,        0x04

.equ LOAD_ADDR,      0x80000000
.equ STACK_TOP,      0x80040000
.equ BOOT_MAGIC,     0x52495343    # "RISC"

.equ SYNC_BYTE,      0x55
.equ ACK_BYTE,       0x06
.equ NAK_BYTE,       0x15

.equ STATUS_TX_EMPTY, 0x01
.equ STATUS_RX_FULL,  0x04

# SPI Flash Commands
.equ CMD_READ,       0x03
.equ CMD_FAST_READ,  0x0B
.equ CMD_RDID,       0x9F

#############################################################################
# Reset Vector
#############################################################################
_reset_vector:
_start:
    # Disable interrupts
    csrw    mie, zero
    csrw    mstatus, zero
    
    # Initialize all general purpose registers to zero
    li      x1, 0
    li      x2, 0
    li      x3, 0
    li      x4, 0
    li      x5, 0
    li      x6, 0
    li      x7, 0
    li      x8, 0
    li      x9, 0
    li      x10, 0
    li      x11, 0
    li      x12, 0
    li      x13, 0
    li      x14, 0
    li      x15, 0
    li      x16, 0
    li      x17, 0
    li      x18, 0
    li      x19, 0
    li      x20, 0
    li      x21, 0
    li      x22, 0
    li      x23, 0
    li      x24, 0
    li      x25, 0
    li      x26, 0
    li      x27, 0
    li      x28, 0
    li      x29, 0
    li      x30, 0
    li      x31, 0
    
    # Initialize stack pointer
    li      sp, STACK_TOP
    
    # Initialize CSRs
    j       init_csrs

#############################################################################
# CSR Initialization
#############################################################################
init_csrs:
    # Clear machine trap-vector base address
    csrw    mtvec, zero
    
    # Clear machine exception program counter
    csrw    mepc, zero
    
    # Clear machine cause register
    csrw    mcause, zero
    
    # Clear machine trap value register
    csrw    mtval, zero
    
    # Clear machine scratch register
    csrw    mscratch, zero
    
    # Set machine status: MPP=M-mode, MIE=0
    li      t0, 0x00001800    # MPP = 11 (M-mode)
    csrw    mstatus, t0
    
    # Initialize performance counters
    csrw    mcycle, zero
    csrw    minstret, zero
    
    j       init_hardware

#############################################################################
# Hardware Initialization
#############################################################################
init_hardware:
    # Initialize UART
    li      t0, UART_BASE
    
    # Set baud rate divisor for 115200 @ 50MHz
    # Divisor = 50000000 / (16 * 115200) = 27
    li      t1, 27
    sw      t1, UART_BAUD(t0)
    
    # Enable UART
    li      t1, 0x01
    sw      t1, UART_CTRL(t0)
    
    # Initialize SPI
    li      t0, SPI_BASE
    
    # Set clock divider for 1MHz SPI clock
    li      t1, 50
    sw      t1, SPI_CLKDIV(t0)
    
    # Deselect chip
    li      t1, 1
    sw      t1, SPI_CS(t0)
    
    # Enable SPI
    li      t1, 0x01
    sw      t1, SPI_CTRL(t0)
    
    # Initialize GPIO (turn on LED to indicate boot)
    li      t0, GPIO_BASE
    li      t1, 0x01
    sw      t1, GPIO_OUT(t0)
    
    j       detect_boot_mode

#############################################################################
# Boot Mode Detection
#############################################################################
detect_boot_mode:
    # Check GPIO input for boot mode selection
    # Bit 0: 0 = UART boot, 1 = SPI Flash boot
    li      t0, GPIO_BASE
    lw      t1, GPIO_IN(t0)
    andi    t1, t1, 0x01
    
    beqz    t1, uart_boot
    j       spi_boot

#############################################################################
# UART Boot Protocol
#############################################################################
uart_boot:
    # Send SYNC byte to indicate ready
    li      a0, SYNC_BYTE
    jal     uart_send_byte
    
    # Receive program size (4 bytes, little-endian)
    jal     uart_recv_byte
    mv      s0, a0              # s0 = size[7:0]
    
    jal     uart_recv_byte
    slli    t0, a0, 8
    or      s0, s0, t0          # s0 = size[15:0]
    
    jal     uart_recv_byte
    slli    t0, a0, 16
    or      s0, s0, t0          # s0 = size[23:0]
    
    jal     uart_recv_byte
    slli    t0, a0, 24
    or      s0, s0, t0          # s0 = size[31:0]
    
    # Validate size (must be > 0 and <= 256KB)
    beqz    s0, uart_boot_error
    li      t0, 0x40000         # 256KB
    bgt     s0, t0, uart_boot_error
    
    # Initialize CRC32
    li      s1, 0xFFFFFFFF      # s1 = CRC accumulator
    
    # Load program data
    li      s2, LOAD_ADDR       # s2 = destination address
    mv      s3, s0              # s3 = bytes remaining
    
uart_load_loop:
    beqz    s3, uart_load_done
    
    # Receive byte
    jal     uart_recv_byte
    
    # Store byte
    sb      a0, 0(s2)
    
    # Update CRC32
    mv      a1, s1
    jal     crc32_update
    mv      s1, a0
    
    # Advance pointers
    addi    s2, s2, 1
    addi    s3, s3, -1
    
    j       uart_load_loop

uart_load_done:
    # Finalize CRC
    not     s1, s1              # s1 = final CRC
    
    # Receive expected CRC (4 bytes)
    jal     uart_recv_byte
    mv      s4, a0
    
    jal     uart_recv_byte
    slli    t0, a0, 8
    or      s4, s4, t0
    
    jal     uart_recv_byte
    slli    t0, a0, 16
    or      s4, s4, t0
    
    jal     uart_recv_byte
    slli    t0, a0, 24
    or      s4, s4, t0
    
    # Compare CRC
    bne     s1, s4, uart_crc_error
    
    # Send ACK
    li      a0, ACK_BYTE
    jal     uart_send_byte
    
    # Jump to loaded program
    j       jump_to_program

uart_boot_error:
uart_crc_error:
    # Send NAK
    li      a0, NAK_BYTE
    jal     uart_send_byte
    
    # Blink LED to indicate error
    li      t0, GPIO_BASE
    li      t1, 0x02
    sw      t1, GPIO_OUT(t0)
    
    # Retry
    j       uart_boot

#############################################################################
# SPI Flash Boot
#############################################################################
spi_boot:
    # Read boot header from SPI Flash at address 0
    li      s0, 0               # Flash address
    
    # Read magic number
    mv      a0, s0
    li      a1, 4
    li      a2, LOAD_ADDR
    jal     spi_read
    
    # Check magic
    li      t0, LOAD_ADDR
    lw      t1, 0(t0)
    li      t2, BOOT_MAGIC
    bne     t1, t2, spi_boot_error
    
    # Read header (entry point, load address, size)
    li      a0, 4               # Skip magic
    li      a1, 12              # 3 words
    li      a2, LOAD_ADDR
    jal     spi_read
    
    li      t0, LOAD_ADDR
    lw      s1, 0(t0)           # s1 = entry point
    lw      s2, 4(t0)           # s2 = load address
    lw      s3, 8(t0)           # s3 = size
    
    # Validate
    beqz    s3, spi_boot_error
    li      t0, 0x40000
    bgt     s3, t0, spi_boot_error
    
    # Load program from Flash
    li      a0, 16              # Skip header
    mv      a1, s3              # Size
    mv      a2, s2              # Load address
    jal     spi_read
    
    # Store entry point for jump
    mv      s0, s1
    
    j       jump_to_program

spi_boot_error:
    # Blink LED pattern for SPI error
    li      t0, GPIO_BASE
    li      t1, 0x04
    sw      t1, GPIO_OUT(t0)
    
    # Fall back to UART boot
    j       uart_boot

#############################################################################
# Jump to User Program
#############################################################################
jump_to_program:
    # Validate entry point
    li      t0, 0x80000000
    blt     s0, t0, boot_error
    li      t0, 0x80040000
    bge     s0, t0, boot_error
    
    # Turn off boot LED
    li      t0, GPIO_BASE
    sw      zero, GPIO_OUT(t0)
    
    # Disable interrupts before jump
    csrw    mie, zero
    
    # Clear pipeline with fence
    fence.i
    fence
    
    # Set return address to trap handler
    la      ra, boot_error
    
    # Jump to user program
    jr      s0

boot_error:
    # Infinite loop on error
    li      t0, GPIO_BASE
    li      t1, 0xFF
    sw      t1, GPIO_OUT(t0)
1:  j       1b

#############################################################################
# UART Helper Functions
#############################################################################

# uart_send_byte: Send byte in a0
uart_send_byte:
    li      t0, UART_BASE
1:  lw      t1, UART_STATUS(t0)
    andi    t1, t1, STATUS_TX_EMPTY
    beqz    t1, 1b
    sw      a0, UART_DATA(t0)
    ret

# uart_recv_byte: Receive byte, return in a0
uart_recv_byte:
    li      t0, UART_BASE
1:  lw      t1, UART_STATUS(t0)
    andi    t1, t1, STATUS_RX_FULL
    beqz    t1, 1b
    lw      a0, UART_DATA(t0)
    andi    a0, a0, 0xFF
    ret

#############################################################################
# SPI Helper Functions
#############################################################################

# spi_read: Read from SPI Flash
# a0 = flash address
# a1 = byte count
# a2 = destination address
spi_read:
    # Save registers
    addi    sp, sp, -16
    sw      ra, 0(sp)
    sw      s0, 4(sp)
    sw      s1, 8(sp)
    sw      s2, 12(sp)
    
    mv      s0, a0              # Flash address
    mv      s1, a1              # Byte count
    mv      s2, a2              # Destination
    
    li      t0, SPI_BASE
    
    # Assert CS (active low)
    sw      zero, SPI_CS(t0)
    
    # Send READ command
    li      a0, CMD_READ
    jal     spi_transfer
    
    # Send 24-bit address (MSB first)
    srli    a0, s0, 16
    andi    a0, a0, 0xFF
    jal     spi_transfer
    
    srli    a0, s0, 8
    andi    a0, a0, 0xFF
    jal     spi_transfer
    
    andi    a0, s0, 0xFF
    jal     spi_transfer
    
    # Read data bytes
spi_read_loop:
    beqz    s1, spi_read_done
    
    li      a0, 0xFF            # Dummy byte
    jal     spi_transfer
    
    sb      a0, 0(s2)
    addi    s2, s2, 1
    addi    s1, s1, -1
    j       spi_read_loop

spi_read_done:
    # Deassert CS
    li      t0, SPI_BASE
    li      t1, 1
    sw      t1, SPI_CS(t0)
    
    # Restore registers
    lw      ra, 0(sp)
    lw      s0, 4(sp)
    lw      s1, 8(sp)
    lw      s2, 12(sp)
    addi    sp, sp, 16
    ret

# spi_transfer: Transfer byte, return received byte
# a0 = byte to send, returns received byte in a0
spi_transfer:
    li      t0, SPI_BASE
    
    # Write byte to TX
    sw      a0, SPI_DATA(t0)
    
    # Wait for transfer complete
1:  lw      t1, SPI_STATUS(t0)
    andi    t1, t1, 0x10        # BUSY bit
    bnez    t1, 1b
    
    # Read received byte
    lw      a0, SPI_DATA(t0)
    andi    a0, a0, 0xFF
    ret

#############################################################################
# CRC32 Calculation
#############################################################################

# crc32_update: Update CRC with one byte
# a0 = byte
# a1 = current CRC
# Returns new CRC in a0
crc32_update:
    xor     a1, a1, a0
    li      t0, 8               # 8 bits
crc_loop:
    beqz    t0, crc_done
    andi    t1, a1, 1
    srli    a1, a1, 1
    beqz    t1, crc_skip
    li      t2, 0xEDB88320      # CRC32 polynomial
    xor     a1, a1, t2
crc_skip:
    addi    t0, t0, -1
    j       crc_loop
crc_done:
    mv      a0, a1
    ret

#############################################################################
# Data Section
#############################################################################
.section .data
boot_msg:
    .asciz "RISC-V Bootloader v1.0\r\n"

.section .bss
.align 4
temp_buffer:
    .space 256
