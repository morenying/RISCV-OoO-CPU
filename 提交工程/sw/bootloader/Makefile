# RISC-V Bootloader Makefile

# Toolchain
CROSS_COMPILE ?= riscv32-unknown-elf-
CC = $(CROSS_COMPILE)gcc
AS = $(CROSS_COMPILE)as
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump

# Flags
ASFLAGS = -march=rv32im -mabi=ilp32
LDFLAGS = -T bootloader.ld -nostdlib -nostartfiles

# Files
TARGET = bootloader
SRCS = bootloader.S
OBJS = $(SRCS:.S=.o)

# Outputs
ELF = $(TARGET).elf
BIN = $(TARGET).bin
HEX = $(TARGET).hex
DUMP = $(TARGET).dump

.PHONY: all clean

all: $(HEX) $(DUMP)

$(ELF): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(HEX): $(ELF)
	$(OBJCOPY) -O verilog $< $@

$(DUMP): $(ELF)
	$(OBJDUMP) -d -S $< > $@

%.o: %.S
	$(AS) $(ASFLAGS) -o $@ $<

clean:
	rm -f $(OBJS) $(ELF) $(BIN) $(HEX) $(DUMP)

# Generate hex file for simulation
sim: $(HEX)
	@echo "Bootloader hex file generated: $(HEX)"
	@echo "Copy to simulation directory"
