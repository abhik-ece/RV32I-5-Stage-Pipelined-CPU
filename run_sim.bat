@echo off
if not exist sim mkdir sim
if not exist synth mkdir synth
iverilog -g2012 -Wall -s tb_rv32i_core -o sim/tb_rv32i_core.vvp rtl/rv32i_core.sv tb/tb_rv32i_core.sv
if errorlevel 1 exit /b 1
vvp sim/tb_rv32i_core.vvp
