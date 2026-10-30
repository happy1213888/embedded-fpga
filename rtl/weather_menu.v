`timescale 1ns/1ps
module weather_menu(input clk,input rst,input [3:0] press,input [2:0] mode,input [4:0] current_index,input open_from_settings,
 output reg open,output reg [2:0] selected,output reg choose_pulse,output reg back_pulse,output reg preview_pulse,output reg [4:0] preview_index,
 input [9:0] x,input [9:0] y,input [23:0] background,input preview_ready,input [23:0] preview_pixel,input [4:0] thumbnails_loaded,
 output reg [2:0] thumb_slot,output reg [12:0] thumb_address,input [7:0] thumb_pixel,output reg [23:0] rgb,
 output reg anim_active,output reg anim_dir,output reg [4:0] anim_frame);
 reg from_settings,back_pending,choose_waiting,queued_valid,queued_dir;reg[4:0]return_index;reg[2:0]old_selected,target_selected;reg[5:0]wait_phase;
 integer px,py,sx,sy,actor_x,actor_y;reg actor,scale2,scale4;reg[2:0]actor_slot;wire frame_tick=x==0&&y==480;
 wire[7:0]tr={thumb_pixel[7:5],thumb_pixel[7:5],thumb_pixel[7:6]},tg={thumb_pixel[4:2],thumb_pixel[4:2],thumb_pixel[4:3]},tb={thumb_pixel[1:0],thumb_pixel[1:0],thumb_pixel[1:0],thumb_pixel[1:0]};
 function[2:0]prev5;input[2:0]v;begin prev5=v==0?4:v-1'b1;end endfunction function[2:0]next5;input[2:0]v;begin next5=v==4?0:v+1'b1;end endfunction
 task start_move;input d;begin anim_active<=1;anim_dir<=d;anim_frame<=0;old_selected<=selected;target_selected<=d?next5(selected):prev5(selected);end endtask
 always@(posedge clk)begin choose_pulse<=0;back_pulse<=0;preview_pulse<=0;if(rst)begin open<=0;selected<=0;old_selected<=0;target_selected<=0;from_settings<=0;return_index<=0;back_pending<=0;choose_waiting<=0;anim_active<=0;anim_dir<=0;anim_frame<=0;queued_valid<=0;queued_dir<=0;wait_phase<=0;end else begin
  if(frame_tick&&open&&!preview_ready&&!anim_active)wait_phase<=wait_phase+3;
  if(back_pending)begin open<=0;back_pending<=0;end
  if(open_from_settings&&!open)begin open<=1;selected<=current_index[3:1];from_settings<=1;return_index<=current_index;preview_index<={current_index[3:1],1'b0};preview_pulse<=1;choose_waiting<=0;anim_active<=0;queued_valid<=0;end
  else if(mode==3'b001&&press[2]&&!open)begin open<=1;selected<=current_index[3:1];from_settings<=0;return_index<=current_index;preview_index<={current_index[3:1],1'b0};preview_pulse<=1;choose_waiting<=0;anim_active<=0;queued_valid<=0;end
  else if(open)begin if(anim_active)begin if(press[0])begin queued_valid<=1;queued_dir<=0;end if(press[1])begin queued_valid<=1;queued_dir<=1;end if(frame_tick)begin if(anim_frame==23)begin selected<=target_selected;preview_index<={target_selected,1'b0};preview_pulse<=1;anim_active<=0;anim_frame<=0;if(queued_valid)begin old_selected<=target_selected;target_selected<=queued_dir?next5(target_selected):prev5(target_selected);anim_dir<=queued_dir;anim_active<=1;queued_valid<=0;end end else anim_frame<=anim_frame+1'b1;end end else begin
   if(press[0]&&!choose_waiting)start_move(0);else if(press[1]&&!choose_waiting)start_move(1);
   if(press[3]&&!choose_waiting)begin choose_pulse<=1;choose_waiting<=1;end if(choose_waiting&&current_index=={selected,1'b0})begin open<=0;choose_waiting<=0;end
   if(press[2])begin preview_index<=return_index;if(from_settings)begin back_pulse<=1;back_pending<=1;end else open<=0;end end end end end
 always@*begin thumb_slot=selected;thumb_address=0;actor=0;actor_slot=selected;px=0;py=0;sx=0;sy=0;actor_x=0;actor_y=0;scale2=0;scale4=0;if(open)begin
  if(!anim_active)begin if(preview_ready&&x>=160&&x<480&&y>=124&&y<324)begin actor=1;actor_slot=selected;actor_x=160;actor_y=124;scale4=1;end else if(x>=24&&x<104&&y>=199&&y<249)begin actor=1;actor_slot=prev5(selected);actor_x=24;actor_y=199;end else if(x>=536&&x<616&&y>=199&&y<249)begin actor=1;actor_slot=next5(selected);actor_x=536;actor_y=199;end end
  else if(anim_dir)begin
   if(anim_frame<8)begin scale4=1;actor_x=192-((anim_frame<<3)+(anim_frame<<1));actor_y=144+(anim_frame<<2);end else if(anim_frame<16)begin scale2=1;actor_x=112-(((anim_frame-8)<<2)+((anim_frame-8)<<1));actor_y=176+(((anim_frame-8)<<1)+(anim_frame-8));end else begin actor_x=64-((anim_frame-16)<<2);actor_y=200;end if(x>=actor_x&&x<actor_x+(scale4?320:scale2?160:80)&&y>=actor_y&&y<actor_y+(scale4?200:scale2?100:50))begin actor=1;actor_slot=old_selected;end
   actor_x=544-((anim_frame<<4)-anim_frame);actor_y=204-(anim_frame<8?anim_frame<<1:anim_frame<16?16+((anim_frame-8)<<1):32+((anim_frame-16)<<2));scale4=anim_frame>=16;scale2=anim_frame>=8&&anim_frame<16;if(x>=actor_x&&x<actor_x+(scale4?320:scale2?160:80)&&y>=actor_y&&y<actor_y+(scale4?200:scale2?100:50))begin actor=1;actor_slot=next5(old_selected);end
   actor_x=640-(anim_frame<<2);actor_y=204;scale4=0;scale2=0;if(x>=actor_x&&x<actor_x+80&&y>=actor_y&&y<actor_y+50)begin actor=1;actor_slot=next5(next5(old_selected));end end
  else begin
   if(anim_frame<8)begin scale4=1;actor_x=192+((anim_frame<<3)+(anim_frame<<1));actor_y=144+(anim_frame<<2);end else if(anim_frame<16)begin scale2=1;actor_x=272+(((anim_frame-8)<<2)+((anim_frame-8)<<1));actor_y=176+(((anim_frame-8)<<1)+(anim_frame-8));end else begin actor_x=320+((anim_frame-16)<<2);actor_y=200;end if(x>=actor_x&&x<actor_x+(scale4?320:scale2?160:80)&&y>=actor_y&&y<actor_y+(scale4?200:scale2?100:50))begin actor=1;actor_slot=old_selected;end
   actor_x=32+((anim_frame<<4)-anim_frame);actor_y=204-(anim_frame<8?anim_frame<<1:anim_frame<16?16+((anim_frame-8)<<1):32+((anim_frame-16)<<2));scale4=anim_frame>=16;scale2=anim_frame>=8&&anim_frame<16;if(x>=actor_x&&x<actor_x+(scale4?320:scale2?160:80)&&y>=actor_y&&y<actor_y+(scale4?200:scale2?100:50))begin actor=1;actor_slot=prev5(old_selected);end
   actor_x=-64+(anim_frame<<2);actor_y=204;scale4=0;scale2=0;if(x>=actor_x&&x<actor_x+80&&y>=actor_y&&y<actor_y+50)begin actor=1;actor_slot=prev5(prev5(old_selected));end end
  if(actor)begin px=x-actor_x;py=y-actor_y;sx=scale4?(px>>2):scale2?(px>>1):px;sy=scale4?(py>>2):scale2?(py>>1):py;thumb_slot=actor_slot;thumb_address=sy*80+sx;end end end
 // Preserve the exact picture visible when the menu opened.  The top level
 // already freezes its framebuffer bank for the duration of the menu.
 // preview_pixel is produced by a synchronous line RAM and arrives two
 // pixel clocks after the menu coordinate.  Keep the preview layer active
 // for those two trailing clocks; framebuffer_engine clamps them to pixel
 // 319, preventing the background from leaking through at the right edge.
 wire center_preview=open&&!anim_active&&preview_ready&&x>=160&&x<482&&y>=104&&y<344;
 wire[9:0] wait_dx=x>=320?x-320:320-x;
 wire[9:0] wait_dy=y>=206?y-206:206-y;
 wire wait_ring=open&&!anim_active&&!preview_ready&&wait_dx<=32&&wait_dy<=32&&
   ((wait_dx>=25&&wait_dy<=20)||(wait_dy>=25&&wait_dx<=20))&&
   (((x+y+wait_phase)&6'h3f)<6'd46);
 wire loading_panel=open&&!anim_active&&!preview_ready&&x>=160&&x<480&&y>=104&&y<344;
 // The synchronous preview visibly ends at x=481.  Put the right two-pixel
 // selection edge immediately outside it at x=482..483; the other three
 // edges retain their established positions.
 always@(posedge clk)begin rgb<=background;if(open&&actor&&thumbnails_loaded[thumb_slot])rgb<={tr,tg,tb};if(loading_panel)rgb<=24'h24384a;if(center_preview)rgb<=preview_pixel;if(wait_ring)rgb<=24'hffffff;if(open&&x>=160&&x<484&&y>=104&&y<344&&(x<162||x>=482||y<106||y>=342))rgb<=24'hffe680;end
endmodule
