import uvm_pkg::*;
`include "uvm_macros.svh"

class monitor extends uvm_driver#(transaction);
`uvm_component_utils(monitor)

uvm_analysis_port #(transaction) wr_an_port; 

virtual intf vif;
transaction tx;

function new(string name="monitor", uvm_component parent);
super.new(name,parent);
endfunction

function void build_phase(uvm_phase phase);
super.build_phase(phase);
wr_an_port=new("wr_an_port", this);
//`uvm_info("MON", "Build phase", UVM_HIGH)

if(!uvm_config_db#(virtual intf)::get(this, "", "vif", vif)) begin
    `uvm_error("WR_MON","Failed to pass interface")
end
endfunction

task run_phase (uvm_phase phase);
super.run_phase(phase);
forever begin
    tx=transaction::type_id::create("tx");
    tx.w_en=vif.w_en;
    tx.data_in=vif.data_in;
    tx.wrst_n=vif.wrst_n;
    tx.full=vif.full;
//    tx.empty=vif.empty;
    wr_an_port.write(tx);
    repeat(2) @(posedge vif.w_clk);

end
endtask
endclass