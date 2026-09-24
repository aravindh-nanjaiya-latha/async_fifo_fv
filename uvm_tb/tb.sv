module tb;

parameter data_width = 8;

logic [data_width-1:0] data_in;
logic w_en, r_en, w_clk, r_clk,wrst_n,rrst_n;
logic full,empty;
logic [data_width-1:0] data_out;

top #(.data_width(data_width)) DUT (.*);

always #12.5 w_clk = ~w_clk;
always #20 r_clk = ~r_clk;

initial begin
wrst_n = 0;
rrst_n = 0;
w_en = 0;
r_en = 0;
data_in = '0;
w_clk = 0;
r_clk = 0;
end

initial begin
#50;
wrst_n = 1;
rrst_n = 1;
w_en = 1;
#20;
repeat(60) begin
data_in = $urandom_range(0,10);
@(posedge w_clk);
end
//w_en = 0;
#20;


end

initial begin
#50;
r_en = 1;
#1000;
r_en = 0;
#2000;
$stop();
end

initial begin
#1020;
$display("wptr = %d and data in fifo = %d",DUT.w_inst.b_wptr,DUT.f_memory_inst.f_mem[34]);
end

/*
initial begin
$monitor($time, "wrst = %0d, rrst = %0d, w_en = %0d, r_en = %0d, data_in = %0d, data_out = %0d, full = %0d and empty = %0d, wptr = %d and rptr = %d, g_rptr_nxt = %b, g_wptr_sync = %b",wrst_n,rrst_n,w_en,r_en,data_in,data_out,full,empty,DUT.w_inst.b_wptr, DUT.r_inst.b_rptr,DUT.r_inst.g_rptr,DUT.r_inst.g_wptr_sync);
end
*/

always @(posedge w_clk) $display($time, "[W_CLk] wrst = %0d, rrst = %0d, w_en = %0d, r_en = %0d, data_in = %0d, data_out = %0d, full = %0d and empty = %0d, wptr = %d and rptr = %d, g_rptr_nxt = %b, g_wptr_sync = %b",wrst_n,rrst_n,w_en,r_en,data_in,data_out,full,empty,DUT.w_inst.b_wptr, DUT.r_inst.b_rptr,DUT.r_inst.g_rptr_next,DUT.r_inst.g_wptr_sync);
always @(posedge r_clk) $display($time, "[R_CLk] wrst = %0d, rrst = %0d, w_en = %0d, r_en = %0d, data_in = %0d, data_out = %0d, full = %0d and empty = %0d, wptr = %d and rptr = %d, g_rptr_nxt = %b, g_wptr_sync = %b",wrst_n,rrst_n,w_en,r_en,data_in,data_out,full,empty,DUT.w_inst.b_wptr, DUT.r_inst.b_rptr,DUT.r_inst.g_rptr_next,DUT.r_inst.g_wptr_sync);

endmodule