`include "uvm_macros.svh"
import uvm_pkg::*;

class env extends uvm_env;
    `uvm_component_utils(env)

    wr_agent wr_a;
    scb s;
    rd_agent rd_a;

    function new (string name = "env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        wr_a = wr_agent::type_id::create("wr_a",this);
        s = scb::type_id::create("s",this);
        rd_a = rd_agent::type_id::create("rd_a",this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        wr_a.mon.wr_an_port.connect(s.wr_port);
        rd_a.m.send.connect(s.rd_port);
    endfunction

endclass