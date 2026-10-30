`timescale 1ns/1ps
module reset_sync(input clk,input async_reset,output reset);
    (* preserve = "true", keep = "true" *) reg [3:0] sync=4'b1111;
    always @(posedge clk or posedge async_reset) if(async_reset) sync<=15;else sync<={sync[2:0],1'b0};
    assign reset=sync[3];
endmodule
