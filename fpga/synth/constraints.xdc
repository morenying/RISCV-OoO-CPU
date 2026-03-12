##=============================================================================
## Constraints File for RISC-V OoO CPU on EGO1 (Xilinx Artix-7 xc7a35tcsg324-1)
##
## This file defines:
## - Clock constraints
## - I/O pin assignments
## - I/O standards
## - Timing constraints
##
## Requirements: 8.2
##=============================================================================

##=============================================================================
## Clock Constraints
##=============================================================================

## System Clock (100MHz oscillator on EGO1)
create_clock -period 10.000 -name sys_clk [get_ports sys_clk_i]

## Generated Clock (50MHz from MMCM)
## The MMCM generates a 50MHz clock from the 100MHz input
## This is automatically constrained by Vivado when using MMCM

## Clock Groups - Asynchronous clocks
## If using multiple clock domains, define them here
# set_clock_groups -asynchronous -group [get_clocks sys_clk] -group [get_clocks clk_out1_clk_wiz]

##=============================================================================
## Input/Output Delays
##=============================================================================

## SRAM Timing Constraints
## IS61WV25616 timing: tAA = 10ns, tOE = 5ns, tWC = 10ns
set_input_delay -clock sys_clk -max 12.0 [get_ports sram_data_io[*]]
set_input_delay -clock sys_clk -min 0.0 [get_ports sram_data_io[*]]
set_output_delay -clock sys_clk -max 5.0 [get_ports sram_addr_o[*]]
set_output_delay -clock sys_clk -min 0.0 [get_ports sram_addr_o[*]]
set_output_delay -clock sys_clk -max 5.0 [get_ports sram_data_io[*]]
set_output_delay -clock sys_clk -min 0.0 [get_ports sram_data_io[*]]
set_output_delay -clock sys_clk -max 5.0 [get_ports {sram_ce_n_o sram_oe_n_o sram_we_n_o sram_lb_n_o sram_ub_n_o}]
set_output_delay -clock sys_clk -min 0.0 [get_ports {sram_ce_n_o sram_oe_n_o sram_we_n_o sram_lb_n_o sram_ub_n_o}]

## UART Timing (asynchronous, use false path or max delay)
set_input_delay -clock sys_clk -max 5.0 [get_ports uart_rx_i]
set_output_delay -clock sys_clk -max 5.0 [get_ports uart_tx_o]

## SPI Timing
set_output_delay -clock sys_clk -max 5.0 [get_ports {spi_sclk_o spi_mosi_o spi_cs_n_o}]
set_input_delay -clock sys_clk -max 10.0 [get_ports spi_miso_i]

## GPIO Timing (buttons and LEDs - relaxed timing)
set_input_delay -clock sys_clk -max 10.0 [get_ports btn_i[*]]
set_output_delay -clock sys_clk -max 10.0 [get_ports led_o[*]]

##=============================================================================
## Pin Assignments - EGO1 Development Board
## Note: These are example assignments - verify with actual board schematic
##=============================================================================

## System Clock (100MHz)
set_property PACKAGE_PIN P17 [get_ports sys_clk_i]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk_i]

## System Reset (Active Low - typically a button)
set_property PACKAGE_PIN P15 [get_ports sys_rst_n_i]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n_i]

##=============================================================================
## SRAM Interface (IS61WV25616 - 256K x 16)
## Note: Pin assignments depend on EGO1 board routing
##=============================================================================

## SRAM Address Bus [17:0]
set_property PACKAGE_PIN M18 [get_ports {sram_addr_o[0]}]
set_property PACKAGE_PIN M19 [get_ports {sram_addr_o[1]}]
set_property PACKAGE_PIN K17 [get_ports {sram_addr_o[2]}]
set_property PACKAGE_PIN N17 [get_ports {sram_addr_o[3]}]
set_property PACKAGE_PIN P18 [get_ports {sram_addr_o[4]}]
set_property PACKAGE_PIN L17 [get_ports {sram_addr_o[5]}]
set_property PACKAGE_PIN M16 [get_ports {sram_addr_o[6]}]
set_property PACKAGE_PIN L18 [get_ports {sram_addr_o[7]}]
set_property PACKAGE_PIN J18 [get_ports {sram_addr_o[8]}]
set_property PACKAGE_PIN H17 [get_ports {sram_addr_o[9]}]
set_property PACKAGE_PIN H18 [get_ports {sram_addr_o[10]}]
set_property PACKAGE_PIN J17 [get_ports {sram_addr_o[11]}]
set_property PACKAGE_PIN K18 [get_ports {sram_addr_o[12]}]
set_property PACKAGE_PIN K16 [get_ports {sram_addr_o[13]}]
set_property PACKAGE_PIN L16 [get_ports {sram_addr_o[14]}]
set_property PACKAGE_PIN N18 [get_ports {sram_addr_o[15]}]
set_property PACKAGE_PIN N19 [get_ports {sram_addr_o[16]}]
set_property PACKAGE_PIN P19 [get_ports {sram_addr_o[17]}]

## SRAM Data Bus [15:0] (Bidirectional)
set_property PACKAGE_PIN U20 [get_ports {sram_data_io[0]}]
set_property PACKAGE_PIN T20 [get_ports {sram_data_io[1]}]
set_property PACKAGE_PIN R19 [get_ports {sram_data_io[2]}]
set_property PACKAGE_PIN R18 [get_ports {sram_data_io[3]}]
set_property PACKAGE_PIN T19 [get_ports {sram_data_io[4]}]
set_property PACKAGE_PIN T18 [get_ports {sram_data_io[5]}]
set_property PACKAGE_PIN U19 [get_ports {sram_data_io[6]}]
set_property PACKAGE_PIN U18 [get_ports {sram_data_io[7]}]
set_property PACKAGE_PIN V20 [get_ports {sram_data_io[8]}]
set_property PACKAGE_PIN V19 [get_ports {sram_data_io[9]}]
set_property PACKAGE_PIN W20 [get_ports {sram_data_io[10]}]
set_property PACKAGE_PIN W19 [get_ports {sram_data_io[11]}]
set_property PACKAGE_PIN Y19 [get_ports {sram_data_io[12]}]
set_property PACKAGE_PIN Y18 [get_ports {sram_data_io[13]}]
set_property PACKAGE_PIN W18 [get_ports {sram_data_io[14]}]
set_property PACKAGE_PIN W17 [get_ports {sram_data_io[15]}]

## SRAM Control Signals
set_property PACKAGE_PIN R17 [get_ports sram_ce_n_o]
set_property PACKAGE_PIN T17 [get_ports sram_oe_n_o]
set_property PACKAGE_PIN U17 [get_ports sram_we_n_o]
set_property PACKAGE_PIN V17 [get_ports sram_lb_n_o]
set_property PACKAGE_PIN W16 [get_ports sram_ub_n_o]

## SRAM I/O Standard
set_property IOSTANDARD LVCMOS33 [get_ports sram_addr_o[*]]
set_property IOSTANDARD LVCMOS33 [get_ports sram_data_io[*]]
set_property IOSTANDARD LVCMOS33 [get_ports sram_ce_n_o]
set_property IOSTANDARD LVCMOS33 [get_ports sram_oe_n_o]
set_property IOSTANDARD LVCMOS33 [get_ports sram_we_n_o]
set_property IOSTANDARD LVCMOS33 [get_ports sram_lb_n_o]
set_property IOSTANDARD LVCMOS33 [get_ports sram_ub_n_o]

##=============================================================================
## UART Interface
##=============================================================================

## UART RX (from USB-UART bridge)
set_property PACKAGE_PIN N5 [get_ports uart_rx_i]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_i]

## UART TX (to USB-UART bridge)
set_property PACKAGE_PIN T4 [get_ports uart_tx_o]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_o]

##=============================================================================
## SPI Interface (for external Flash)
##=============================================================================

set_property PACKAGE_PIN L13 [get_ports spi_sclk_o]
set_property PACKAGE_PIN K17 [get_ports spi_mosi_o]
set_property PACKAGE_PIN K18 [get_ports spi_miso_i]
set_property PACKAGE_PIN L14 [get_ports spi_cs_n_o]
set_property IOSTANDARD LVCMOS33 [get_ports spi_sclk_o]
set_property IOSTANDARD LVCMOS33 [get_ports spi_mosi_o]
set_property IOSTANDARD LVCMOS33 [get_ports spi_miso_i]
set_property IOSTANDARD LVCMOS33 [get_ports spi_cs_n_o]

##=============================================================================
## LED Outputs [7:0]
##=============================================================================

set_property PACKAGE_PIN F6 [get_ports {led_o[0]}]
set_property PACKAGE_PIN G4 [get_ports {led_o[1]}]
set_property PACKAGE_PIN G3 [get_ports {led_o[2]}]
set_property PACKAGE_PIN J4 [get_ports {led_o[3]}]
set_property PACKAGE_PIN H4 [get_ports {led_o[4]}]
set_property PACKAGE_PIN J3 [get_ports {led_o[5]}]
set_property PACKAGE_PIN J2 [get_ports {led_o[6]}]
set_property PACKAGE_PIN K2 [get_ports {led_o[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports led_o[*]]

##=============================================================================
## Button Inputs [7:0]
##=============================================================================

set_property PACKAGE_PIN R11 [get_ports {btn_i[0]}]
set_property PACKAGE_PIN R17 [get_ports {btn_i[1]}]
set_property PACKAGE_PIN R15 [get_ports {btn_i[2]}]
set_property PACKAGE_PIN V1 [get_ports {btn_i[3]}]
set_property PACKAGE_PIN U4 [get_ports {btn_i[4]}]
set_property PACKAGE_PIN V5 [get_ports {btn_i[5]}]
set_property PACKAGE_PIN T3 [get_ports {btn_i[6]}]
set_property PACKAGE_PIN T2 [get_ports {btn_i[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports btn_i[*]]

##=============================================================================
## External Interrupt Inputs [3:0]
##=============================================================================

set_property PACKAGE_PIN U2 [get_ports {ext_irq_i[0]}]
set_property PACKAGE_PIN U1 [get_ports {ext_irq_i[1]}]
set_property PACKAGE_PIN W2 [get_ports {ext_irq_i[2]}]
set_property PACKAGE_PIN W1 [get_ports {ext_irq_i[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports ext_irq_i[*]]

##=============================================================================
## Debug UART Interface
##=============================================================================

set_property PACKAGE_PIN N4 [get_ports debug_uart_rx_i]
set_property PACKAGE_PIN R3 [get_ports debug_uart_tx_o]
set_property IOSTANDARD LVCMOS33 [get_ports debug_uart_rx_i]
set_property IOSTANDARD LVCMOS33 [get_ports debug_uart_tx_o]

##=============================================================================
## False Paths and Multicycle Paths
##=============================================================================

## Reset is asynchronous - use false path for timing analysis
set_false_path -from [get_ports sys_rst_n_i]

## Button inputs are asynchronous
set_false_path -from [get_ports btn_i[*]]

## External interrupts are asynchronous
set_false_path -from [get_ports ext_irq_i[*]]

## Debug UART is asynchronous
set_false_path -from [get_ports debug_uart_rx_i]
set_false_path -to [get_ports debug_uart_tx_o]

##=============================================================================
## Configuration and Bitstream Settings
##=============================================================================

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

##=============================================================================
## End of Constraints File
##=============================================================================
