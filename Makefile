# Two ways to verify this design:
#   make test  -> local self-checking testbench on Icarus Verilog (no UVM)
#   make uvm   -> the full UVM environment on Verilator + Accellera UVM
#
# The UVM flow needs: verilator, the Accellera uvm-core source (UVM_HOME),
# and the z3 solver on PATH (for constrained randomization).

IVERILOG ?= iverilog
VVP      ?= vvp
VERILATOR ?= verilator
UVM_HOME  ?= $(HOME)/developer/oss/uvm-core/src

.PHONY: test uvm clean

test:
	$(IVERILOG) -g2012 -o fifo_sc.vvp rtl/sync_fifo.v tb_icarus/tb_fifo_selfcheck.sv
	$(VVP) fifo_sc.vvp

uvm:
	$(VERILATOR) --binary --timing -Wno-fatal -Wno-lint --build-jobs 8 \
	  +define+UVM_NO_DPI +define+UVM_NO_DEPRECATED \
	  +incdir+$(UVM_HOME) -sv $(UVM_HOME)/uvm_pkg.sv \
	  rtl/sync_fifo.v tb_uvm/fifo_if.sv tb_uvm/fifo_pkg.sv tb_uvm/tb_top.sv \
	  --top-module tb_top -o fifo_uvm_sim
	VERILATOR_SOLVER="z3 --in" ./obj_dir/fifo_uvm_sim +UVM_TESTNAME=fifo_test +UVM_NO_RELNOTES

clean:
	rm -f fifo_sc.vvp *.vcd build.log
	rm -rf obj_dir
