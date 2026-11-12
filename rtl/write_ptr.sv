// Write pointer module for FIFO with depth = 45 (binary range 9 → 54)
module w_ptr (
    input  logic        wclk,       // write clock
    input  logic        wrst_n,     // active low reset
    input  logic        wen,        // write enable
    input  logic [5:0]  g_rptr_sync,// read pointer synchronized (Gray)
    output logic [5:0]  b_wptr,     // binary write pointer
    output logic [5:0]  g_wptr,     // gray write pointer
    output logic        full        // FIFO full flag
);

    logic [5:0] b_wptr_next;
    logic [5:0] b_rptr_sync;

    //========================================================
    // Convert Gray read pointer -> Binary (for comparison)
    //========================================================
    assign b_rptr_sync[5] = g_rptr_sync[5];
    assign b_rptr_sync[4] = g_rptr_sync[4] ^ b_rptr_sync[5];
    assign b_rptr_sync[3] = g_rptr_sync[3] ^ b_rptr_sync[4];
    assign b_rptr_sync[2] = g_rptr_sync[2] ^ b_rptr_sync[3];
    assign b_rptr_sync[1] = g_rptr_sync[1] ^ b_rptr_sync[2];
    assign b_rptr_sync[0] = g_rptr_sync[0] ^ b_rptr_sync[1];

    //========================================================
    // Next binary write pointer with wrap-around at 54 → 9
    //========================================================
    always_comb begin
        if (b_wptr == 6'd54)
            b_wptr_next = 6'd9;
        else
            b_wptr_next = b_wptr + 6'd1;
    end

    //========================================================
    // Write pointer update
    //========================================================
    // BUG FIX 6: g_wptr was combinational (assign g_wptr = b_wptr ^ (b_wptr >> 1)) and fed
    // the read-side synchroniser directly, so the crossing launched from the BINARY register
    // through XOR logic: a multi-bit binary step can glitch into sync_instR.q1.
    // Found by the Jasper CDC app (CDC_PR_LOGC, visible with fifo_detection=false).
    // FIXED by registering the gray pointer, as read_ptr.sv already does for g_rptr.
    logic [5:0] g_wptr_next;
    assign g_wptr_next = b_wptr_next ^ (b_wptr_next >> 1);

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            b_wptr <= 6'd9;        // start at 9 after reset
            g_wptr <= 6'b001101;   // gray(9)
        end
        else if (wen && !full) begin
            b_wptr <= b_wptr_next;
            g_wptr <= g_wptr_next;
        end
    end

    //========================================================
    // Full condition:
    // FIFO full if next write pointer equals synchronized read pointer
    //========================================================
    assign full = (b_wptr_next == b_rptr_sync);

    //========================================================
    // Assertion to check full flag consistency
    //========================================================
    always_ff @(posedge wclk) begin
        if (wrst_n) begin
            assert (full == (b_wptr_next == b_rptr_sync))
                else $error("FULL failed -> b_rptr_sync=%b, b_wptr=%b, b_wptr_next=%b, full=%b",
                            b_rptr_sync, b_wptr, b_wptr_next, full);
        end
    end

endmodule
