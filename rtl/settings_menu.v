`timescale 1ns/1ps
module settings_menu(input clk,input rst,input[3:0]press,input[2:0]mode,input weather_open,input weather_back,input weather_choose,output reg open,output reg weather_request,output reg[1:0]adjust_target,output reg adjust_dec,output reg adjust_inc,output[2:0]selected_item,input[9:0]x,input[9:0]y,input[23:0]background,output reg[23:0]rgb);
 reg[2:0]selected;reg editing,waiting;wire visible=open&&!waiting;integer row;assign selected_item=selected;
 always @(posedge clk)begin weather_request<=0;adjust_dec<=0;adjust_inc<=0;if(rst)begin open<=0;selected<=0;editing<=0;waiting<=0;adjust_target<=0;end else begin
  if(mode==0&&press[2]&&!weather_open)begin open<=~open;selected<=0;editing<=0;waiting<=0;end if(weather_back)waiting<=0;if(weather_choose)begin open<=0;waiting<=0;editing<=0;end
  if(visible)if(editing)begin if(press[0])adjust_dec<=1;if(press[1])adjust_inc<=1;if(press[2]||press[3])editing<=0;end else begin
   if(press[0])selected<=selected==0?3:selected-1'b1;if(press[1])selected<=selected==3?0:selected+1'b1;if(press[2])open<=0;
   if(press[3])if(selected==3)begin weather_request<=1;waiting<=1;end else begin editing<=1;adjust_target<=selected[1:0];end end end end
 always @* begin
  rgb=background;row=(y-154)/44;
  // A single compact panel: the black outer frame contains the title, all
  // four rows and the current parameter.  Pixels outside the frame remain
  // untouched, removing the former oversized pale-blue rectangle.
  if(visible&&x>=205&&x<435&&y>=96&&y<378)rgb=24'hc6e8f8;
  if(visible&&x>=205&&x<435&&y>=96&&y<378&&
     (x==205||x==434||y==96||y==377))rgb=24'h000000;
  // Four full-height 44-pixel rows.  Each bottom edge directly touches the
  // next row's top edge.  Shared boundaries are drawn once, not as two
  // adjacent scan lines, so they remain visually one pixel thick.
  if(visible&&x>=205&&x<435&&y>=154&&y<330&&
     (x==205||x==434||y==154||y==198||y==242||y==286||y==329))rgb=24'h000000;
  // Selected row uses a clear two-pixel pale-yellow inner outline.
  if(visible&&x>=206&&x<434&&y>=154&&y<330&&row==selected&&
     (x==206||x==207||x==432||x==433||
      ((y-154)%44)==1||((y-154)%44)==2||
      ((y-154)%44)==41||((y-154)%44)==42))rgb=24'hffe680;
 end
endmodule
