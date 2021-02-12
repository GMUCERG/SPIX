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
    reg [31:0] xi = 0, xj = 0;
    reg hold = 1;
    
    wire [31:0] rc_round, x0, x1;
    assign rc_round = {31'hFFFF_FFFF, rc[round]};
    
    assign x0 = x_in[31:0];
    assign x1 = x_in[63:32];
    assign x_out = {xj, xi};
    
    always @(posedge clk) begin
        valid <= 0;
    
        if (rst) begin
            round <= 0;
            hold <= 1;
        end else begin
            if (hold) begin
                if (start) begin
                    xi <= x0;
                    xj <= x1;
                    hold <= 0;
                end
            end else begin
                // alternate xi/xj as j-1/j-2
                if (round[0]) begin
                    xj <= ({xi[26:0], xi[31:27]} & xi) ^ {xi[30:0], xi[31]} ^ xj ^ rc_round;
                end else begin
                    xi <= ({xj[26:0], xj[31:27]} & xj) ^ {xj[30:0], xj[31]} ^ xi ^ rc_round;
                end
                round <= round + 1;
                if (round == 7) begin
                    valid <= 1'b1; 
                    hold <= 1;
                end
            end
        end
    end
    
endmodule
