
 create_clock -name clk50 -period 20.00  -waveform {0 10.00} [get_nets {clk50}]
create_clock -name clk_sys -period 18.60 -waveform {0 9.3} [get_nets {clk_sys}]
create_generated_clock -name clk_z80 -source [get_nets {clk_sys}] -divide_by 2 [get_nets {clk_z80}]

// Z80 to M68K, 2 clk_sys cycles
set_multicycle_path 4 -end -setup -from [get_clocks {clk_z80}] -to [get_clocks {clk_sys}]
set_multicycle_path 3 -end -hold -from [get_clocks {clk_z80}] -to [get_clocks {clk_sys}]

// From fx68k.txt
// micro-code fetch is needed in 2 cycles
//set_multicycle_path 4 -start -setup -from [get_pins {megadrive/M68K/Ir*/*}] -to [get_pins {megadrive/M68K/microAddr_*/*}]
//set_multicycle_path 3 -start -hold -from [get_pins {megadrive/M68K/Ir*/*}] -to [get_pins {megadrive/M68K/microAddr_*/*}]
//set_multicycle_path 4 -start -setup -from [get_pins {megadrive/M68K/Ir*/*}] -to [get_pins {megadrive/M68K/nanoAddr_*/*}]
//set_multicycle_path 3 -start -hold -from [get_pins {megadrive/M68K/Ir*/*}] -to [get_pins {megadrive/M68K/nanoAddr_*/*}]

// The update of the CCR flags is also time critical.
//set_multicycle_path 4 -start -setup -from [get_pins {megadrive/M68K/nanoLatch*/*}] -to [get_pins {megadrive/M68K/excUnit/alu/pswCcr*/*}]
//set_multicycle_path 3 -start -hold -from [get_pins {megadrive/M68K/nanoLatch*/*}] -to [get_pins {megadrive/M68K/excUnit/alu/pswCcr*/*}]
//set_multicycle_path 4 -start -setup -from [get_pins {megadrive/M68K/excUnit/alu/oper*/*}] -to [get_pins {megadrive/M68K/excUnit/alu/pswCcr*/*}]
//set_multicycle_path 3 -start -hold -from [get_pins {megadrive/M68K/excUnit/alu/oper*/*}] -to [get_pins {megadrive/M68K/excUnit/alu/pswCcr*/*}]

