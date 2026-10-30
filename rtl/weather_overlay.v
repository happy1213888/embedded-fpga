`timescale 1ns/1ps
module weather_overlay(
 input [9:0] x,input [9:0] y,input [23:0] background,input enable,
 input [4:0] picture_index,input [7:0] rain_mm,input [7:0] temperature,input [4:0] wind_level,
 input [2:0] lightning_level,input [7:0] snow_mm,input [2:0] warning_level,input [2:0] breath_phase,
 input exercise_complete,output reg [23:0] rgb);
 localparam integer DATA_CENTER_X=320,CENTER_X=390,CENTER_Y=112;
 reg [7:0] value; reg [23:0] ink; reg [3:0] code; reg [34:0] dg; reg [15:0] rowbits;
 integer size,count,total,left,top,pos,lx,ly,sx,sy,nx,ny,digit_scale,digit_w,digit_h,spacing;
 reg body,outline;
 function [34:0] digit_font; input [7:0] c; begin case(c)
  "0":digit_font=35'b01110_10001_10011_10101_11001_10001_01110;
  "1":digit_font=35'b00100_01100_00100_00100_00100_00100_01110;
  "2":digit_font=35'b01110_10001_00001_00010_00100_01000_11111;
  "3":digit_font=35'b11110_00001_00001_01110_00001_00001_11110;
  "4":digit_font=35'b00010_00110_01010_10010_11111_00010_00010;
  "5":digit_font=35'b11111_10000_10000_11110_00001_00001_11110;
  "6":digit_font=35'b01110_10000_10000_11110_10001_10001_01110;
  "7":digit_font=35'b11111_00001_00010_00100_01000_01000_01000;
  "8":digit_font=35'b01110_10001_10001_01110_10001_10001_01110;
  "9":digit_font=35'b01110_10001_10001_01111_00001_00001_01110;
  "E":digit_font=35'b11111_10000_10000_11110_10000_10000_11111;
  "N":digit_font=35'b10001_11001_11001_10101_10011_10011_10001;
  "D":digit_font=35'b11110_10001_10001_10001_10001_10001_11110;
  default:digit_font=0; endcase end endfunction
 function [255:0] chinese_font; input [3:0] c; begin case(c)
  0:chinese_font=256'b0000000000000000011111111111110000000011000000000000001100000000000000110000000011111111111111100000001100000000000001101100000000000110110000000000110011000000000111001100010000111000110001101111000011001100011000001111110000000000000000000000000000000000; // 无
  1:chinese_font=256'b0000000000000000111111011111111000001100011000000101100111111100011110011000110011111101101011000011010110101100001101011010110000110101111011000011010111101100001100011111110000110000110110000011000110001100111000110000010000000000000000000000000000000000; // 预
  2:chinese_font=256'b0000000000000000001101100110000011111111111111100110000011001100011111111010100000101111001110000011111100111000001001110100010000000001100000001111111111111110000000000000000000111111111110000011000000011000001111111111100000000000000000000000000000000000; // 警
  3:chinese_font=256'b0000000000000000000011000110000011111111111111100000110001100000000000001100000001101100111111000110110110110000011011010011100000000000000010000011111111111000001101101101100000110110110110000011011011011000111111111111111000000000000000000000000000000000; // 蓝
  4:chinese_font=256'b0000000000000000000011100000000000011111111100000011100001100000011100001110000001111111111110000011001110011000001100111001100000110011100110000011111111111000001100000000010000110000000001100011000000001100000111111111100000000000000000000000000000000000; // 色
  5:chinese_font=256'b0000000000000000000011000110000001111111111111000000110001100000111111111111111000000001000000000011111111111000001100010001100000111111111110000011000100011000001111111111100000000000000000000001110001110000011100000000110000000000000000000000000000000000; // 黄
  6:chinese_font=256'b0000000000000000001100000110100000110111111110000011010110110100111111110001110000110011111110000111011000001100011101000000011001111011111110001111101000011000111100111111100000110011000100000011000110110000001101111111111000000000000000000000000000000000; // 橙
  7:chinese_font=256'b0000000000000000000100000000000000111011111111000011000001100000011011000110000001101100011000001111100001100000001110000110000000110000011000000111110001100000011000000110000000000000011000000001110001100000111001111111111000000000000000000000000000000000; // 红
  default:chinese_font=0; endcase end endfunction
 function [3:0] warning_char; input [2:0] level; input integer p; begin
  if(level==0) case(p) 0:warning_char=0;1:warning_char=1;default:warning_char=2;endcase
  else case(p) 0:begin case(level)1:warning_char=3;2:warning_char=5;3:warning_char=6;default:warning_char=7;endcase end 1:warning_char=4;2:warning_char=1;default:warning_char=2;endcase
 end endfunction
 function [15:0] chinese_row; input [3:0] c; input [3:0] r; begin case({c,r})
 8'h00:chinese_row=16'h0000;8'h01:chinese_row=16'h7FFC;8'h02:chinese_row=16'h0300;8'h03:chinese_row=16'h0300;
 8'h04:chinese_row=16'h0300;8'h05:chinese_row=16'hFFFE;8'h06:chinese_row=16'h0300;8'h07:chinese_row=16'h06C0;
 8'h08:chinese_row=16'h06C0;8'h09:chinese_row=16'h0CC0;8'h0A:chinese_row=16'h1CC4;8'h0B:chinese_row=16'h38C6;
 8'h0C:chinese_row=16'hF0CC;8'h0D:chinese_row=16'h60FC;8'h0E:chinese_row=16'h0000;8'h0F:chinese_row=16'h0000;
 8'h10:chinese_row=16'h0000;8'h11:chinese_row=16'hFDFE;8'h12:chinese_row=16'h0C60;8'h13:chinese_row=16'h59FC;
 8'h14:chinese_row=16'h798C;8'h15:chinese_row=16'hFDAC;8'h16:chinese_row=16'h35AC;8'h17:chinese_row=16'h35AC;
 8'h18:chinese_row=16'h35EC;8'h19:chinese_row=16'h35EC;8'h1A:chinese_row=16'h31FC;8'h1B:chinese_row=16'h30D8;
 8'h1C:chinese_row=16'h318C;8'h1D:chinese_row=16'hE304;8'h1E:chinese_row=16'h0000;8'h1F:chinese_row=16'h0000;
 8'h20:chinese_row=16'h0000;8'h21:chinese_row=16'h3660;8'h22:chinese_row=16'hFFFE;8'h23:chinese_row=16'h60CC;
 8'h24:chinese_row=16'h7FA8;8'h25:chinese_row=16'h2F38;8'h26:chinese_row=16'h3F38;8'h27:chinese_row=16'h2744;
 8'h28:chinese_row=16'h0180;8'h29:chinese_row=16'hFFFE;8'h2A:chinese_row=16'h0000;8'h2B:chinese_row=16'h3FF8;
 8'h2C:chinese_row=16'h3018;8'h2D:chinese_row=16'h3FF8;8'h2E:chinese_row=16'h0000;8'h2F:chinese_row=16'h0000;
 8'h30:chinese_row=16'h0000;8'h31:chinese_row=16'h0C60;8'h32:chinese_row=16'hFFFE;8'h33:chinese_row=16'h0C60;
 8'h34:chinese_row=16'h00C0;8'h35:chinese_row=16'h6CFC;8'h36:chinese_row=16'h6DB0;8'h37:chinese_row=16'h6D38;
 8'h38:chinese_row=16'h0008;8'h39:chinese_row=16'h3FF8;8'h3A:chinese_row=16'h36D8;8'h3B:chinese_row=16'h36D8;
 8'h3C:chinese_row=16'h36D8;8'h3D:chinese_row=16'hFFFE;8'h3E:chinese_row=16'h0000;8'h3F:chinese_row=16'h0000;
 8'h40:chinese_row=16'h0000;8'h41:chinese_row=16'h0E00;8'h42:chinese_row=16'h1FF0;8'h43:chinese_row=16'h3860;
 8'h44:chinese_row=16'h70E0;8'h45:chinese_row=16'h7FF8;8'h46:chinese_row=16'h3398;8'h47:chinese_row=16'h3398;
 8'h48:chinese_row=16'h3398;8'h49:chinese_row=16'h3FF8;8'h4A:chinese_row=16'h3004;8'h4B:chinese_row=16'h3006;
 8'h4C:chinese_row=16'h300C;8'h4D:chinese_row=16'h1FF8;8'h4E:chinese_row=16'h0000;8'h4F:chinese_row=16'h0000;
 8'h50:chinese_row=16'h0000;8'h51:chinese_row=16'h0C60;8'h52:chinese_row=16'h7FFC;8'h53:chinese_row=16'h0C60;
 8'h54:chinese_row=16'hFFFE;8'h55:chinese_row=16'h0100;8'h56:chinese_row=16'h3FF8;8'h57:chinese_row=16'h3118;
 8'h58:chinese_row=16'h3FF8;8'h59:chinese_row=16'h3118;8'h5A:chinese_row=16'h3FF8;8'h5B:chinese_row=16'h0000;
 8'h5C:chinese_row=16'h1C70;8'h5D:chinese_row=16'h700C;8'h5E:chinese_row=16'h0000;8'h5F:chinese_row=16'h0000;
 8'h60:chinese_row=16'h0000;8'h61:chinese_row=16'h3068;8'h62:chinese_row=16'h37F8;8'h63:chinese_row=16'h35B4;
 8'h64:chinese_row=16'hFF1C;8'h65:chinese_row=16'h33F8;8'h66:chinese_row=16'h760C;8'h67:chinese_row=16'h7406;
 8'h68:chinese_row=16'h7BF8;8'h69:chinese_row=16'hFA18;8'h6A:chinese_row=16'hF3F8;8'h6B:chinese_row=16'h3310;
 8'h6C:chinese_row=16'h31B0;8'h6D:chinese_row=16'h37FE;8'h6E:chinese_row=16'h0000;8'h6F:chinese_row=16'h0000;
 8'h70:chinese_row=16'h0000;8'h71:chinese_row=16'h1000;8'h72:chinese_row=16'h3BFC;8'h73:chinese_row=16'h3060;
 8'h74:chinese_row=16'h6C60;8'h75:chinese_row=16'h6C60;8'h76:chinese_row=16'hF860;8'h77:chinese_row=16'h3860;
 8'h78:chinese_row=16'h3060;8'h79:chinese_row=16'h7C60;8'h7A:chinese_row=16'h6060;8'h7B:chinese_row=16'h0060;
 8'h7C:chinese_row=16'h1C60;8'h7D:chinese_row=16'hE7FE;8'h7E:chinese_row=16'h0000;8'h7F:chinese_row=16'h0000;
 default:chinese_row=0;endcase end endfunction
 function [4:0] scale_coord; input [5:0] c; input [2:0] phase; reg [8:0] t; begin
  case(phase)
   0:scale_coord=c>>1;
   1:begin t=(c<<2)+(c<<1)+c;scale_coord=t>>4;end
   2:begin t=(c<<3)+(c<<2)+c;scale_coord=t>>5;end
   3:begin t=(c<<2)+(c<<1);scale_coord=t>>4;end
   default:scale_coord=c/3;
  endcase
  if(scale_coord>15) scale_coord=15;
 end endfunction
 always @* begin
  rgb=background; body=0; outline=0; code=0; rowbits=0; dg=0;
  value=0;ink=24'hffffff;size=32;count=0;total=0;left=0;top=0;pos=0;
  lx=0;ly=0;sx=0;sy=0;nx=0;ny=0;digit_scale=0;digit_w=0;digit_h=0;spacing=0;
  case(picture_index[4:1]) 0:value=rain_mm;1:value=temperature;2:value={3'd0,wind_level};3:value={5'd0,lightning_level};default:value=snow_mm;endcase
  case(warning_level)1:ink=24'h36a9e1;2:ink=24'hffe040;3:ink=24'hff8018;4:ink=24'hff3030;default:ink=24'hffffff;endcase
  if(enable && exercise_complete) begin
   digit_scale=4; digit_w=20; digit_h=28; left=CENTER_X-34; top=CENTER_Y-14; pos=(x-left)/24; lx=(x-left)%24; ly=y-top;
   case(pos)0:dg=digit_font("E");1:dg=digit_font("N");2:dg=digit_font("D");default:dg=0;endcase
   if(x>=left && x<left+68 && y>=top && y<top+digit_h && lx<digit_w && dg[34-(ly/4)*5-(lx/4)]) rgb=24'h20ff80;
  end else if(enable && picture_index<10 && !picture_index[0]) begin
   digit_scale=4; digit_w=20; digit_h=28; count=(value>=100)?3:((value>=10)?2:1); total=count*digit_w+(count-1)*4; left=DATA_CENTER_X-total/2; top=CENTER_Y-digit_h/2; pos=(x-left)/24; lx=(x-left)%24; ly=y-top;
   if(count==3) case(pos)0:dg=digit_font("0"+value/100);1:dg=digit_font("0"+(value/10)%10);2:dg=digit_font("0"+value%10);default:dg=0;endcase
   else if(count==2) case(pos)0:dg=digit_font("0"+(value/10)%10);1:dg=digit_font("0"+value%10);default:dg=0;endcase
   else if(pos==0) dg=digit_font("0"+value%10);
   if(x>=left && x<left+total && y>=top && y<top+digit_h && lx<digit_w && dg[34-(ly/4)*5-(lx/4)]) rgb=ink;
  end else if(enable && picture_index<10) begin
   case((warning_level>=3)?breath_phase:0) 0:size=32;1:size=36;2:size=40;3:size=44;default:size=48;endcase
   count=(warning_level==0)?3:4; spacing=4;
   case(size)
    32:begin total=(count==3)?104:140;left=(count==3)?338:320;top=96;end
    36:begin total=(count==3)?116:156;left=(count==3)?332:312;top=94;end
    40:begin total=(count==3)?128:172;left=(count==3)?326:304;top=92;end
    44:begin total=(count==3)?140:188;left=(count==3)?320:296;top=90;end
    default:begin total=(count==3)?152:204;left=(count==3)?314:288;top=88;end
   endcase
   if(x>=left-2 && x<left+total+2 && y>=top-2 && y<top+size+2) begin
    if(x<left+size) begin pos=0;lx=x-left;end
    else if(x<left+size+spacing+size) begin pos=1;lx=x-(left+size+spacing);end
    else if(x<left+(size+spacing)*2+size) begin pos=2;lx=x-(left+(size+spacing)*2);end
    else begin pos=3;lx=x-(left+(size+spacing)*3);end
    ly=y-top;
    if(pos<count && lx>=0 && lx<size && ly>=0 && ly<size) begin sx=scale_coord(lx,(warning_level>=3)?breath_phase:0);sy=scale_coord(ly,(warning_level>=3)?breath_phase:0);code=warning_char(warning_level,pos);rowbits=chinese_row(code,sy);body=rowbits[15-sx];end
    // The breathing orange/red warning uses the colored glyph only.
    // Dynamic black outline pixels previously exposed a rectangular box.
    if(!body && warning_level<3) begin
     code=warning_char(warning_level,pos);
     if(lx>=2) begin sx=scale_coord(lx-2,(warning_level>=3)?breath_phase:0);sy=scale_coord(ly,(warning_level>=3)?breath_phase:0);rowbits=chinese_row(code,sy);outline=rowbits[15-sx];end
     if(lx+2<size) begin sx=scale_coord(lx+2,(warning_level>=3)?breath_phase:0);rowbits=chinese_row(code,sy);outline=outline|rowbits[15-sx];end
     if(ly>=2) begin sx=scale_coord(lx,(warning_level>=3)?breath_phase:0);sy=scale_coord(ly-2,(warning_level>=3)?breath_phase:0);rowbits=chinese_row(code,sy);outline=outline|rowbits[15-sx];end
     if(ly+2<size) begin sy=scale_coord(ly+2,(warning_level>=3)?breath_phase:0);rowbits=chinese_row(code,sy);outline=outline|rowbits[15-sx];end
    end
    if(outline && warning_level<3) rgb=24'h000000; if(body) rgb=ink;
   end
  end
 end
endmodule
