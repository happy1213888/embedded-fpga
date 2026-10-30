`timescale 1ns/1ps
module subtitle_overlay(input clk,input [9:0] x,input [9:0] y,input [23:0] background,
 input visible,input [4:0] picture_index,input [2:0] sentence,input [31:0] sentence_samples,input [31:0] sentence_duration,
 input [11:0] text_width,output reg [15:0] pixel_address,input [1:0] pixel_code,output reg [23:0] rgb);
 reg in1,in2,in3,bar1,bar2,bar3; reg [23:0] bg1,bg2,bg3; reg [18:0] coeff; reg [50:0] product; integer left; integer local_x;
 wire[7:0]gray_r={1'b0,bg3[23:17]}+8'd64,gray_g={1'b0,bg3[15:9]}+8'd64,gray_b={1'b0,bg3[7:1]}+8'd64;
 always @* begin
  // Restore the hardware-verified D44 pacing.  These coefficients include the
  // natural entry/exit margins used by the generated subtitle bitmaps.
  // With the one-second timeline delay removed, spread the same complete
  // right-to-left travel over the full male-speech interval.  The first glyph
  // still begins at x=640, while the tail exits at the original speech end.
  case(picture_index) 1:coeff=19'd674;3:coeff=19'd697;5:coeff=19'd856;7:coeff=19'd834;9:coeff=19'd815;default:coeff=0;endcase
  // The first glyph starts outside x=640 and enters continuously from the
  // right edge when the male voice begins, matching the D44 presentation.
  product=sentence_samples*coeff;left=640-(product>>18);local_x=x-left;
 end
 always @(posedge clk) begin
  bg1<=background;bg2<=bg1;bg3<=bg2;bar1<=visible&&y>=416&&y<448;bar2<=bar1;bar3<=bar2;in1<=visible&&y>=420&&y<444&&local_x>=0&&local_x<text_width;in2<=in1;in3<=in2;
  if(visible&&y>=420&&y<444&&local_x>=0&&local_x<text_width)pixel_address<=(y-420)*text_width+local_x;else pixel_address<=0;
  rgb<=bar3?{gray_r,gray_g,gray_b}:bg3;if(in3&&pixel_code!=0)rgb<=24'h000000;
 end
endmodule
