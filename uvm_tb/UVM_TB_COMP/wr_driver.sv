import uvm_pkg::*;
`include "uvm_macros.svh"

class driver extends uvm_driver#(transaction);
`uvm_component_utils(driver)

virtual intf vif;
transaction tr;

function new(string name="driver", uvm_component parent);
super.new(name,parent);
endfunction

function void build_phase(uvm_phase phase);
super.build_phase(phase);
`uvm_info("Driver", "Build phase", UVM_HIGH)

if(!uvm_config_db#(virtual intf)::get(this, "", "vif", vif)) begin
    `uvm_error("Driver","Failed to pass interface")
end
endfunction

task run_phase (uvm_phase phase);
super.run_phase(phase);
w_reset;
forever begin
    tr=transaction::type_id::create("tr");
    seq_item_port.get_next_item(tr);
    vif.w_en<=tr.w_en;
    vif.data_in<=tr.data_in;
    seq_item_port.item_done();
end

endtask

task w_reset;
vif.wrst_n<=0;
vif.w_en<=0;
repeat(2) @(posedge vif.w_clk);
vif.wrst_n<=1;
endtask
endclass