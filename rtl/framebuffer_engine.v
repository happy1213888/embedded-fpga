`timescale 1ns/1ps
// Two SDRAM frames at 0x000000 and 0x080000; two BRAM scanline buffers.
module framebuffer_engine(input clk,input rst,input pixel_clk,
    input [1:0] write_bank,input write_abort,input [18:0] pixel_address,input [23:0] pixel,
    input preview_capture,input [2:0] preview_slot,input [16:0] preview_address,
    input pixel_valid,output pixel_ready,output write_idle,
    input line_toggle,input [8:0] line_source_y,input line_bank,input [1:0] front_bank,
    input dual_fetch,input [8:0] second_source_y,input [1:0] second_front_bank,input compact_preview,input [2:0] compact_slot,
    input [9:0] read_x,input [9:0] second_read_x,input read_bank,output [23:0] line_pixel,output [23:0] second_line_pixel,
    output reg line_done_toggle,output reg line_overrun,
    output mem_request,output mem_write,output [20:0] mem_address,output [255:0] mem_data,
    input mem_ready,input mem_done,input mem_read_valid,input [2:0] mem_read_beat,input [31:0] mem_read_data);
    reg [23:0] line0[0:1023],line1[0:1023],preview_line[0:1023];
    reg [23:0] line0_q,line1_q,preview_q;
    reg read_bank_q;
    reg [255:0] write_pack,preview_write_pack;
    reg [20:0] write_address,preview_write_address,line_address;
    reg [3:0] pack_count,preview_pack_count;
    reg [1:0] line_sync;
    reg last_line,fetching,fetch_bank,fetch_second,fetch_right,inflight,transaction_write,transaction_preview;
    reg [6:0] burst_number;
    wire line_event=line_sync[1]!=last_line;
    wire preview_sample=preview_capture;
    function[20:0] preview_base;input[2:0]slot;begin case(slot)
      0:preview_base=21'd1572864;1:preview_base=21'd1649664;2:preview_base=21'd1726464;
      3:preview_base=21'd1803264;default:preview_base=21'd1880064;endcase end endfunction
    wire [20:0] compact_base=preview_base(preview_slot);
    assign pixel_ready=pack_count<8 && (!preview_sample || preview_pack_count<8);
    assign write_idle=pack_count==0 && preview_pack_count==0 && !(inflight && transaction_write);
    assign mem_request=!inflight && (fetching || pack_count==8 || preview_pack_count==8);
    assign mem_write=!fetching;
    assign mem_address=fetching?line_address+{burst_number,3'b000}:(pack_count==8?write_address:preview_write_address);
    assign mem_data=pack_count==8?write_pack:preview_write_pack;
    assign line_pixel=read_bank_q?line1_q:line0_q;
    assign second_line_pixel=preview_q;
    // Keep each RAM's synchronous read and write ports independent of the FSM.
    always @(posedge pixel_clk) begin
        line0_q<=line0[read_x];
        line1_q<=line1[read_x];
        // Clamp the preview address at both edges.  The menu compositor and
        // this synchronous RAM cross several pixel-clock registers; keeping
        // the final address at 319 prevents an out-of-window cycle from
        // exposing stale/black data at the right edge.
        preview_q<=preview_line[{read_bank,(second_read_x<160?9'd0:second_read_x>=480?9'd319:second_read_x[8:0]-9'd160)}];
        read_bank_q<=read_bank;
    end
    always @(posedge clk) begin
        if(!rst && mem_read_valid && inflight && !transaction_write && !fetch_second && !fetch_bank)
            line0[(fetch_right?10'd480:10'd0)+{burst_number,mem_read_beat}]<=mem_read_data[23:0];
        if(!rst && mem_read_valid && inflight && !transaction_write && !fetch_second && fetch_bank)
            line1[(fetch_right?10'd480:10'd0)+{burst_number,mem_read_beat}]<=mem_read_data[23:0];
        if(!rst && mem_read_valid && inflight && !transaction_write && fetch_second)
            // Each ping-pong half is 512 pixels.  A candidate line contains
            // 40 bursts x 8 pixels = 320 pixels, so the within-half address
            // is only nine bits.  Keeping burst_number's unused MSB here
            // made the concatenation 11 bits; truncation discarded fetch_bank
            // and left the odd preview buffer unwritten on hardware.
            preview_line[{fetch_bank,burst_number[5:0],mem_read_beat}]<=mem_read_data[23:0];
    end
    always @(posedge clk) begin
        line_sync<={line_sync[0],line_toggle};
        if(rst) begin
            write_pack<=0;preview_write_pack<=0;write_address<=0;preview_write_address<=0;pack_count<=0;preview_pack_count<=0;line_sync<=0;last_line<=0;
            fetching<=0;fetch_bank<=0;fetch_second<=0;fetch_right<=0;inflight<=0;transaction_write<=0;transaction_preview<=0;burst_number<=0;
            line_address<=0;line_done_toggle<=0;line_overrun<=0;
        end else begin
            if(pixel_valid && pixel_ready) begin
                write_pack[pack_count*32+:32]<={8'd0,pixel};
                if(pack_count==0) write_address<={write_bank,pixel_address};
                pack_count<=pack_count+1'b1;
                if(preview_sample) begin
                    preview_write_pack[preview_pack_count*32+:32]<={8'd0,pixel};
                    if(preview_pack_count==0) preview_write_address<=compact_base+preview_address;
                    preview_pack_count<=preview_pack_count+1'b1;
                end
            end
            if(line_event) begin
                last_line<=line_sync[1];
                if(fetching) line_overrun<=1;
                else begin fetching<=1;fetch_bank<=line_bank;fetch_second<=0;fetch_right<=0;line_address<={front_bank,19'd0}+line_source_y*21'd640;burst_number<=0;end
            end
            if(mem_request && mem_ready) begin inflight<=1;transaction_write<=mem_write;transaction_preview<=mem_write&&pack_count!=8;end
            if(mem_done && inflight) begin
                inflight<=0;
                if(transaction_write) begin if(transaction_preview) preview_pack_count<=0;else pack_count<=0;end
                else if(dual_fetch && !fetch_second && !fetch_right && burst_number==19) begin
                    fetch_right<=1;line_address<={front_bank,19'd0}+line_source_y*21'd640+21'd480;burst_number<=0;
                end else if(dual_fetch && !fetch_second && fetch_right && burst_number==19) begin
                    fetch_second<=1;fetch_right<=0;line_address<=compact_preview?(preview_base(compact_slot)+({12'd0,second_source_y}<<8)+({12'd0,second_source_y}<<6)):({second_front_bank,19'd0}+second_source_y*21'd640+21'd160);burst_number<=0;
                end else if((fetch_second&&burst_number==39)||(!dual_fetch&&burst_number==79)) begin fetching<=0;fetch_second<=0;fetch_right<=0;line_done_toggle<=~line_done_toggle;end
                else burst_number<=burst_number+1'b1;
            end
            if(write_abort && !(inflight && transaction_write)) begin pack_count<=0;preview_pack_count<=0;end
        end
    end
endmodule

