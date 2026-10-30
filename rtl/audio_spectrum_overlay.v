`timescale 1ns/1ps
module audio_spectrum_overlay(
 input clk,input rst,input frame_tick,input sample_strobe,input signed[15:0]sample,
 input enable,input[4:0]picture_index,input[9:0]x,input[9:0]y,
 input[23:0]background,output reg[23:0]rgb);
 reg[15:0]peak;reg[1:0]frame_div;reg[6:0]height[0:7];
 integer i,slot,band,bar_top;reg[15:0]magnitude,next_peak;reg[6:0]level;
 reg[23:0]ink;
 always @*begin
  magnitude=sample[15]?(~sample+1'b1):sample;next_peak=magnitude>peak?magnitude:peak;
  // The environmental WAV files have modest programme levels after the
  // weather and transition gains.  Use a low gate and nonlinear expansion so
  // quiet ambience still produces visible columns without making silence move.
  if(next_peak<16'd24)level=0;
  else if(next_peak<16'd256)level=7'd4;
  else if(next_peak<16'd1024)level=7'd8+((next_peak-16'd256)>>7);
  else if(next_peak<16'd4096)level=7'd14+((next_peak-16'd1024)>>7);
  else if(next_peak<16'd8192)level=7'd38+((next_peak-16'd4096)>>8);
  else level=7'd60;
 end
 always @(posedge clk)begin
  if(rst)begin peak<=0;frame_div<=0;
   for(i=0;i<8;i=i+1)height[i]<=0;end
  else if(!enable)begin peak<=0;frame_div<=0;for(i=0;i<8;i=i+1)height[i]<=0;end
  else begin
   // Capture the peak continuously, but publish only once every four video
   // frames (about 15 Hz at 60 Hz video).  Updating every 32 PCM samples was
   // over 1000 Hz and appeared as LCD/camera persistence rather than motion.
   if(sample_strobe)peak<=next_peak;
   if(frame_tick)begin
    if(frame_div==2'd3)begin
     for(i=0;i<7;i=i+1)height[i]<=height[i+1];
     // Fast attack and controlled release make beats clear without flicker.
     if(level>=height[7])height[7]<=level;
     else if(height[7]>level+7'd8)height[7]<=height[7]-7'd8;
     else height[7]<=level;
     peak<=0;frame_div<=0;
    end else frame_div<=frame_div+1'b1;
   end
  end
 end
 always @*begin
  // Keep the original picture fully visible.  Only active spectrum bar pixels
  // are overlaid; the former light-gray 400..479 HUD background is removed.
  rgb=background;
  case(picture_index>>1)0:ink=24'h42bff5;1:ink=24'hff8a38;2:ink=24'h9275d8;3:ink=24'hffd83d;default:ink=24'hb9e9ff;endcase
  if(enable&&y>=400&&y<480)begin slot=(x>=54)?((x-54)/34):-1;
   if(slot>=0&&slot<16&&((x-54)%34)<22)begin band=slot<8?slot:15-slot;bar_top=470-height[band];if(y>=bar_top&&y<470)rgb=ink;end
  end
 end
endmodule
