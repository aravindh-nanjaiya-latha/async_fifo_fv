`include "uvm_macros.svh"
import uvm_pkg::*;

`include "Interface.sv"
`include "transaction.sv"
`include "wr_sequence.sv"
`include "wr_driver.sv"
`include "wr_monitor.sv"
`include "wr_agent.sv"
`include "rd_seq_item.sv"
`include "rd_sequence.sv"
`include "rd_driver.sv"
`include "rd_monitor.sv"
`include "rd_agent.sv"
`include "scoreboard.sv"
`include "environment.sv"
`include "test.sv"


module uvm_afifo_top;

intf vif();

top #(.data_width(8)) DUT (.data_in(vif.data_in),.w_en(vif.w_en),.r_en(vif.r_en),.w_clk(vif.w_clk),.r_clk(vif.r_clk)
,.wrst_n(vif.wrst_n),.rrst_n(vif.rrst_n),.full(vif.full),.empty(vif.empty),.data_out(vif.data_out)
);

//clock_wr
//clock_rd
always #12.5 vif.w_clk = ~vif.w_clk;
always #20 vif.r_clk = ~vif.r_clk;

initial begin
uvm_config_db#(virtual intf)::set(null,"*","vif",vif);
end

initial begin
vif.w_clk = 1;
vif.r_clk = 1;
end

initial begin
run_test("test");
end

initial begin
#5000;
$stop();
end



endmodule

