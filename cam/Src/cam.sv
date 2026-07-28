interface cambus;
 logic [31:0] din;
 logic [31:0] sword;
 logic [1:0] wr_adr;
 logic clk;
 logic wr;
 logic rst;
 logic [1:0] adr;
 logic emp;
endinterface

module cam(
    input logic [31:0] din,
    input logic [31:0] sword,
    input logic [1:0] wr_adr,
    input logic clk,
    input logic rst,
    input logic wr,
    output logic [1:0] adr,
    output logic emp
);

    logic [31:0] x [3:0];

    typedef enum logic [1:0] {
        Reg0 = 2'b00,
        Reg1 = 2'b01,
        Reg2 = 2'b10,
        Reg3 = 2'b11
    } address;

    typedef enum logic {
        Miss  = 1'b0,
        Found = 1'b1
    } search;

always_ff @(posedge clk) begin
    if (rst) begin
        x[0] <= 32'b0;
        x[1] <= 32'b0;
        x[2] <= 32'b0;
        x[3] <= 32'b0;
    end 
    else if (wr) begin
        x[wr_adr] <= din;
    end 
end     

always_comb begin  
    adr = Reg0;
    emp = Miss;
    if (sword == x[0]) begin
        adr = Reg0;
        emp = Found;
    end else if (sword == x[1]) begin
        adr = Reg1;
        emp = Found;
    end else if (sword == x[2]) begin
        adr = Reg2;
        emp = Found;
    end else if (sword == x[3]) begin
        adr = Reg3;
        emp = Found;
    end
end
endmodule


