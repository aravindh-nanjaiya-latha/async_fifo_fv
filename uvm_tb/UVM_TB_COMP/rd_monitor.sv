`include "uvm_macros.svh"
import uvm_pkg::*;

class rd_monitor extends uvm_monitor;
`uvm_component_utils(rd_monitor)

rd_transaction tx;
uvm_analysis_port #(rd_transaction) send;
virtual intf vif;

function new (string name = "rd_monitor", uvm_component parent = null);
    super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    tx = rd_transaction::type_id::create("tx",this);
    send = new("send",this);
    if (!uvm_config_db#(virtual intf)::get(this,"","vif",vif)) begin
        `uvm_error("rd_mon","Unable to access interface");
    end
endfunction

virtual task run_phase(uvm_phase phase);
    forever begin
        //pass the values to the scoreboard
        repeat(2) @(posedge vif.r_clk);
        tx.r_en = vif.r_en;
        tx.rrst_n = vif.rrst_n;
        tx.data_out = vif.data_out;
        tx.empty = vif.empty;
        send.write(tx); 
        `uvm_info("rd_mon", $sformatf("Sampled read: data_out=0x%0h, empty=%0d", tx.data_out, tx.empty), UVM_MEDIUM);
    end
endtask
endclass