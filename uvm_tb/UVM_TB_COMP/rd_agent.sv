`include "uvm_macros.svh"
import uvm_pkg::*;
//`include "rd_driver.sv"
//`include "rd_monitor.sv"
//`include "rd_seq_item.sv"

class rd_agent extends uvm_agent;
    `uvm_component_utils(rd_agent)

    rd_drv d;
    rd_monitor m;
    uvm_sequencer#(rd_transaction ) rd_seqr;

    function new(string name = "rd_agent", uvm_component parent=null);
        super.new(name,parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        d=rd_drv::type_id::create("d",this);
        m=rd_monitor::type_id::create("m",this);
        rd_seqr = uvm_sequencer#(rd_transaction)::type_id::create("rd_seqr",this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        d.seq_item_port.connect(rd_seqr.seq_item_export);
    endfunction

endclass