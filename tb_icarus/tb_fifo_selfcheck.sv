// -----------------------------------------------------------------------------
// tb_fifo_selfcheck.sv : local, simulator-agnostic self-checking testbench for
//   sync_fifo. Runs on Icarus Verilog (no UVM required). It proves both the DUT
//   and the golden-model checking algorithm that the UVM scoreboard also uses.
//
//   Reference model: a SystemVerilog queue. On every accepted write the data is
//   pushed; on every accepted read the head is popped and expected to appear on
//   the DUT rd_data one clock later (the DUT registers rd_data).
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_fifo_selfcheck;

    localparam integer DATA_WIDTH = 8;
    localparam integer DEPTH      = 16;

    reg                    clk;
    reg                    rst_n;
    reg                    wr_en;
    reg  [DATA_WIDTH-1:0]  wr_data;
    reg                    rd_en;
    wire [DATA_WIDTH-1:0]  rd_data;
    wire                   full;
    wire                   empty;

    // Golden reference FIFO
    reg [DATA_WIDTH-1:0] model [$];

    // Book-keeping for the one-cycle read latency
    reg                   rd_valid_d;   // a read was accepted last cycle
    reg [DATA_WIDTH-1:0]  rd_expect_d;  // value expected on rd_data this cycle

    integer errors = 0;
    integer checks = 0;

    sync_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_en  (wr_en),
        .wr_data(wr_data),
        .rd_en  (rd_en),
        .rd_data(rd_data),
        .full   (full),
        .empty  (empty)
    );

    // 100 MHz clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Accepted-transaction detection (mirrors the DUT's internal do_write/do_read)
    wire do_write = wr_en && !full;
    wire do_read  = rd_en && !empty;

    // Reference model update + checking, sampled on the clock edge
    always @(posedge clk) begin
        if (!rst_n) begin
            model.delete();
            rd_valid_d  <= 1'b0;
            rd_expect_d <= '0;
        end else begin
            // Check the read that was accepted on the previous edge
            if (rd_valid_d) begin
                checks = checks + 1;
                if (rd_data !== rd_expect_d) begin
                    errors = errors + 1;
                    $display("[%0t] MISMATCH: rd_data=0x%02x expected=0x%02x",
                             $time, rd_data, rd_expect_d);
                end
            end

            // Update the golden model for transactions accepted on this edge
            if (do_write) model.push_back(wr_data);

            if (do_read) begin
                rd_expect_d <= model.pop_front();
                rd_valid_d  <= 1'b1;
            end else begin
                rd_valid_d  <= 1'b0;
            end
        end
    end

    // Stimulus
    integer i;
    reg [DATA_WIDTH-1:0] rnd;

    task do_reset;
        begin
            wr_en = 0; rd_en = 0; wr_data = 0;
            rst_n = 0;
            repeat (3) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task write_one(input [DATA_WIDTH-1:0] d);
        begin
            @(negedge clk); wr_en = 1; wr_data = d; rd_en = 0;
            @(negedge clk); wr_en = 0;
        end
    endtask

    task read_one;
        begin
            @(negedge clk); rd_en = 1; wr_en = 0;
            @(negedge clk); rd_en = 0;
        end
    endtask

    initial begin
        $dumpfile("tb_fifo_selfcheck.vcd");
        $dumpvars(0, tb_fifo_selfcheck);

        do_reset;

        // 1) Directed: fill completely, then drain completely (FIFO order)
        for (i = 0; i < DEPTH; i = i + 1) write_one(i[DATA_WIDTH-1:0] + 8'h10);
        if (!full) $display("[%0t] NOTE: expected full after %0d writes", $time, DEPTH);
        for (i = 0; i < DEPTH; i = i + 1) read_one;
        repeat (2) @(posedge clk);
        if (!empty) $display("[%0t] NOTE: expected empty after draining", $time);

        // 2) Randomized mixed traffic
        for (i = 0; i < 2000; i = i + 1) begin
            rnd = $random;
            @(negedge clk);
            wr_en   = $random;
            rd_en   = $random;
            wr_data = rnd;
            @(posedge clk);
        end
        @(negedge clk); wr_en = 0; rd_en = 0;

        // Drain whatever remains
        while (!empty) read_one;
        repeat (3) @(posedge clk);

        $display("--------------------------------------------------");
        $display("checks=%0d  errors=%0d", checks, errors);
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL");
        $display("--------------------------------------------------");
        $finish;
    end

endmodule
