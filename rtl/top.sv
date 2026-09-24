module top #(parameter data_width = 8) (input logic [data_width-1:0] data_in,
input logic w_en, r_en, w_clk, r_clk,wrst_n,rrst_n,
output logic full,empty,
output logic [data_width-1:0] data_out
);

logic [5:0] g_rptr_sync,b_wptr,g_rptr,g_wptr,g_wptr_sync,b_rptr;


w_ptr w_inst (.wclk(w_clk),.wrst_n(wrst_n),.g_rptr_sync(g_rptr_sync),.b_wptr(b_wptr),.g_wptr(g_wptr),.full(full),.wen(w_en));
sync sync_instW (.rst(wrst_n),.clk(w_clk),.din(g_rptr),.dout(g_rptr_sync));
sync sync_instR (.rst(rrst_n),.clk(r_clk),.din(g_wptr),.dout(g_wptr_sync));
read_ptr_handler #(.ptr_width(6)) r_inst (.rclk(r_clk),.r_en(r_en),.rrst_n(rrst_n),.g_wptr_sync(g_wptr_sync),.g_rptr(g_rptr),.b_rptr(b_rptr),.empty(empty));
fifo_mem #(.data_width(data_width),.depth(54)) f_memory_inst (.w_clk(w_clk),.r_clk(r_clk),.w_en(w_en),.r_en(r_en),.full(full),.empty(empty),.arstn(wrst_n),.data_in(data_in),.data_out(data_out),.w_ptr(b_wptr),.r_ptr(b_rptr));


endmodule