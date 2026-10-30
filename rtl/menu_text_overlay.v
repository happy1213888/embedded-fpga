`timescale 1ns/1ps
module menu_text_overlay(input clk,input[9:0]x,input[9:0]y,input[23:0]background,input settings_open,input weather_open,input preview_ready,input[2:0]settings_selected,input[2:0]weather_group,input[6:0]brightness_percent,input[6:0]contrast_percent,input[2:0]scale,input weather_anim,input weather_dir,input[4:0]weather_frame,output reg[23:0]rgb);
 reg[5:0]code;reg[3:0]font_row;wire[15:0]bits;integer left,top,pos,lx,ly,count,line,font_col;reg title_large;reg[7:0]percent;reg[3:0]hundreds,tens,ones;reg[23:0]rgb_next;menu_font font(code,font_row,bits);
 always @(posedge clk)begin
  if(settings_selected==0)percent<=brightness_percent;
  else if(settings_selected==1)percent<=contrast_percent;
  else case(scale)0:percent<=0;1:percent<=25;2:percent<=50;3:percent<=75;default:percent<=100;endcase
  case(percent)0:begin hundreds<=0;tens<=0;ones<=0;end 5:begin hundreds<=0;tens<=0;ones<=5;end 10:begin hundreds<=0;tens<=1;ones<=0;end 15:begin hundreds<=0;tens<=1;ones<=5;end 20:begin hundreds<=0;tens<=2;ones<=0;end 25:begin hundreds<=0;tens<=2;ones<=5;end 30:begin hundreds<=0;tens<=3;ones<=0;end 35:begin hundreds<=0;tens<=3;ones<=5;end 40:begin hundreds<=0;tens<=4;ones<=0;end 45:begin hundreds<=0;tens<=4;ones<=5;end 50:begin hundreds<=0;tens<=5;ones<=0;end 55:begin hundreds<=0;tens<=5;ones<=5;end 60:begin hundreds<=0;tens<=6;ones<=0;end 65:begin hundreds<=0;tens<=6;ones<=5;end 70:begin hundreds<=0;tens<=7;ones<=0;end 75:begin hundreds<=0;tens<=7;ones<=5;end 80:begin hundreds<=0;tens<=8;ones<=0;end 85:begin hundreds<=0;tens<=8;ones<=5;end 90:begin hundreds<=0;tens<=9;ones<=0;end 95:begin hundreds<=0;tens<=9;ones<=5;end 100:begin hundreds<=1;tens<=0;ones<=0;end default:begin hundreds<=0;tens<=0;ones<=0;end endcase rgb<=rgb_next;end
 always @* begin rgb_next=background;code=0;font_row=0;left=0;top=0;pos=0;lx=0;ly=0;count=0;line=0;font_col=0;title_large=0;
  if(settings_open)begin
   if(y>=112&&y<136)begin left=296;top=112;count=2;pos=(x-left)/24;lx=(x-left)%24;ly=y-top;title_large=1;code=pos==0?51:52;end
   else if(y>=154&&y<330)begin
    if(y<198)begin line=0;top=168;end
    else if(y<242)begin line=1;top=212;end
    else if(y<286)begin line=2;top=256;end
    else begin line=3;top=300;end
    ly=y-top;case(line)
    0:begin left=304;count=2;pos=(x-left)>>4;lx=(x-left)&15;code=pos==0?16:17;end
    1:begin left=296;count=3;pos=(x-left)>>4;lx=(x-left)&15;case(pos)0:code=18;1:code=19;default:code=17;endcase end
    2:begin left=288;count=4;pos=(x-left)>>4;lx=(x-left)&15;case(pos)0:code=20;1:code=21;2:code=22;default:code=23;endcase end
    default:begin left=272;count=6;pos=(x-left)>>4;lx=(x-left)&15;case(pos)0:code=0;1:code=1;2:code=2;3:code=3;4:code=4;default:code=5;endcase end endcase end
   else if(y>=350&&y<366)begin top=350;ly=y-top;
    if(settings_selected==3)begin left=256;count=8;pos=(x-left)>>4;lx=(x-left)&15;case(pos)0:code=26;1:code=27;2:code=0;3:code=1;4:code=43;5:code=weather_group==0?6:weather_group==1?9:weather_group==2?11:weather_group==3?13:7;6:code=weather_group==0?7:weather_group==1?10:weather_group==2?12:weather_group==3?14:15;default:code=weather_group==0?8:0;endcase end
    else begin left=248;count=9;pos=(x-left)>>4;lx=(x-left)&15;case(pos)0:code=26;1:code=27;2:code=settings_selected==0?16:settings_selected==1?18:22;3:code=settings_selected==0?17:settings_selected==1?19:23;4:code=43;5:code=hundreds==0?31:31+hundreds;6:code=31+tens;7:code=31+ones;default:code=42;endcase end end
  end else if(weather_open)begin
   if(y>=44&&y<68)begin left=248;top=44;count=6;pos=(x-left)/24;lx=(x-left)%24;ly=y-top;case(pos)0:code=0;1:code=1;2:code=2;3:code=3;4:code=4;default:code=5;endcase end
   else if(!preview_ready&&y>=210&&y<226)begin left=280;top=210;count=5;pos=(x-left)>>4;lx=(x-left)&15;ly=y-top;case(pos)0:code=44;1:code=45;2:code=46;3:code=47;default:code=48;endcase end
   else if(y>=378&&y<402)begin top=378;ly=y-top;
    // Old label follows the departing centre image and disappears at mid-slide.
    // The new label enters during the second half and settles at the centre.
    if(!weather_anim)begin left=weather_group==0?284:296;count=weather_group==0?3:2;end
    else if(weather_frame<12)begin left=(weather_group==0?284:296)+(weather_dir?-((weather_frame<<4)+(weather_frame<<1)):((weather_frame<<4)+(weather_frame<<1)));count=weather_group==0?3:2;end
    else begin left=((weather_dir?(weather_group==4?0:weather_group+1):(weather_group==0?4:weather_group-1))==0?284:296)+(weather_dir?(((24-weather_frame)<<4)+((24-weather_frame)<<1)):-(((24-weather_frame)<<4)+((24-weather_frame)<<1)));count=(weather_dir?(weather_group==4?0:weather_group+1):(weather_group==0?4:weather_group-1))==0?3:2;end
    pos=(x-left)/24;lx=(x-left)%24;
    if(weather_anim&&weather_frame>=12)begin case(weather_dir?(weather_group==4?0:weather_group+1):(weather_group==0?4:weather_group-1))0:case(pos)0:code=6;1:code=7;default:code=8;endcase 1:code=pos==0?9:10;2:code=pos==0?11:12;3:code=pos==0?13:14;default:code=pos==0?7:15;endcase end
    else begin case(weather_group)0:case(pos)0:code=6;1:code=7;default:code=8;endcase 1:code=pos==0?9:10;2:code=pos==0?11:12;3:code=pos==0?13:14;default:code=pos==0?7:15;endcase end end end
  if(pos>=0&&pos<count)begin if(title_large)begin if(lx<24&&ly<24)begin
   case(ly)0,1:font_row=0;2:font_row=1;3,4:font_row=2;5:font_row=3;6,7:font_row=4;8:font_row=5;9,10:font_row=6;11:font_row=7;12,13:font_row=8;14:font_row=9;15,16:font_row=10;17:font_row=11;18,19:font_row=12;20:font_row=13;21,22:font_row=14;default:font_row=15;endcase
   case(lx)0,1:font_col=0;2:font_col=1;3,4:font_col=2;5:font_col=3;6,7:font_col=4;8:font_col=5;9,10:font_col=6;11:font_col=7;12,13:font_col=8;14:font_col=9;15,16:font_col=10;17:font_col=11;18,19:font_col=12;20:font_col=13;21,22:font_col=14;default:font_col=15;endcase
   // The 16-to-24 mapping repeats source rows and columns, producing a
   // naturally heavier title without adding a long neighbour-pixel chain.
   if(bits[15-font_col])rgb_next=24'h173650;end end
  else if(weather_open&&(top==44||top==378))begin if(lx<24&&ly<24)begin
   case(ly)0,1:font_row=0;2:font_row=1;3,4:font_row=2;5:font_row=3;6,7:font_row=4;8:font_row=5;9,10:font_row=6;11:font_row=7;12,13:font_row=8;14:font_row=9;15,16:font_row=10;17:font_row=11;18,19:font_row=12;20:font_row=13;21,22:font_row=14;default:font_row=15;endcase
   case(lx)0,1:line=0;2:line=1;3,4:line=2;5:line=3;6,7:line=4;8:line=5;9,10:line=6;11:line=7;12,13:line=8;14:line=9;15,16:line=10;17:line=11;18,19:line=12;20:line=13;21,22:line=14;default:line=15;endcase
   // The 16-to-24 repeated-column mapping above is the bold treatment.
   // Pure white gives maximum contrast over the dimmed photo background.
   if(bits[15-line])rgb_next=24'hffffff;end end else if(lx>=0&&lx<16&&ly>=0&&ly<16)begin font_row=ly;if(bits[15-lx])rgb_next=24'h173650;end end end
endmodule
