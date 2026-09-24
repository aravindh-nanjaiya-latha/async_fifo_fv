`include "uvm_macros.svh"
import uvm_pkg::*;

class rd_transaction extends uvm_sequence_item;
    `uvm_object_utils(rd_transaction)

    
    rand logic r_en;
    logic r_clk;
    logic rrst_n;
    logic empty;
    logic [7:0] data_out;

    function new (string name = "rd_transaction");
        super.new(name);
    endfunction

    constraint for_read_enable {r_en dist {1 := 70 , 0 := 30};}
endclass