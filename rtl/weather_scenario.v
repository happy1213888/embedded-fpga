`timescale 1ns/1ps
module weather_scenario #(
    parameter integer SECOND_FRAMES=60,
    parameter integer ORANGE_SECONDS=3,
    parameter integer AUTO_FRAMES=300
)(
    input wire clk,input wire rst,input wire frame_tick,input wire busy,input wire pause,
    input wire [2:0] mode,input wire [3:0] press,input wire long_reset,
    input wire auto_mode,input wire [4:0] current_index,input wire [5:0] file_count,input wire menu_choose,input wire [2:0] menu_group,
    output reg request_toggle,output reg [4:0] requested_index,
    output reg [7:0] rain_mm,output reg [7:0] temperature,
    output reg [4:0] wind_level,output reg [2:0] lightning_level,
    output reg [7:0] snow_mm,
    output reg [2:0] warning_level,output reg [2:0] breath_phase,
    output reg alert_page,output reg exercise_complete
);
    reg [6:0] second_frames;
    reg one_second;
    reg [1:0] orange_seconds;
    reg [2:0] lightning_seconds;
    reg [8:0] auto_frames;
    reg boot_requested;
    wire [2:0] viewed_group=current_index[4:1];
    wire risk_page=!current_index[0] && current_index<10;
    // The warning level is combinational from the stored value.  A manual
    // increment updates that value with a nonblocking assignment, so detect
    // the red boundary from the pre-increment value as well.
    wire manual_increment=mode==3'b001 && press[1] && risk_page;
    wire manual_reaches_red=manual_increment && (
        (viewed_group==0 && rain_mm>=140) ||
        (viewed_group==1 && temperature>=42) ||
        (viewed_group==2 && wind_level>=11) ||
        (viewed_group==3 && lightning_level>=3) ||
        (viewed_group==4 && snow_mm>=140));
    // Detect the automatic step that enters orange.  warning_level is based
    // on the value before this clock edge, so this explicit look-ahead keeps
    // the orange hold from starting one second late.
    wire auto_reaches_orange=one_second && risk_page && !alert_page && !exercise_complete && (
        (viewed_group==0 && rain_mm>=90 && rain_mm<100) ||
        (viewed_group==1 && temperature==39) ||
        (viewed_group==2 && wind_level==9) ||
        (viewed_group==3 && lightning_seconds==4 && lightning_level==2) ||
        (viewed_group==4 && snow_mm>=90 && snow_mm<100));

    function [2:0] level_for;
        input [2:0] group_id;
        input [7:0] rain_value;
        input [7:0] temperature_value;
        input [4:0] wind_value;
        input [2:0] lightning_value;
        input [7:0] snow_value;
        begin
            case(group_id)
                0: level_for=rain_value<30?0:rain_value<50?1:rain_value<100?2:rain_value<150?3:4;
                1: level_for=temperature_value<35?0:temperature_value<38?1:temperature_value<40?2:temperature_value<43?3:4;
                2: level_for=wind_value<6?0:wind_value<8?1:wind_value<10?2:wind_value<12?3:4;
                3: level_for=lightning_value>4?4:lightning_value;
                default: level_for=snow_value<30?0:snow_value<50?1:snow_value<100?2:snow_value<150?3:4;
            endcase
        end
    endfunction

    task request_page;
        input [4:0] page;
        begin requested_index<=page;request_toggle<=~request_toggle;end
    endtask

    task reset_data;
        begin
            rain_mm<=0;temperature<=25;wind_level<=5;lightning_level<=0;snow_mm<=0;
            orange_seconds<=0;lightning_seconds<=0;alert_page<=0;breath_phase<=0;
        end
    endtask
    task reset_from_group;input[2:0]g;begin
        if(g<=0) rain_mm<=0;if(g<=1) temperature<=25;if(g<=2) wind_level<=5;
        if(g<=3) lightning_level<=0;if(g<=4) snow_mm<=0;
        orange_seconds<=0;lightning_seconds<=0;alert_page<=0;breath_phase<=0;
    end endtask

    always @* warning_level=level_for(viewed_group,rain_mm,temperature,wind_level,lightning_level,snow_mm);

    always @(posedge clk) begin
        one_second<=0;
        if(rst) second_frames<=0;
        else if(!pause && frame_tick) begin
            if(second_frames==SECOND_FRAMES-1) begin second_frames<=0;one_second<=1;end
            else second_frames<=second_frames+1'b1;
        end
    end

    always @(posedge clk) begin
        if(rst) begin
            request_toggle<=0;requested_index<=0;boot_requested<=0;auto_frames<=0;
            exercise_complete<=0;reset_data();
        end else if(menu_choose) begin
            reset_from_group(menu_group);exercise_complete<=0;auto_frames<=0;request_page({menu_group,1'b0});
        end else if(!pause) begin
            begin
            if(warning_level>=3) begin
                if(second_frames < (SECOND_FRAMES/8)) breath_phase<=0;
                else if(second_frames < (SECOND_FRAMES*2/8)) breath_phase<=1;
                else if(second_frames < (SECOND_FRAMES*3/8)) breath_phase<=2;
                else if(second_frames < (SECOND_FRAMES*4/8)) breath_phase<=3;
                else if(second_frames < (SECOND_FRAMES*5/8)) breath_phase<=4;
                else if(second_frames < (SECOND_FRAMES*6/8)) breath_phase<=3;
                else if(second_frames < (SECOND_FRAMES*7/8)) breath_phase<=2;
                else breath_phase<=1;
            end else breath_phase<=0;
            if(long_reset) begin
                reset_data();exercise_complete<=0;auto_frames<=0;
                if(!busy) request_page(0);
            end else begin
                if(!boot_requested && file_count!=0 && !busy) begin boot_requested<=1;request_page(0);end
                if(mode==3'b001 && current_index<10) begin
                    if(press[0]) case(viewed_group)
                        0:rain_mm<=rain_mm>=10?rain_mm-10:0;
                        1:temperature<=temperature>25?temperature-1:25;
                        2:wind_level<=wind_level>5?wind_level-1:5;
                        3:lightning_level<=lightning_level>0?lightning_level-1:0;
                        default:snow_mm<=snow_mm>=10?snow_mm-10:0;
                    endcase
                    if(press[1]) case(viewed_group)
                        0:rain_mm<=rain_mm>=240?250:rain_mm+10;
                        1:temperature<=temperature>=49?50:temperature+1;
                        2:wind_level<=wind_level>=16?17:wind_level+1;
                        3:lightning_level<=lightning_level>=3?4:lightning_level+1;
                        default:snow_mm<=snow_mm>=240?250:snow_mm+10;
                    endcase
                end
                if(one_second && risk_page && !alert_page && !exercise_complete) begin
                    // Grow only below orange.  Once orange is reached, freeze
                    // the displayed value so red cannot steal the three-second
                    // orange warning interval (especially temperature/wind).
                    if(warning_level<3) case(viewed_group)
                        0:rain_mm<=rain_mm>=240?250:rain_mm+10;
                        1:temperature<=temperature>=49?50:temperature+1;
                        2:wind_level<=wind_level>=16?17:wind_level+1;
                        3:begin
                            if(lightning_seconds==4)begin lightning_seconds<=0;lightning_level<=lightning_level>=3?4:lightning_level+1;end
                            else lightning_seconds<=lightning_seconds+1'b1;
                        end
                        4:snow_mm<=snow_mm>=240?250:snow_mm+10;
                    endcase
                    // The entry tick establishes orange.  The following three
                    // complete one-second ticks hold orange, then request the
                    // advice page.  If the loader is busy, saturate instead of
                    // wrapping and dispatch at the first available tick.
                    if(warning_level==3) begin
                        if(orange_seconds==ORANGE_SECONDS-1) begin
                            if(!busy) begin orange_seconds<=0;alert_page<=1;request_page(current_index+1'b1);end
                            else orange_seconds<=orange_seconds;
                        end else orange_seconds<=orange_seconds+1'b1;
                    end else if(auto_reaches_orange) orange_seconds<=0;
                    else orange_seconds<=0;
                end
                // A key press may move directly into red between one-second
                // ticks.  Red warning always preempts immediately.
                if(risk_page && !alert_page && !exercise_complete &&
                   (warning_level==4 || manual_reaches_red) && !busy) begin
                    orange_seconds<=0;alert_page<=1;request_page(current_index+1'b1);
                end
                if(!risk_page) orange_seconds<=0;
                if(mode==3'b000 && file_count!=0 && !alert_page) begin
                    // While a load is active, base further key presses on the
                    // last requested page so rapid presses form a true sequence.
                    if(press[0]) request_page(busy?(requested_index==0?file_count-1'b1:requested_index-1'b1):(current_index==0?file_count-1'b1:current_index-1'b1));
                    else if(press[1]) request_page(busy?(requested_index+1'b1>=file_count?0:requested_index+1'b1):(current_index+1'b1>=file_count?0:current_index+1'b1));
                end
                if(frame_tick && auto_mode && !busy && !alert_page && !exercise_complete) begin
                    if(auto_frames==AUTO_FRAMES-1) begin auto_frames<=0;request_page(current_index+1'b1>=file_count?0:current_index+1'b1);end
                    else auto_frames<=auto_frames+1'b1;
                end else if(!auto_mode) auto_frames<=0;
                if(mode==3'b110) begin
                    if(press[0] && !busy) begin reset_data();exercise_complete<=0;request_page(0);end
                    if(press[3] && alert_page && current_index[0] && !busy) begin
                        alert_page<=0;
                        if(current_index==9) begin reset_data();exercise_complete<=0;request_page(0);end
                        else request_page(current_index+1'b1);
                    end
                    if(press[1] && exercise_complete && !busy) begin reset_data();exercise_complete<=0;request_page(0);end
                end
            end
            end
        end
    end
endmodule

