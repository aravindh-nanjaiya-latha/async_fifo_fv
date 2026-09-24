import uvm_pkg::*;
`include "uvm_macros.svh"

class transaction extends uvm_sequence_item;
`uvm_object_utils(transaction)

rand logic [7:0] data_in;
rand logic w_en;
logic wrst_n;
logic full;

function new(string name = "transaction");
super.new(name);
endfunction

constraint for_data{
    data_in inside {[0:100]};
}

constraint for_wen{
    w_en dist {1:=80 , 0:= 20};
}

endclass