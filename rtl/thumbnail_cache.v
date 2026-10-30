`timescale 1ns/1ps
module thumbnail_cache(
 input write_clk,input write_reset,input write_start,input [2:0] write_slot,
 input write_valid,input [7:0] write_byte,output reg write_ready,output reg [4:0] loaded,
 input pixel_clk,input [2:0] read_slot,input [12:0] read_address,output reg [7:0] pixel
);
 reg [7:0] mem[0:19999];
 reg [12:0] write_pointer;reg [4:0] header_pointer;reg [2:0] active_slot;
 reg [14:0] read_pointer;
 always @(posedge write_clk) begin
  write_ready<=1'b1;
  if(write_reset) begin write_pointer<=0;header_pointer<=0;active_slot<=0;loaded<=0;end
  else if(write_start) begin write_pointer<=0;header_pointer<=0;active_slot<=write_slot;loaded[write_slot]<=0;end
  else if(write_valid) begin
   if(header_pointer<16) header_pointer<=header_pointer+1'b1;
            else if(write_pointer<4000) begin
                mem[active_slot*4000+write_pointer]<=write_byte;
    if(write_pointer==3999) loaded[active_slot]<=1'b1;
    write_pointer<=write_pointer+1'b1;
   end
  end
 end
 always @(posedge pixel_clk) begin
            read_pointer<=read_slot*4000+read_address;
  pixel<=mem[read_pointer];
 end
endmodule
