`timescale 1ns/1ps
// Exact average 48k samples/s from 25MHz; ACR measures the real pixel intervals.
module audio_test(input clk,input rst,input mute,output reg sample_clock,output reg [15:0] sample);
    reg [24:0] accumulator;
    reg [5:0] phase;
    function signed [15:0] sine;
        input [5:0] p;
        reg signed [15:0] q;
        begin case(p%24)
            0:q=0;1:q=1069;2:q=2120;3:q=3135;4:q=4096;5:q=4987;
            6:q=5793;7:q=6499;8:q=7094;9:q=7568;10:q=7913;11:q=8122;
            12:q=8192;13:q=8122;14:q=7913;15:q=7568;16:q=7094;17:q=6499;
            18:q=5793;19:q=4987;20:q=4096;21:q=3135;22:q=2120;default:q=1069;
        endcase sine=p<24?q:-q;end
    endfunction
    always @(posedge clk) begin
        sample_clock<=0;
        if(rst) begin accumulator<=0;phase<=0;sample<=0;end
        else if(accumulator>=25000000-48000) begin
            accumulator<=accumulator+48000-25000000;sample_clock<=1;
            sample<=mute?0:sine(phase);phase<=phase==47?0:phase+1'b1;
        end else accumulator<=accumulator+48000;
    end
endmodule
