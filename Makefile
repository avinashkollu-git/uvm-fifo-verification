# Local self-checking testbench (Icarus Verilog, no UVM required).
# The full UVM environment lives in tb_uvm/ and runs on EDA Playground
# (see README.md), since Icarus does not support UVM.

IVERILOG ?= iverilog
VVP      ?= vvp

.PHONY: test clean

test:
	$(IVERILOG) -g2012 -o fifo_sc.vvp rtl/sync_fifo.v tb_icarus/tb_fifo_selfcheck.sv
	$(VVP) fifo_sc.vvp

clean:
	rm -f fifo_sc.vvp *.vcd
