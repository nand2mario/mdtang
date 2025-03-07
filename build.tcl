if {$argc == 0} {
    puts "Usage: $argv0 <device> <mcu>"
    puts "          device: mega60k mega138k mega138kpro console60k"
    puts "             mcu: bl616, picorv32"
    puts "Currently supports only ds2 controller"
    exit 1
}

set dev [lindex $argv 0]
if {$argc >= 2} {
    set mcu [lindex $argv 1]
} else {
    set mcu "bl616"
}

if {$dev eq "mega60k"} {
    set_device GW5AT-LV60PG484AC1/I0 -device_version B
    add_file -type cst "src/m138k/m138k.cst"
    add_file -type verilog "src/m60k/pll.v"
    add_file -type verilog "src/m60k/pll_27.v"
    add_file -type verilog "src/m60k/pll_74.v"
} elseif {$dev eq "console60k"} {
    set_device GW5AT-LV60PG484AC1/I0 -device_version B
    add_file -type cst "src/console60k/mdtang.cst"
    add_file -type verilog "src/m60k/pll.v"
    add_file -type verilog "src/m60k/pll_27.v"
    add_file -type verilog "src/m60k/pll_74.v"    
} elseif {$dev eq "mega138k"} {
    set_device GW5AT-LV138PG484AC1/I0 -device_version B
    add_file -type cst "src/m138k/m138k.cst"
    add_file -type verilog "src/m138k/pll.v"
    add_file -type verilog "src/m138k/pll_27.v"
    add_file -type verilog "src/m138k/pll_74.v"
} elseif {$dev eq "mega138kpro"} {
    set_device GW5AST-LV138FPG676AC1/I0 -device_version B
    add_file -type cst "src/m138k/m138kpro.cst"
    add_file -type verilog "src/m138k/pll.v"
    add_file -type verilog "src/m138k/pll_27.v"
    add_file -type verilog "src/m138k/pll_74.v"
} else {
    error "Unknown device $dev"
}
add_file -type sdc "src/mdtang.sdc"
set_option -output_base_name mdtang_${dev}_${mcu}

if {$mcu eq "bl616"} {
    add_file -type verilog "src/iosys/iosys_bl616.v"
    add_file -type verilog "src/iosys/picorv32.v"
    add_file -type verilog "src/iosys/uart_fixed.v"
} elseif {$mcu eq "picorv32"} {
    add_file -type verilog "src/iosys/iosys_picorv32.v"
    add_file -type verilog "src/iosys/simplespimaster1x.v"
    add_file -type verilog "src/iosys/simpleuart.v"
    add_file -type verilog "src/iosys/spi_master.v"
    add_file -type verilog "src/iosys/spiflash.v"
} else {
    error "Unknown mcu $mcu"
}
add_file -type verilog "src/iosys/textdisp.v"
add_file -type verilog "src/iosys/gowin_dpb_menu.v"
add_file -type verilog "src/iosys/dualshock_controller.v"

add_file -type verilog "src/common/dpram.v"
add_file -type verilog "src/common/dpram32_block.v"
add_file -type verilog "src/common/dpram_block.v"
add_file -type verilog "src/fx68k/fx68k.sv"
add_file -type verilog "src/fx68k/fx68kAlu.sv"
add_file -type verilog "src/fx68k/uaddrPla.sv"
add_file -type verilog "src/hdmi/audio_clock_regeneration_packet.sv"
add_file -type verilog "src/hdmi/audio_info_frame.sv"
add_file -type verilog "src/hdmi/audio_sample_packet.sv"
add_file -type verilog "src/hdmi/auxiliary_video_information_info_frame.sv"
add_file -type verilog "src/hdmi/hdmi.sv"
add_file -type verilog "src/hdmi/packet_assembler.sv"
add_file -type verilog "src/hdmi/packet_picker.sv"
add_file -type verilog "src/hdmi/serializer.sv"
add_file -type verilog "src/hdmi/source_product_description_info_frame.sv"
add_file -type verilog "src/hdmi/tmds_channel.sv"
add_file -type verilog "src/framebuffer_sync.sv"
add_file -type verilog "src/jt12/adpcm/jt10_adpcm_div.v"
add_file -type verilog "src/jt12/jt12.v"
add_file -type verilog "src/jt12/jt12_acc.v"
add_file -type verilog "src/jt12/jt12_csr.v"
add_file -type verilog "src/jt12/jt12_div.v"
add_file -type verilog "src/jt12/jt12_dout.v"
add_file -type verilog "src/jt12/jt12_eg.v"
add_file -type verilog "src/jt12/jt12_eg_cnt.v"
add_file -type verilog "src/jt12/jt12_eg_comb.v"
add_file -type verilog "src/jt12/jt12_eg_ctrl.v"
add_file -type verilog "src/jt12/jt12_eg_final.v"
add_file -type verilog "src/jt12/jt12_eg_pure.v"
add_file -type verilog "src/jt12/jt12_eg_step.v"
add_file -type verilog "src/jt12/jt12_exprom.v"
add_file -type verilog "src/jt12/jt12_kon.v"
add_file -type verilog "src/jt12/jt12_lfo.v"
add_file -type verilog "src/jt12/jt12_logsin.v"
add_file -type verilog "src/jt12/jt12_mmr.v"
add_file -type verilog "src/jt12/jt12_mod.v"
add_file -type verilog "src/jt12/jt12_op.v"
add_file -type verilog "src/jt12/jt12_pcm_interpol.v"
add_file -type verilog "src/jt12/jt12_pg.v"
add_file -type verilog "src/jt12/jt12_pg_comb.v"
add_file -type verilog "src/jt12/jt12_pg_dt.v"
add_file -type verilog "src/jt12/jt12_pg_inc.v"
add_file -type verilog "src/jt12/jt12_pg_sum.v"
add_file -type verilog "src/jt12/jt12_pm.v"
add_file -type verilog "src/jt12/jt12_reg.v"
add_file -type verilog "src/jt12/jt12_rst.v"
add_file -type verilog "src/jt12/jt12_sh.v"
add_file -type verilog "src/jt12/jt12_sh24.v"
add_file -type verilog "src/jt12/jt12_sh_rst.v"
add_file -type verilog "src/jt12/jt12_single_acc.v"
add_file -type verilog "src/jt12/jt12_sumch.v"
add_file -type verilog "src/jt12/jt12_timers.v"
add_file -type verilog "src/jt12/jt12_top.v"
add_file -type verilog "src/jt12/mixer/jt12_comb.v"
add_file -type verilog "src/jt12/mixer/jt12_decim.v"
add_file -type verilog "src/jt12/mixer/jt12_fm_uprate.v"
add_file -type verilog "src/jt12/mixer/jt12_genmix.v"
add_file -type verilog "src/jt12/mixer/jt12_interpol.v"
add_file -type verilog "src/jt89/jt89.v"
add_file -type verilog "src/jt89/jt89_mixer.v"
add_file -type verilog "src/jt89/jt89_noise.v"
add_file -type verilog "src/jt89/jt89_tone.v"
add_file -type verilog "src/jt89/jt89_vol.v"
add_file -type verilog "src/mdtang_top.sv"
add_file -type verilog "src/memory/rv_sdram_adapter.v"
add_file -type verilog "src/memory/sdram.v"
add_file -type verilog "src/peripherals/audio_iir_filter.v"
add_file -type verilog "src/peripherals/fourway.v"
add_file -type verilog "src/peripherals/gen_io.sv"
add_file -type verilog "src/peripherals/genesis_lpf.v"
add_file -type verilog "src/peripherals/lightgun.sv"
add_file -type verilog "src/peripherals/multitap.sv"
add_file -type verilog "src/peripherals/teamplayer.sv"
add_file -type verilog "src/system.sv"
add_file -type verilog "src/t80/t80.v"
add_file -type verilog "src/t80/t80_alu.v"
add_file -type verilog "src/t80/t80_mcode.v"
add_file -type verilog "src/t80/t80_reg.v"
add_file -type verilog "src/t80/t80s.v"
add_file -type verilog "src/vdp/vdp.v"
add_file -type verilog "src/vdp/vdp_common.v"
add_file -type verilog "src/vdp/vram.v"

set_option -synthesis_tool gowinsynthesis
set_option -top_module mdtang_top
set_option -include_path {"src/common"}
set_option -verilog_std sysv2017
set_option -vhdl_std vhd2008
set_option -ireg_in_iob 1
set_option -oreg_in_iob 1
set_option -ioreg_in_iob 1
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -use_cpu_as_gpio 1

# use the slower but timing-optimized place algorithm
set_option -place_option 3

run all
