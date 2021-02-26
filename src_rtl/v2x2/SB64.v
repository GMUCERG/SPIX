`timescale 1ns / 1ps

module SB64(
    input clk,
    input rst,
    input start,
    input [63:0] x_in,
    input [7:0] rc,
    output [63:0] x_out,
    output reg valid = 0
    );
    
    reg [2:0] round = 0;
    reg [31:0] xl1 = 0, xr1 = 0, xl2 = 0, xr2 = 0;
    reg hold = 1;
    
    wire [31:0] rc_round1, rc_round2, x0, x1;
    assign rc_round1 = {31'hFFFF_FFFF, rc[round]};
    assign rc_round2 = {31'hFFFF_FFFF, rc[round+1]};
    
    assign x0 = x_in[63:32];
    assign x1 = x_in[31:0];
    assign x_out = {xl1, xr1};
    
    // unrolled stage
    always @(*) begin
        xl2 = ({xl1[26:0], xl1[31:27]} & xl1) ^ {xl1[30:0], xl1[31]} ^ xr1^ rc_round1;
        xr2 = xl1;
    
    end
    
    always @(posedge clk) begin
        valid <= 0;
    
        if (rst) begin
            round <= 0;
            hold <= 1;
        end else begin
            if (hold) begin
                if (start) begin
                    xl1 <= x0;
                    xr1 <= x1;
                    hold <= 0;
                end
            end else begin
                xl1 <= ({xl2[26:0], xl2[31:27]} & xl2) ^ {xl2[30:0], xl2[31]} ^ xr2 ^ rc_round2;
                xr1 <= xl2;

                round <= round + 2;
                if (round == 6) begin
                    valid <= 1'b1; 
                    hold  <= 1;
                    round <= 0;
                end
            end
        end
    end
    
endmodule
