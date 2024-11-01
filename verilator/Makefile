N=mdtang_top
D=../src
SRCS=$D/mdtang_top.sv \
	 $D/fx68k/verilator/fx68k.sv $D/fx68k/verilator/fx68kAlu.sv $D/fx68k/verilator/uaddrPla.sv \
	 $D/vdp/vdp.v $D/vdp/vdp_common.v $D/common/dpram_block.v $D/common/dpram.v \
	 $D/common/ssram.v $D/common/dpram32_block.v \
	 $D/system.sv $D/memory/sdram_sim.v $D/peripherals/multitap.sv $D/peripherals/gen_io.sv \
	 $D/peripherals/fourway.v $D/peripherals/lightgun.sv $D/peripherals/teamplayer.sv \
	 $D/jt89/jt89_mixer.v $D/jt89/jt89_noise.v $D/jt89/jt89_tone.v $D/jt89/jt89_vol.v $D/jt89/jt89.v \
	 $D/jt12/jt12.v $D/jt12/jt12_top.v $D/jt12/jt12_acc.v $D/jt12/jt12_single_acc.v $D/jt12/jt12_eg.v \
	 $D/jt12/jt12_eg_cnt.v $D/jt12/jt12_eg_comb.v $D/jt12/jt12_eg_step.v $D/jt12/jt12_eg_pure.v \
	 $D/jt12/jt12_eg_final.v $D/jt12/jt12_eg_ctrl.v $D/jt12/jt12_exprom.v $D/jt12/jt12_kon.v \
	 $D/jt12/jt12_lfo.v $D/jt12/jt12_div.v $D/jt12/jt12_mod.v $D/jt12/jt12_op.v $D/jt12/jt12_csr.v \
	 $D/jt12/jt12_pg.v $D/jt12/jt12_pg_inc.v $D/jt12/jt12_pg_dt.v $D/jt12/jt12_pg_sum.v $D/jt12/jt12_pg_comb.v \
	 $D/jt12/jt12_pm.v $D/jt12/jt12_logsin.v $D/jt12/jt12_reg.v $D/jt12/jt12_sh.v $D/jt12/jt12_sh_rst.v \
	 $D/jt12/jt12_sh24.v $D/jt12/jt12_sumch.v $D/jt12/jt12_timers.v $D/jt12/jt12_pcm_interpol.v \
	 $D/jt12/jt12_mmr.v $D/jt12/jt12_dout.v $D/jt12/jt12_rst.v $D/jt12/adpcm/jt10_adpcm_div.v \
	 $D/jt12/mixer/jt12_genmix.v $D/jt12/mixer/jt12_decim.v $D/jt12/mixer/jt12_interpol.v \
	 $D/jt12/mixer/jt12_comb.v $D/jt12/mixer/jt12_fm_uprate.v \
	 $D/peripherals/genesis_lpf.v $D/peripherals/audio_iir_filter.v \
	 $D/t80/t80_alu.v $D/t80/t80.v $D/t80/t80_mcode.v $D/t80/t80_reg.v $D/t80/t80s.v

#	 $D/tv80/tv80_alu.v $D/tv80/tv80_core.v $D/tv80/tv80_mcode.v $D/tv80/tv80_reg.v $D/tv80/tv80s.v

DEPS=
INCLUDES=-I$D -I$D/fx68k -I$D/vdp

CFLAGS_SDL=$(shell sdl2-config --cflags) -g -O2
LIBS_SDL=$(shell sdl2-config --libs) -g

.PHONY: build sim verilate clean gtkwave audio
	
build: ./obj_dir/V$N

verilate: ./obj_dir/V$N.cpp

./obj_dir/V$N.cpp: sim_main.cpp $(SRCS) $(DEPS)
	@echo
	@echo "### VERILATE ####"
	mkdir -p obj_dir
	verilator --top-module $N +1800-2023ext+sv --trace-fst -Wno-PINMISSING -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -cc --exe -CFLAGS "$(CFLAGS_SDL)" -LDFLAGS "$(LIBS_SDL)" $(INCLUDES) $(SRCS) sim_main.cpp
#	verilator --top-module $N --timing --trace-fst -Wno-WIDTH -Wno-PINMISSING -Wno-UNOPTFLAT -cc --exe -CFLAGS "$(CFLAGS_SDL)" -LDFLAGS "$(LIBS_SDL)" $(INCLUDES) $(SRCS) sim_main.cpp

./obj_dir/V$N: verilate
	@echo
	@echo "### BUILDING SIM ###"
	make -C obj_dir -f V$N.mk V$N

sim: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION (GUI) ###"
	@cd obj_dir && ./V$N -c 10000000

trace: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION (trace) ###"
	@cd obj_dir && ./V$N -t -c 5000000 2> stderr.log

gtkwave:
	gtkwave obj_dir/waveform.fst

audio:
	ffmpeg -y -f s16le -ar 48k -ac 2 -i md.aud md.wav

clean:
	rm -rf obj_dir
