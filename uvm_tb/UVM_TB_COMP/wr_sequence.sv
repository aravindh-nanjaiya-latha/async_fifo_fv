import uvm_pkg::*;
`include "uvm_macros.svh"

class wr_generator extends uvm_sequence;
`uvm_object_utils(wr_generator)

function new(string name = "wr_generator");
super.new(name);
endfunction

transaction tr;

task body;


repeat(50) begin
    tr = transaction::type_id::create("tr");
    start_item(tr); 
    assert(tr.randomize());
    finish_item(tr);
end
endtask

endclass