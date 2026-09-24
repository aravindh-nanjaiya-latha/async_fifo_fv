interface intf #(parameter data_width = 8);
    logic [data_width-1:0]data_in;
    logic [data_width-1:0]data_out;
    logic w_en;
    logic r_en;
    logic w_clk;
    logic r_clk;
    logic wrst_n;
    logic rrst_n;
    logic full;
    logic empty; 
endinterface //intf