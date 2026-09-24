import uvm_pkg::*;
`include "uvm_macros.svh"

class wr_agent extends uvm_agent;
`uvm_component_utils(wr_agent)

    driver drv;//driver of write module
    monitor mon;//monitor of write module
    uvm_sequencer#(transaction) seqr;

function new (string name = "wr_agent", uvm_component parent = null);
    super.new(name, parent);
endfunction

virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv = driver::type_id::create("drv",this);
    mon = monitor::type_id::create("mon", this);
    seqr = uvm_sequencer#(transaction)::type_id::create("seqr",this);
endfunction

virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
endfunction

endclass