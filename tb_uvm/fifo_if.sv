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
