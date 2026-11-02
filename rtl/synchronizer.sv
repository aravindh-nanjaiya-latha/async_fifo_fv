//module for synchronizer


// BUG FIX 1: Synchronizer reset value was set to 0. But the pointers of fifo is set from binary=9 to binary=54.
// During reset window - g_wptr_sync is reset to 6'b0. Which is compared to g_rptr_next in the read side. Since they are not equal after reset empty is deasserted when it is not supposed to be.
// This was found in the FPV using Jasper with the property - chk_fv_empty_when_occ_zero

//FIXED by adding parameter to the synchronizer. Since both read and write side uses the same synchronizer at their instance we cannot hard code it here.

module sync #(parameter [5:0] RST_VAL = 6'b000000)
(input logic rst, clk, 
input logic [5:0] din, 
output logic [5:0] dout);
logic [5:0] q1;
always_ff @(posedge clk or negedge rst) begin
    if(!rst) begin
        dout<=RST_VAL; //initially set to =0. fixed to RST_VAL
        q1<=RST_VAL; //initially set to =0. fixed to RST_VAL
    end
    else begin
        q1<=din;
        dout<=q1;
    end
end
endmodule
 
