`timescale 1ns/1ps
module subtitle_timeline(input clk,input rst,input [31:0] played_samples,input [4:0] picture_index,output reg visible,output reg [2:0] sentence,output reg [31:0] sentence_samples,output reg [31:0] sentence_duration);
reg[4:0]last_picture;reg[31:0]last_played,t,loop_samples,speech_end_samples;
// Hardware measurement shows the male announcement begins at the start of
// the playable second-page PCM timeline.  Do not discard the first 48,000
// samples here; that created the observed one-second subtitle lag.
localparam[31:0] SPEECH_START=32'd0;
always @* begin case(picture_index)
 1,3:begin loop_samples=1056000;speech_end_samples=960000;end
 5,7:begin loop_samples=576000;speech_end_samples=480000;end
 9:begin loop_samples=624000;speech_end_samples=528000;end
 default:begin loop_samples=1;speech_end_samples=0;end endcase end
always @(posedge clk)begin
 if(rst)begin t<=0;last_played<=0;last_picture<=picture_index;end
 else if(picture_index!=last_picture||played_samples<last_played)begin t<=0;last_played<=played_samples;last_picture<=picture_index;end
 else if(played_samples!=last_played)begin last_played<=played_samples;if(t+(played_samples-last_played)>=loop_samples)t<=t+(played_samples-last_played)-loop_samples;else t<=t+(played_samples-last_played);end
end
// Begin the crawl during the one-second environmental lead-in.  The bitmap
// pacing constants cover the complete 0..speech_end interval, so delaying the
// start made the subtitle remain roughly one second behind the announcement.
always @* begin
 visible=speech_end_samples>SPEECH_START&&t>=SPEECH_START&&t<speech_end_samples;
 sentence=0;
 sentence_samples=t>=SPEECH_START?t-SPEECH_START:0;
 sentence_duration=speech_end_samples>SPEECH_START?speech_end_samples-SPEECH_START:1;
end
endmodule
