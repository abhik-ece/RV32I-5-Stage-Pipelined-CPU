set -euo pipefail
mkdir -p sim synth
iverilog -g2012 -Wall -s tb_rv32i_core -o sim/tb_rv32i_core.vvp rtl/rv32i_core.sv tb/tb_rv32i_core.sv
vvp sim/tb_rv32i_core.vvp
