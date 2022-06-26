vlib work

vcom bshifter.vhd
vcom alu.vhd
vcom reg_bank.vhd
vcom control.vhd
vcom datapath.vhd
vcom int_control.vhd
vcom cpu.vhd
vcom uart.vhd
vcom basic_soc.vhd
vcom boot_ram.vhd
vcom ram.vhd

vcom -cover bcesx bram_block_a.vhdl
vcom -cover bcesx bram_block_b.vhdl
vcom -cover bcesx counter2bit.vhdl
vcom -cover bcesx key_scheduler.vhdl
vcom -cover bcesx xtime.vhdl
vcom -cover bcesx mix_column.vhdl
vcom -cover bcesx folded_register.vhdl
vcom -cover bcesx io_interface.vhdl
vcom -cover bcesx mini_aes.vhdl

vcom hf-riscv_tb.vhd

vsim -voptargs="+acc" tb

add wave sim:/*

run 1000000000 ns
