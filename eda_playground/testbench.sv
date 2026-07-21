// ============================================================
// EDA Playground TESTBENCH pane.
// Contains: fifo_if (interface) + fifo_pkg (UVM env) + tb_top.
// Design pane must contain design.sv (the sync_fifo DUT).
// Left panel: UVM/OVM = UVM 1.2 ; Simulator = Aldec Riviera-PRO.
// ============================================================

// -----------------------------------------------------------------------------
// fifo_if.sv : virtual interface for the sync_fifo UVM testbench.
//   Clocking blocks make driving and sampling race-free:
//     - drv_cb drives stimulus with a small output skew.
//     - mon_cb samples with input #1step, so the monitor sees the settled
//       (pre-edge) values, matching the DUT's registered behaviour.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

interface fifo_if #(parameter int DATA_WIDTH = 8)
                   (input logic clk, input logic rst_n);

    logic                    wr_en;
    logic                    rd_en;
    logic [DATA_WIDTH-1:0]   wr_data;
    logic [DATA_WIDTH-1:0]   rd_data;
    logic                    full;
    logic                    empty;

    // Driver clocking block
    clocking drv_cb @(posedge clk);
        default input #1step output #1;
        output wr_en, rd_en, wr_data;
        input  full, empty;
    endclocking

    // Monitor clocking block (all inputs, sampled just before the edge)
    clocking mon_cb @(posedge clk);
        default input #1step;
        input wr_en, rd_en, wr_data, rd_data, full, empty;
    endclocking

endinterface

// -----------------------------------------------------------------------------
// fifo_pkg.sv : complete UVM verification environment for sync_fifo.
//   Components: sequence item, sequence, sequencer, driver, monitor, agent,
//   scoreboard, env, and test. DATA_WIDTH is fixed at 8 to keep the class
//   library non-parameterized (typical for a focused block-level environment).
//
//   Checking model (in the scoreboard): a reference queue. Every accepted write
//   pushes its data; every accepted read pops the head and compares it against
//   the rd_data the DUT presents one clock later (the DUT registers rd_data).
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

package fifo_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    localparam int DW = 8;

    typedef enum { OP_WRITE, OP_READ } fifo_op_e;

    // -------------------------------------------------------------------------
    // Sequence item
    // -------------------------------------------------------------------------
    class fifo_seq_item extends uvm_sequence_item;
        rand bit          wr_en;
        rand bit          rd_en;
        rand bit [DW-1:0] wr_data;

        // Populated by the monitor when it broadcasts an observed transaction
        fifo_op_e         op;
        bit [DW-1:0]      data;

        `uvm_object_utils_begin(fifo_seq_item)
            `uvm_field_int(wr_en,   UVM_ALL_ON)
            `uvm_field_int(rd_en,   UVM_ALL_ON)
            `uvm_field_int(wr_data, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "fifo_seq_item");
            super.new(name);
        endfunction

        // Bias toward keeping the FIFO active without deadlocking on one op
        constraint c_activity { wr_en dist {1 := 3, 0 := 1};
                                rd_en dist {1 := 2, 0 := 1}; }
    endclass

    // -------------------------------------------------------------------------
    // Sequence : random mixed read/write traffic
    // -------------------------------------------------------------------------
    class fifo_random_seq extends uvm_sequence #(fifo_seq_item);
        `uvm_object_utils(fifo_random_seq)

        int unsigned num_items = 2000;

        function new(string name = "fifo_random_seq");
            super.new(name);
        endfunction

        task body();
            fifo_seq_item req;
            repeat (num_items) begin
                req = fifo_seq_item::type_id::create("req");
                start_item(req);
                if (!req.randomize())
                    `uvm_error("SEQ", "randomize failed")
                finish_item(req);
            end
        endtask
    endclass

    // -------------------------------------------------------------------------
    // Sequencer
    // -------------------------------------------------------------------------
    typedef uvm_sequencer #(fifo_seq_item) fifo_sequencer;

    // -------------------------------------------------------------------------
    // Driver
    // -------------------------------------------------------------------------
    class fifo_driver extends uvm_driver #(fifo_seq_item);
        `uvm_component_utils(fifo_driver)

        virtual fifo_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual fifo_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "virtual interface not set")
        endfunction

        task run_phase(uvm_phase phase);
            // Idle during reset
            vif.drv_cb.wr_en   <= 1'b0;
            vif.drv_cb.rd_en   <= 1'b0;
            vif.drv_cb.wr_data <= '0;
            forever begin
                seq_item_port.get_next_item(req);
                @(vif.drv_cb);
                if (vif.rst_n) begin
                    vif.drv_cb.wr_en   <= req.wr_en;
                    vif.drv_cb.rd_en   <= req.rd_en;
                    vif.drv_cb.wr_data <= req.wr_data;
                end else begin
                    vif.drv_cb.wr_en <= 1'b0;
                    vif.drv_cb.rd_en <= 1'b0;
                end
                seq_item_port.item_done();
            end
        endtask
    endclass

    // -------------------------------------------------------------------------
    // Monitor : broadcasts accepted writes and reads (rd_data captured one
    //           clock after a read is accepted, matching the registered output)
    // -------------------------------------------------------------------------
    class fifo_monitor extends uvm_monitor;
        `uvm_component_utils(fifo_monitor)

        virtual fifo_if vif;
        uvm_analysis_port #(fifo_seq_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual fifo_if)::get(this, "", "vif", vif))
                `uvm_fatal("MON", "virtual interface not set")
        endfunction

        task run_phase(uvm_phase phase);
            fifo_seq_item obs;
            bit pending_read = 1'b0;
            forever begin
                @(vif.mon_cb);
                if (!vif.rst_n) begin
                    pending_read = 1'b0;
                    continue;
                end
                // A read accepted last clock: rd_data is valid now
                if (pending_read) begin
                    obs      = fifo_seq_item::type_id::create("obs_rd");
                    obs.op   = OP_READ;
                    obs.data = vif.mon_cb.rd_data;
                    ap.write(obs);
                    pending_read = 1'b0;
                end
                // Accepted write this clock
                if (vif.mon_cb.wr_en && !vif.mon_cb.full) begin
                    obs      = fifo_seq_item::type_id::create("obs_wr");
                    obs.op   = OP_WRITE;
                    obs.data = vif.mon_cb.wr_data;
                    ap.write(obs);
                end
                // Accepted read this clock: capture rd_data next clock
                if (vif.mon_cb.rd_en && !vif.mon_cb.empty)
                    pending_read = 1'b1;
            end
        endtask
    endclass

    // -------------------------------------------------------------------------
    // Agent
    // -------------------------------------------------------------------------
    class fifo_agent extends uvm_agent;
        `uvm_component_utils(fifo_agent)

        fifo_sequencer sequencer;
        fifo_driver    driver;
        fifo_monitor   monitor;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sequencer = fifo_sequencer::type_id::create("sequencer", this);
            driver    = fifo_driver::type_id::create("driver", this);
            monitor   = fifo_monitor::type_id::create("monitor", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    // -------------------------------------------------------------------------
    // Scoreboard : golden queue reference model
    // -------------------------------------------------------------------------
    `uvm_analysis_imp_decl(_fifo)

    class fifo_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(fifo_scoreboard)

        uvm_analysis_imp_fifo #(fifo_seq_item, fifo_scoreboard) ap_imp;

        bit [DW-1:0] model[$];
        int unsigned checks = 0;
        int unsigned errors = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap_imp = new("ap_imp", this);
        endfunction

        function void write_fifo(fifo_seq_item t);
            bit [DW-1:0] expected;
            if (t.op == OP_WRITE) begin
                model.push_back(t.data);
            end else begin // OP_READ
                if (model.size() == 0) begin
                    errors++;
                    `uvm_error("SCB", "read observed but reference model is empty")
                    return;
                end
                expected = model.pop_front();
                checks++;
                if (t.data !== expected)
                    begin
                        errors++;
                        `uvm_error("SCB", $sformatf(
                            "MISMATCH: rd_data=0x%02x expected=0x%02x",
                            t.data, expected))
                    end
            end
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("SCB", $sformatf("checks=%0d errors=%0d", checks, errors),
                      UVM_LOW)
            if (errors == 0)
                `uvm_info("SCB", "RESULT: PASS", UVM_LOW)
            else
                `uvm_error("SCB", "RESULT: FAIL")
        endfunction
    endclass

    // -------------------------------------------------------------------------
    // Environment
    // -------------------------------------------------------------------------
    class fifo_env extends uvm_env;
        `uvm_component_utils(fifo_env)

        fifo_agent      agent;
        fifo_scoreboard scoreboard;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent      = fifo_agent::type_id::create("agent", this);
            scoreboard = fifo_scoreboard::type_id::create("scoreboard", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agent.monitor.ap.connect(scoreboard.ap_imp);
        endfunction
    endclass

    // -------------------------------------------------------------------------
    // Test
    // -------------------------------------------------------------------------
    class fifo_test extends uvm_test;
        `uvm_component_utils(fifo_test)

        fifo_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = fifo_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            fifo_random_seq seq;
            phase.raise_objection(this);
            #50;  // let reset deassert
            seq = fifo_random_seq::type_id::create("seq");
            seq.start(env.agent.sequencer);
            #200; // allow the final reads to drain through the monitor
            phase.drop_objection(this);
        endtask
    endclass

endpackage

// -----------------------------------------------------------------------------
// tb_top.sv : UVM top module. Instantiates the DUT and interface, generates the
//   clock and reset, publishes the virtual interface, and starts the test.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import fifo_pkg::*;

    localparam int DATA_WIDTH = 8;
    localparam int DEPTH      = 16;

    logic clk;
    logic rst_n;

    // 100 MHz clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Reset: active low for a few cycles
    initial begin
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    fifo_if #(.DATA_WIDTH(DATA_WIDTH)) vif (.clk(clk), .rst_n(rst_n));

    sync_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_en  (vif.wr_en),
        .wr_data(vif.wr_data),
        .rd_en  (vif.rd_en),
        .rd_data(vif.rd_data),
        .full   (vif.full),
        .empty  (vif.empty)
    );

    initial begin
        uvm_config_db #(virtual fifo_if)::set(null, "*", "vif", vif);
        run_test("fifo_test");
    end

    // Waveform dump (EDA Playground picks this up)
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
