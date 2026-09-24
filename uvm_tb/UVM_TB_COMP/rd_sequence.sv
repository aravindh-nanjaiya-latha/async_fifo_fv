`include "uvm_macros.svh"
import uvm_pkg::*;

class rd_seq extends uvm_sequence#(rd_transaction);
    `uvm_object_utils(rd_seq)

    int num = 45;

    function new (string name = "rd_seq");
        super.new(name);
    endfunction

    virtual task body();
        rd_transaction   tx;
        repeat(num) begin
            tx = rd_transaction::type_id::create("tx");
            start_item(tx);
            if(!tx.randomize()) `uvm_error("rd_seq","Transaction not randomized");
            finish_item(tx);
        end 
    endtask
    
endclass