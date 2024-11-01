
## MDTang simulation suite

This directory contains a verilator-based RTL simulator for MDTang.

You can run the simulation as follows,

```
make
ln -s obj_dir/Vmdtang_top sim
ln -s ../src/fx68k/*.mem .
./sim hello.bin
```

You can replace `hello.bin` with any game rom or test rom. Then follow instructions printed by the simulator for gamepad input, tracing and etc.

You can also get sound output with `make audio`.