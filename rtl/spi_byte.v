`timescale 1ns/1ps
module spi_byte(input clk,input rst,input start,input [7:0] tx,
    input [7:0] divider,input miso,output reg sck,output reg mosi,
    output reg busy,output reg done,output reg [7:0] rx);
    reg [7:0] count,shift;
    reg [3:0] edge_count;
    always @(posedge clk) begin
        done <= 0;
        if(rst) begin sck<=0;mosi<=1;busy<=0;count<=0;edge_count<=0;rx<=0;shift<=0; end
        else if(!busy) begin
            sck<=0;
            if(start) begin busy<=1;count<=divider;edge_count<=0;shift<=tx;mosi<=tx[7]; end
        end else if(count!=0) count<=count-1'b1;
        else begin
            count<=divider;sck<=~sck;
            if(!sck) rx<={rx[6:0],miso};
            else begin shift<={shift[6:0],1'b1};mosi<=shift[6]; end
            if(edge_count==15) begin busy<=0;done<=1;sck<=0;mosi<=1; end
            else edge_count<=edge_count+1'b1;
        end
    end
endmodule
