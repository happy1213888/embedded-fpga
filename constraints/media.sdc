create_clock -name sys_clk -period 20.000 [get_ports sys_clk]
create_generated_clock -name mem_clk -source [get_ports sys_clk] -multiply_by 2 [get_pins {clocks/pll.clkc[0]}]
create_generated_clock -name pixel_clk -source [get_ports sys_clk] -divide_by 2 [get_pins {clocks/pll.clkc[1]}]
create_generated_clock -name serial_clk -source [get_ports sys_clk] -multiply_by 2.5 [get_pins {clocks/pll.clkc[2]}]
create_generated_clock -name sdram_clk -source [get_ports sys_clk] -multiply_by 2 -phase 248 [get_pins {clocks/pll.clkc[3]}]
set_clock_uncertainty 0.000 [get_clocks mem_clk]
# Returned data passes the SDRAM clock pad and tAC; capture at the following
# controller rising edge (20ns), rather than the immediately adjacent 10ns edge.
set_multicycle_path 2 -setup -end -from [get_pins {ram.dq[*]}]
set_multicycle_path 1 -hold -end -from [get_pins {ram.dq[*]}]
# DQ output enable is asserted in ACT, before RCD/WRITE, and released in RECOVER.
# Only OE gets this extra cycle; write data and command/address remain single-cycle.
set_multicycle_path 2 -setup -end -from [get_regs {memory/driving}] -to [get_pins {ram.dq[*]}]
set_multicycle_path 1 -hold -end -from [get_regs {memory/driving}] -to [get_pins {ram.dq[*]}]
# Only asynchronous board inputs are false paths. Related PLL clocks remain timed.
set_false_path -from [get_ports {key_n[*] sw[*]}]
# Asynchronous assertion is confined to the preserved reset synchronizer registers.
set_false_path -through [get_nets {mem_reset/async_reset pixel_reset/async_reset}]
# Fastest SPI: HIGH_DIV=2, 16.667MHz mode 0. Data changes on falling SCK.
create_generated_clock -name sd_spi_clk -source [get_pins {clocks/pll.clkc[0]}] -divide_by 6 [get_ports SD_DCLK]
# 14ns SD output access plus 3ns board budget; RX is enabled at the next rising SCK.
set_input_delay -clock sd_spi_clk -clock_fall -max 17.0 [get_ports SD_MISO]
set_input_delay -clock sd_spi_clk -clock_fall -min 0.0 [get_ports SD_MISO]
set_multicycle_path 3 -setup -end -from [get_ports SD_MISO]
set_multicycle_path 2 -hold -end -from [get_ports SD_MISO]
# MOSI/CS retain a conservative 20ns window (actual half-SCK is 30ns).
set_output_delay -clock mem_clk -max 6.0 [get_ports {SD_nCS SD_MOSI}]
set_output_delay -clock mem_clk -min 0.0 [get_ports {SD_nCS SD_MOSI}]
set_multicycle_path 2 -setup -to [get_ports {SD_nCS SD_MOSI}]
set_multicycle_path 1 -hold -to [get_ports {SD_nCS SD_MOSI}]

