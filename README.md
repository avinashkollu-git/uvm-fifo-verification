# UVM Verification: Synchronous FIFO

A complete **UVM** (Universal Verification Methodology) testbench for a
synchronous FIFO, plus a local self-checking testbench that runs on open-source
tools. The environment is a standard, layered UVM setup: sequence, sequencer,
driver, monitor, agent, scoreboard, environment, and test, with a virtual
interface and clocking blocks for race-free driving and sampling.

## Design under test

`rtl/sync_fifo.v` is a parameterized single-clock FIFO (`DATA_WIDTH`, `DEPTH`).
It uses read and write pointers with an extra wrap bit so the buffer can hold all
`DEPTH` entries, and it registers `rd_data`, so read data appears one clock after
an accepted read.

## Verification architecture

```
                      +-------------------- fifo_env ---------------------+
                      |                                                   |
   fifo_random_seq -->| sequencer --> driver --> [ virtual interface ] -->| DUT
                      |                                  |                 |
                      |                               monitor --> analysis |
                      |                                  |                 |
                      |                            fifo_scoreboard         |
                      |                       (golden queue reference)     |
                      +---------------------------------------------------+
```

- **Sequence item** (`fifo_seq_item`): randomized `wr_en`, `rd_en`, `wr_data`,
  with distribution constraints that keep the FIFO active.
- **Driver**: drives one transaction per clock through the `drv_cb` clocking
  block, and idles during reset.
- **Monitor**: samples the interface through the `mon_cb` clocking block and
  broadcasts every accepted write and read. Read data is captured one clock
  after a read is accepted, matching the registered output.
- **Scoreboard**: a golden reference queue. Every accepted write is pushed; every
  accepted read pops the head and is compared against the observed `rd_data`.
  Reports total checks and errors, and PASS or FAIL, in `report_phase`.

## Checking model

The scoreboard models the FIFO as a queue and enforces first-in first-out order
and data integrity, accounting for the one-cycle read latency of the registered
output. This is the same algorithm proven by the local testbench below.

## Running the UVM environment (EDA Playground, free)

Icarus Verilog does not support UVM, so the UVM environment is run on
[EDA Playground](https://www.edaplayground.com), which provides free
UVM-capable simulators.

1. Open EDA Playground and sign in (free).
2. Left pane, set **UVM/OVM** to **UVM 1.2**, and pick a simulator such as
   **Aldec Riviera-PRO** or **Synopsys VCS**.
3. Add these files (Testbench + Design panes):
   - `rtl/sync_fifo.v`
   - `tb_uvm/fifo_if.sv`
   - `tb_uvm/fifo_pkg.sv`
   - `tb_uvm/tb_top.sv`
4. Set the top module to `tb_top` and add the run option `+UVM_TESTNAME=fifo_test`.
5. Run. Expected result in the log:
   ```
   UVM_INFO ... [SCB] checks=... errors=0
   UVM_INFO ... [SCB] RESULT: PASS
   ```

## Running the local self-checking testbench (Icarus, no UVM)

The local testbench proves both the DUT and the golden-model checking algorithm
using open-source tools only:

```
make test
```

Expected output:

```
checks=1020  errors=0
RESULT: PASS
```

## Files

```
uvm-fifo-verification/
|-- rtl/sync_fifo.v                 DUT
|-- tb_uvm/fifo_if.sv               virtual interface + clocking blocks
|-- tb_uvm/fifo_pkg.sv              full UVM environment (all components)
|-- tb_uvm/tb_top.sv               UVM top: DUT, clock/reset, run_test
|-- tb_icarus/tb_fifo_selfcheck.sv local self-checking testbench (Icarus)
|-- Makefile                        local build/run
`-- README.md
```

## Notes

The local testbench is verified on Icarus Verilog 13.0. The UVM environment is
written for UVM 1.2 and intended to be run on a UVM-capable simulator via EDA
Playground; the scoreboard uses the same reference-queue algorithm proven
locally.
