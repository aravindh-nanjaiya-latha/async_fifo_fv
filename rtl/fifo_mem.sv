//Module for fifo memory
//Author: Raghav

module fifo_mem #(parameter data_width = 8,depth = 54) ( //Actual fifo_depth = 45 only
input logic w_clk,r_clk,w_en,r_en,full,empty,arstn,
input logic [data_width-1:0] data_in,
output logic [data_width-1:0] data_out,
input logic [5:0] w_ptr,r_ptr
);

logic [data_width-1:0] f_mem [depth-1:9];

//Logic for write side
always_ff @(posedge w_clk or negedge arstn) begin
    if(~arstn) begin
        foreach(f_mem[i]) begin
            f_mem[i] <= '0;
        end
    end
    else if(w_en && ~full) begin
        f_mem[w_ptr] <= data_in;
    end
end

//Logic for read side
always_ff @(posedge r_clk) begin
    if(~empty && r_en) begin
        data_out <= f_mem[r_ptr];
    end
end



endmodule
