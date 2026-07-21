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
