// code written by ragha, maithu, Aravindh

`uvm_analysis_imp_decl(_wr)
`uvm_analysis_imp_decl(_rd)
`include "uvm_macros.svh"
import uvm_pkg::*;

class scb extends uvm_scoreboard;
    `uvm_component_utils(scb)

    uvm_analysis_imp_wr #(transaction, scb) wr_port;
    uvm_analysis_imp_rd #(rd_transaction, scb) rd_port;

    transaction wr_transactions [$]; //Queue to store incoming write transactions
    rd_transaction rd_transactions [$]; //Queue to store incoming read transactions

    function new (string name = "scb",uvm_component parent = null);
        super.new(name,parent);
    endfunction

    virtual function void build_phase (uvm_phase phase);
        super.build_phase(phase);
        wr_port = new("wr_port",this);
        rd_port = new("rd_port",this);
    endfunction

    virtual function void write_wr(transaction wr_tr);
    wr_transactions.push_back(wr_tr);
    endfunction

    virtual function void write_rd(rd_transaction rd_tr);
    rd_transactions.push_back(rd_tr);
    endfunction

    virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    
    forever begin
    transaction curr_wr_tr;
    rd_transaction curr_rd_tr;
    if(wr_transactions.size()>0 && rd_transactions.size()>0) begin
    curr_wr_tr = wr_transactions.pop_front();
    curr_rd_tr = rd_transactions.pop_front();
    compare(curr_wr_tr,curr_rd_tr);
    end
    else begin
        @(wr_transactions.size() or rd_transactions.size());
    end
/*
    if(curr_rd_tr.r_en) begin
    compare(curr_wr_tr,curr_rd_tr);
    end
    else begin
    `uvm_info("scb",$sformatf("R_En is disabled"),UVM_MEDIUM);
    end
    
*/

end
    endtask

    task compare(transaction wr_tr, rd_transaction rd_tr);
    

    //compare logic
    if (wr_tr.data_in == rd_tr.data_out) begin
        `uvm_info("scb",$sformatf("FIFO PASS - Write_Transaction = %d, Read Transaction = %d",wr_tr.data_in,rd_tr.data_out),UVM_MEDIUM);
    end else begin
        `uvm_info("scb",$sformatf("FIFO FAIL - Write_Transaction = %d, Read Transaction = %d",wr_tr.data_in,rd_tr.data_out),UVM_MEDIUM);
    end
    endtask


endclass