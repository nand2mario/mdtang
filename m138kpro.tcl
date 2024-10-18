
add_file -type cst "src/m138k/m138kpro.cst"
add_file -type sdc "src/mdtang.sdc"
set_device GW5AST-LV138FPG676AC1/I0 -device_version B

set_option -output_base_name mdtang-m138kpro

source build.tcl
