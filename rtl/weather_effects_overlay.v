`timescale 1ns/1ps
module weather_effects_overlay(
 input clk,input rst,input frame_tick,input pause,input enable,
 input[9:0]x,input[9:0]y,input[4:0]picture_index,input[2:0]weather_level,
 input[23:0]background,output reg[23:0]rgb,output reg lightning_pulse);
 reg[15:0]lfsr;reg[9:0]phase;reg[1:0]slow_div;reg[2:0]level_smooth;
 // Level-dependent lightning cadence, derived only from the existing phase
 // counter so no extra timer/state machine is required.  phase advances once
 // every three frames.  Higher warnings shorten the dark interval and orange/
 // red add a brief secondary flash near the end of each cycle.
 // Pure phase-bit decoding keeps the five cadences visually distinct without
 // adding wide comparators to this already dense pixel pipeline.
 wire lightning_gate0=~phase[5]&~phase[4]&~phase[3];              // rare, long interval
 wire lightning_gate1=~phase[4]&~phase[3];                        // low rate
 wire lightning_gate2=~phase[3];                                  // even on/off
 wire lightning_gate3=~phase[3]||(phase[3]&phase[2]&~phase[1]);    // long flash plus short second flash
 wire lightning_gate4=~(phase[2]&phase[1]);                        // high rate
 wire lightning_active=picture_index==6&&!pause&&
   (level_smooth==0?lightning_gate0:level_smooth==1?lightning_gate1:
    level_smooth==2?lightning_gate2:level_smooth==3?lightning_gate3:lightning_gate4);
 integer group,density,t,u,v,ly,wave,arc,ball,drift,band_base,band_shift,dx,curve_y,move_x,bolt_x;reg hit;reg[23:0]ink;
 wire protected_text=(x>=210&&x<450&&y>=45&&y<160)||(y<32);
 always @(posedge clk)begin
  if(rst)begin lfsr<=16'h5a3c;phase<=0;slow_div<=0;level_smooth<=0;lightning_pulse<=0;end
  else if(frame_tick&&!pause)begin
   lfsr<={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
   if(slow_div==2)begin slow_div<=0;phase<=phase+1'b1;end else slow_div<=slow_div+1'b1;
   if(level_smooth<weather_level)level_smooth<=level_smooth+1'b1;else if(level_smooth>weather_level)level_smooth<=level_smooth-1'b1;
   // Reuse the existing three-frame animation phase.  phase[3] produces a
   // deterministic 24-frame on/off cycle (about 0.4 s each at 60 Hz) without
   // a separate state machine that can be cleared during vertical blanking.
   lightning_pulse<=lightning_active;
  end
 end
 always @* begin
  rgb=background;hit=0;ink=24'hffffff;group=picture_index>>1;density=level_smooth+1;
  t=phase>>(level_smooth>=3?0:1);u=0;v=0;ly=0;wave=0;arc=0;ball=0;drift=0;
  band_base=0;band_shift=0;dx=0;curve_y=0;move_x=0;bolt_x=0;
  if(enable&&!pause&&!picture_index[0]&&picture_index<10&&!protected_text&&y<400)begin
   case(group)
    0:begin
     u=(x+t)&63;v=(y-t)&63;
     hit=(v>=3&&v<(20+density*2))&&((u+v==30)||(u+v==31)||(u+v==62)||(u+v==63));
     ink=level_smooth>=3?24'h9de4ff:24'h62b6e8;
    end
    1:begin
     if(x<165||x>=475)begin v=(y+t)&127;ly=v&63;u=(x<320)?(x&63):((639-x)&63);
      case(ly[5:3])0:wave=8;1:wave=10;2:wave=14;3:wave=16;4:wave=14;5:wave=10;6:wave=6;default:wave=8;endcase
      hit=(u>=wave&&u<=wave+3)&&(ly<52)&&((v>>6)<density);end
     ink=level_smooth>=3?24'hff6b2c:24'hef8b3c;
    end
    2:begin
     // One gentle curve is copied at fixed vertical intervals, producing
     // eight continuous parallel wind bands without sharp corners.
     // 1.5x the previous travel speed.
     move_x=((t<<1)+t)&511;
     dx=(x+move_x)&511;
     if(dx<=340)begin
      if(dx<100)curve_y=dx>>3;
      else if(dx<220)curve_y=12+((dx-100)>>2);
      else curve_y=42+((dx-220)>>3);
      v=y-curve_y;
      // Keep every wind band below the subtitle/data safe boundary.
      hit=(y>=190)&&((v>=205&&v<=206)||(v>=238&&v<=239)||
           (v>=271&&v<=272)||(v>=304&&v<=305)||
           (v>=337&&v<=338)||(v>=370&&v<=371)||
           (v>=403&&v<=404)||(v>=436&&v<=437));
      // One small arrow at the upper-left tip of each band.
      if(dx<12)begin
       u=dx>>1;
       hit=hit||(y>=190&&((v>=205-u&&v<=206-u)||(v>=205+u&&v<=206+u)||
                (v>=238-u&&v<=239-u)||(v>=238+u&&v<=239+u)||
                (v>=271-u&&v<=272-u)||(v>=271+u&&v<=272+u)||
                (v>=304-u&&v<=305-u)||(v>=304+u&&v<=305+u)||
                (v>=337-u&&v<=338-u)||(v>=337+u&&v<=338+u)||
                (v>=370-u&&v<=371-u)||(v>=370+u&&v<=371+u)||
                (v>=403-u&&v<=404-u)||(v>=403+u&&v<=404+u)||
                (v>=436-u&&v<=437-u)||(v>=436+u&&v<=437+u)));
      end
     end
     ink=level_smooth>=3?24'hc2b0f2:24'h91b8d8;
    end
    3:begin
     // Simple three-segment bolt with only two clear turns.
      if(lightning_active&&x>=440&&x<610&&y>=55&&y<325)begin u=x-440;v=y-55;
      // Rotate the three-segment bolt clockwise by roughly 12 degrees.
      if(v<80)bolt_x=135-(v>>2)-(v>>3);
      else if(v<125)bolt_x=105+((v-80)>>1)+((v-80)>>3);
      else bolt_x=133-((v-125)>>2)-((v-125)>>3);
      // Fourteen-pixel body remains a clean three-segment bolt, but has enough
      // contrast to survive HDMI scaling and bright sky backgrounds.
      hit=(u+2>=bolt_x&&u<=bolt_x+(level_smooth>=3?14:11));
     end
     ink=level_smooth>=3?24'hfff36a:24'hffd94a;
    end
    default:begin
     case(phase[5:4])0:drift=0;1:drift=12;2:drift=20;default:drift=10;endcase
     u=(x+drift+(y>>5))&31;v=(y-t)&31;ball=level_smooth>=3?4:level_smooth>=1?3:2;
     hit=(u<ball&&v<ball)&&((((x>>5)^(y>>5))&7)<(density+4));
     ink=x[6]?24'hffffff:24'hccecff;
    end
   endcase
   if(hit)rgb=ink;
  end
 end
endmodule
