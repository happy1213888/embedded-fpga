`timescale 1ns/1ps
module keys_control #(
    parameter integer DEBOUNCE=500000,
    parameter integer LONG_PRESS_FRAMES=120
)(
    input clk,input rst,input [3:0] keys_n,input [3:0] switches,input frame_tick,input [1:0] menu_target,input menu_dec,input menu_inc,
    output reg [3:0] press,output wire [2:0] mode,output reg long_reset,
    output reg signed [8:0] brightness,output reg [8:0] contrast,output reg[6:0] brightness_percent,output reg[6:0] contrast_percent,
    output reg [2:0] scale,output reg osd,output reg auto_mode
);
    reg [3:0] key_meta,key_sync,key_stable;
    reg [3:0] sw_meta,sw_sync;
    reg [19:0] count[0:3];
    reg signed [8:0] next_brightness;
    reg [8:0] next_contrast;
    reg [2:0] next_scale;
    reg next_osd;
    reg [7:0] reset_hold;
    integer i;
    function signed[8:0] brightness_for;input[6:0]p;begin case(p)0:brightness_for=-128;5:brightness_for=-115;10:brightness_for=-102;15:brightness_for=-90;20:brightness_for=-77;25:brightness_for=-64;30:brightness_for=-51;35:brightness_for=-38;40:brightness_for=-26;45:brightness_for=-13;50:brightness_for=0;55:brightness_for=13;60:brightness_for=26;65:brightness_for=38;70:brightness_for=51;75:brightness_for=64;80:brightness_for=77;85:brightness_for=90;90:brightness_for=102;95:brightness_for=115;default:brightness_for=127;endcase end endfunction
    function[8:0] contrast_for;input[6:0]p;begin case(p)0:contrast_for=0;5:contrast_for=13;10:contrast_for=26;15:contrast_for=38;20:contrast_for=51;25:contrast_for=64;30:contrast_for=77;35:contrast_for=90;40:contrast_for=102;45:contrast_for=115;50:contrast_for=128;55:contrast_for=141;60:contrast_for=154;65:contrast_for=166;70:contrast_for=179;75:contrast_for=192;80:contrast_for=205;85:contrast_for=218;90:contrast_for=230;95:contrast_for=243;default:contrast_for=256;endcase end endfunction
    assign mode={sw_sync[0],sw_sync[1],sw_sync[2]};

    always @(posedge clk) begin
        key_meta<=keys_n;key_sync<=key_meta;sw_meta<=switches;sw_sync<=sw_meta;press<=0;
        if(rst) begin
            key_meta<=15;key_sync<=15;key_stable<=15;sw_meta<=0;sw_sync<=0;press<=0;
            for(i=0;i<4;i=i+1) count[i]<=0;
        end else for(i=0;i<4;i=i+1) begin
            if(key_sync[i]==key_stable[i]) count[i]<=0;
            else if(count[i]==DEBOUNCE-1) begin key_stable[i]<=key_sync[i];count[i]<=0;if(!key_sync[i]) press[i]<=1;end
            else count[i]<=count[i]+1'b1;
        end
    end

    always @(posedge clk) begin
        if(rst) begin
            brightness<=0;contrast<=128;brightness_percent<=50;contrast_percent<=50;scale<=2;osd<=1;auto_mode<=0;
            next_brightness<=0;next_contrast<=128;next_scale<=2;next_osd<=1;
            reset_hold<=0;long_reset<=0;
        end else begin
            long_reset<=0;
            // KEY3 is reserved for the weather selection menu.
            if(mode==3'b101) begin if(press[0]) auto_mode<=0;if(press[1]) auto_mode<=1;end
            case(mode)
                3'b010: begin
                    if(press[0]&&brightness_percent>0)begin brightness_percent<=brightness_percent-5;next_brightness<=brightness_for(brightness_percent-5);end
                    else if(press[1]&&brightness_percent<100)begin brightness_percent<=brightness_percent+5;next_brightness<=brightness_for(brightness_percent+5);end
                end
                3'b011: begin
                    if(press[0]&&contrast_percent>0)begin contrast_percent<=contrast_percent-5;next_contrast<=contrast_for(contrast_percent-5);end
                    else if(press[1]&&contrast_percent<100)begin contrast_percent<=contrast_percent+5;next_contrast<=contrast_for(contrast_percent+5);end
                end
                3'b100: begin
                    if(press[0]&&next_scale>0) next_scale<=next_scale-1'b1;
                    else if(press[1]&&next_scale<4) next_scale<=next_scale+1'b1;
                end
            endcase
            if(menu_target==0) begin
                if(menu_dec&&brightness_percent>0)begin brightness_percent<=brightness_percent-5;next_brightness<=brightness_for(brightness_percent-5);end
                else if(menu_inc&&brightness_percent<100)begin brightness_percent<=brightness_percent+5;next_brightness<=brightness_for(brightness_percent+5);end
            end else if(menu_target==1) begin
                if(menu_dec&&contrast_percent>0)begin contrast_percent<=contrast_percent-5;next_contrast<=contrast_for(contrast_percent-5);end
                else if(menu_inc&&contrast_percent<100)begin contrast_percent<=contrast_percent+5;next_contrast<=contrast_for(contrast_percent+5);end
            end else if(menu_target==2) begin
                if(menu_dec&&next_scale>0) next_scale<=next_scale-1'b1;
                else if(menu_inc&&next_scale<4) next_scale<=next_scale+1'b1;
            end
            if(frame_tick) begin
                brightness<=next_brightness;contrast<=next_contrast;scale<=next_scale;osd<=next_osd;
                if(mode==3'b111 && !key_stable[0] && !key_stable[1]) begin
                    if(reset_hold==LONG_PRESS_FRAMES-1) begin long_reset<=1;reset_hold<=0;end
                    else reset_hold<=reset_hold+1'b1;
                end else reset_hold<=0;
            end
        end
    end
endmodule
