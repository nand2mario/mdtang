
add_file -type cst "src/m138k/m138k.cst"
add_file -type sdc "src/mdtang.sdc"
set_device GW5AT-LV60PG484AC1/I0 -device_version B

set_option -output_base_name mdtang-m60k

source build.tcl

