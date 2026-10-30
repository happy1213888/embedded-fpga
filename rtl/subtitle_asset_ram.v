`timescale 1ns/1ps
module subtitle_asset_ram(input write_clk,input write_reset,input write_start,input write_valid,input[7:0]write_byte,output reg write_ready,output reg loaded,output reg[11:0]text_width,input pixel_clk,input[15:0]pixel_address,output reg[1:0]pixel_code);
reg[7:0]mem[0:8191];reg[13:0]write_pointer;reg[4:0]header_pointer;reg[31:0]payload_size;reg[15:0]byte_address;reg[2:0]bit_select;reg[2:0]bit_select_delayed;reg[7:0]read_byte;
always@(posedge write_clk)begin write_ready<=1;if(write_reset)begin write_pointer<=0;header_pointer<=0;loaded<=0;text_width<=0;payload_size<=0;end else if(write_start)begin write_pointer<=0;header_pointer<=0;loaded<=0;text_width<=0;payload_size<=0;end else if(write_valid)begin if(header_pointer<16)begin case(header_pointer)4:text_width[7:0]<=write_byte;5:text_width[11:8]<=write_byte[3:0];8:payload_size[7:0]<=write_byte;9:payload_size[15:8]<=write_byte;10:payload_size[23:16]<=write_byte;11:payload_size[31:24]<=write_byte;endcase header_pointer<=header_pointer+1'b1;end else if(write_pointer<8192)begin mem[write_pointer]<=write_byte;if(write_pointer+1>=payload_size)loaded<=1;write_pointer<=write_pointer+1'b1;end end end
always@(posedge pixel_clk)begin
 byte_address<=pixel_address[15:3];
 bit_select<=pixel_address[2:0];
 read_byte<=mem[byte_address];
 bit_select_delayed<=bit_select;
 pixel_code<={1'b0,read_byte[7-bit_select_delayed]};
end
endmodule
