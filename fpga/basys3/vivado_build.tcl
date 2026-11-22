set design_name "presenter"
set board_name "basys3"
set fpga_part "xc7a35tcpg236-1"

set src_dir [file normalize "../../src"]

read_verilog -sv "${src_dir}/hvsync_generator.v"
read_verilog -sv "${src_dir}/qspi.sv"
read_verilog -sv "${src_dir}/project.v"
read_verilog -sv "pll.sv"
read_verilog -sv "delay.sv"
read_verilog -sv "fpga_top.sv"

read_xdc "${board_name}.xdc"

synth_design -top "fpga_top" -part "${fpga_part}"

opt_design
place_design
route_design

write_bitstream -force "${design_name}.bit"

