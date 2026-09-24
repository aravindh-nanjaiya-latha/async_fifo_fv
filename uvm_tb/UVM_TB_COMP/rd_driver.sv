`include "uvm_macros.svh"
//`include "rd_seq_item.sv"
//`include "Interface.sv"
import uvm_pkg::*;

class rd_drv extends uvm_driver#(rd_transaction );
    `uvm_component_utils(rd_drv)

    rd_transaction tx;
    virtual intf vif;

    function new(string name = "rd_drv",uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        tx = rd_transaction::type_id::create("tx",this);
        if(!uvm_config_db#(virtual intf)::get(this,"","vif",vif)) begin
            `uvm_error("rd_drv","Unable to connect to interface");
        end
    endfunction

    virtual task run_phase(uvm_phase phase);
        reset();
        forever begin
        seq_item_port.get_next_item(tx);
        //all the signals from transaction

        //@(posedge vif.r_clk);
        vif.r_en <= tx.r_en;
        vif.rrst_n <= tx.rrst_n;
        `uvm_info("rd_drv",$sformatf("Data sent to DUT r_en = %0d, rrst_n = %0d",tx.r_en,tx.rrst_n),UVM_MEDIUM);
        seq_item_port.item_done();
        repeat(2) @(posedge vif.r_clk);
        end
    endtask

    virtual task reset();
        vif.rrst_n <= 0;
        vif.r_en <= 0;
        repeat(2) @(posedge vif.r_clk);
        vif.rrst_n <= 1;
        vif.r_en <= 1;
        `uvm_info("rd_drv","Reset Done",UVM_NONE);
    endtask

endclass