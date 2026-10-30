`timescale 1ns/1ps
// Gray-pointer dual-clock FIFO, 512 signed PCM samples (~10.7ms at 48kHz).
module audio_pcm_fifo(input wr_clk,input wr_rst,input wr_en,input signed [15:0] wr_data,output full,output [9:0] wr_level,
    input rd_clk,input rd_rst,input rd_en,output reg signed [15:0] rd_data,output empty,output [9:0] rd_level);
    localparam AW=9; reg [15:0] mem[0:(1<<AW)-1];
    reg [AW:0] wbin,wgray,rbin,rgray; reg [AW:0] rgray_w1,rgray_w2,wgray_r1,wgray_r2;
    wire [AW:0] wbin_inc=wbin+1'b1; wire [AW:0] rbin_inc=rbin+1'b1;
    wire [AW:0] wgray_inc=(wbin_inc>>1)^wbin_inc; wire [AW:0] rgray_inc=(rbin_inc>>1)^rbin_inc;
    wire [AW:0] wbin_next=(wr_en&&!full)?wbin_inc:wbin; wire [AW:0] rbin_next=(rd_en&&!empty)?rbin_inc:rbin;
    wire [AW:0] wgray_next=(wbin_next>>1)^wbin_next; wire [AW:0] rgray_next=(rbin_next>>1)^rbin_next;
    // Look-ahead full detection intentionally reserves one slot.  This keeps
    // the decision in Gray code and off the 100 MHz gray2bin/subtract path.
    // Effective safe capacity is 511 samples (~10.65 ms at 48 kHz).
    assign full=wgray_inc=={~rgray_w2[AW:AW-1],rgray_w2[AW-2:0]}; assign empty=rgray==wgray_r2;
    function [AW:0] gray2bin(input [AW:0] g); integer i; begin gray2bin[AW]=g[AW];for(i=AW-1;i>=0;i=i-1) gray2bin[i]=gray2bin[i+1]^g[i];end endfunction
    assign wr_level=wbin-gray2bin(rgray_w2); assign rd_level=gray2bin(wgray_r2)-rbin;
    always @(posedge wr_clk) begin rgray_w1<=rgray;rgray_w2<=rgray_w1;if(wr_rst) begin wbin<=0;wgray<=0;rgray_w1<=0;rgray_w2<=0;end else if(wr_en&&!full) begin mem[wbin[AW-1:0]]<=wr_data;wbin<=wbin_next;wgray<=wgray_next;end end
    always @(posedge rd_clk) begin wgray_r1<=wgray;wgray_r2<=wgray_r1;if(rd_rst) begin rbin<=0;rgray<=0;wgray_r1<=0;wgray_r2<=0;rd_data<=0;end else if(rd_en&&!empty) begin rd_data<=mem[rbin[AW-1:0]];rbin<=rbin_next;rgray<=rgray_next;end end
endmodule
