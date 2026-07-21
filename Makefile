# Three ways to verify this design:
#   make test   -> self-checking testbench on Icarus Verilog (no UVM)
#   make uvm    -> the full UVM environment on Verilator + Accellera UVM
#   make formal -> formal property proof with Yosys + yosys-smtbmc + z3
#
# The UVM flow needs verilator, the Accellera uvm-core source (UVM_HOME), and
# the z3 solver on PATH. The formal flow needs yosys, yosys-smtbmc, and z3.

IVERILOG ?= iverilog
VVP      ?= vvp
VERILATOR ?= verilator
YOSYS     ?= yosys
SMTBMC    ?= yosys-smtbmc
UVM_HOME  ?= $(HOME)/developer/oss/uvm-core/src
FORMAL_DEPTH ?= 20

.PHONY: test uvm formal clean

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

formal:
	mkdir -p formal
	$(YOSYS) -q -p "read_verilog -sv -DFORMAL rtl/sync_fifo.v; \
	                prep -top sync_fifo -nordff; \
	                write_smt2 -wires formal/sync_fifo.smt2"
	@echo "--- BMC ---"
	$(SMTBMC) -s z3 -t $(FORMAL_DEPTH) formal/sync_fifo.smt2
	@echo "--- temporal induction ---"
	$(SMTBMC) -s z3 -i -t $(FORMAL_DEPTH) formal/sync_fifo.smt2
	@echo "--- cover (reachability) ---"
	$(SMTBMC) -s z3 -c -t $(FORMAL_DEPTH) formal/sync_fifo.smt2

clean:
	rm -f fifo_sc.vvp *.vcd build.log
	rm -rf obj_dir formal/sync_fifo.smt2
