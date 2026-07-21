// -----------------------------------------------------------------------------
// sync_fifo.v : single-clock (synchronous) FIFO.
//   Depth must be a power of two. full/empty use an extra wrap bit on the
//   read/write pointers so the buffer can hold all DEPTH entries.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module sync_fifo #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH      = 16      // must be a power of two
) (
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire                   wr_en,
    input  wire [DATA_WIDTH-1:0]  wr_data,
    input  wire                   rd_en,
    output reg  [DATA_WIDTH-1:0]  rd_data,
    output wire                   full,
    output wire                   empty
);
    localparam integer ADDR_W = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_W:0]       wr_ptr;   // extra MSB is the wrap bit
    reg [ADDR_W:0]       rd_ptr;

    wire do_write = wr_en && !full;
    wire do_read  = rd_en && !empty;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (do_write) begin
            mem[wr_ptr[ADDR_W-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr  <= 0;
            rd_data <= 0;
        end else if (do_read) begin
            rd_data <= mem[rd_ptr[ADDR_W-1:0]];
            rd_ptr  <= rd_ptr + 1'b1;
        end
    end

    // empty when pointers fully equal; full when addresses equal but wrap bits differ.
    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[ADDR_W] != rd_ptr[ADDR_W]) &&
                   (wr_ptr[ADDR_W-1:0] == rd_ptr[ADDR_W-1:0]);

// -----------------------------------------------------------------------------
// Formal properties. Compiled only when FORMAL is defined, so simulation runs
// (Icarus, Verilator/UVM) are unaffected. Proven with Yosys + yosys-smtbmc + z3.
// -----------------------------------------------------------------------------
`ifdef FORMAL
    // Number of entries currently held. The extra wrap bit makes this subtraction
    // give the true occupancy (0 .. DEPTH).
    wire [ADDR_W:0] f_count = wr_ptr - rd_ptr;

    // Only start checking once we have a previous cycle to reason about.
    reg f_past_valid = 1'b0;
    always @(posedge clk) f_past_valid <= 1'b1;

    always @(posedge clk) begin
        if (f_past_valid && rst_n) begin
            // 1. full and empty are mutually exclusive.
            assert (!(full && empty));

            // 2. Occupancy never exceeds DEPTH (no overflow) and, being unsigned,
            //    never wraps below zero (no underflow).
            assert (f_count <= DEPTH[ADDR_W:0]);

            // 3. The flags exactly describe the occupancy.
            assert (full  == (f_count == DEPTH[ADDR_W:0]));
            assert (empty == (f_count == 0));

            // 4. A write is only accepted when not full; a read only when not empty.
            if ($past(rst_n)) begin
                if ($past(full))  assert (wr_ptr == $past(wr_ptr) || $past(!wr_en));
                if ($past(empty)) assert (rd_ptr == $past(rd_ptr));
            end
        end
    end

    // Reachability: prove these states are actually attainable, so the
    // assertions above are not vacuously true.
    always @(posedge clk) begin
        if (f_past_valid && rst_n) begin
            cover (full);
            cover (empty && $past(!empty));
        end
    end
`endif

endmodule

`default_nettype wire
