`timescale 1ns/1ps
// Streaming RIFF/WAVE decoder for PCM, 48 kHz, 16-bit, mono assets.
module wav_pcm_decoder(
    input clk,input rst,input start,
    input [7:0] byte_data,input byte_valid,output byte_ready,input file_done,
    output reg sample_valid,input sample_ready,output reg signed [15:0] sample,
    output reg format_ready,output reg data_started,output reg stream_done,output reg [3:0] error,
    output reg [31:0] sample_position);
    localparam HEADER=0,CHUNK_ID=1,CHUNK_SIZE=2,FMT_DATA=3,SKIP=4,PCM=5;
    reg [2:0] state; reg [5:0] pos; reg [31:0] chunk_id,chunk_size,left;
    reg [15:0] audio_format,channels,bits_per_sample; reg [31:0] sample_rate;
    reg [7:0] low_byte; reg pcm_low; reg [31:0] riff_id,wave_id;
    assign byte_ready=!sample_valid || sample_ready;
    always @(posedge clk) begin
      if(rst || start) begin state<=HEADER;pos<=0;chunk_id<=0;chunk_size<=0;left<=0;sample_valid<=0;
        format_ready<=0;data_started<=0;stream_done<=0;error<=0;sample_position<=0;pcm_low<=1;
        audio_format<=0;channels<=0;bits_per_sample<=0;sample_rate<=0;riff_id<=0;wave_id<=0;
      end else begin
        stream_done<=0;
        if(sample_valid && sample_ready) sample_valid<=0;
        if(byte_valid && byte_ready) case(state)
          HEADER: begin
            if(pos<4) riff_id<={byte_data,riff_id[31:8]};
            if(pos>=8 && pos<12) wave_id<={byte_data,wave_id[31:8]};
            if(pos==11) begin
              if(riff_id!=32'h46464952 || {byte_data,wave_id[31:8]}!=32'h45564157) begin error<=1;state<=SKIP;left<=32'hffffffff;end
              else begin state<=CHUNK_ID;pos<=0;chunk_id<=0;end
            end else pos<=pos+1'b1;
          end
          CHUNK_ID: begin chunk_id<={byte_data,chunk_id[31:8]}; if(pos==3) begin pos<=0;chunk_size<=0;state<=CHUNK_SIZE;end else pos<=pos+1'b1; end
          CHUNK_SIZE: begin
            chunk_size<={byte_data,chunk_size[31:8]};
            if(pos==3) begin
              left<={byte_data,chunk_size[31:8]};pos<=0;
              if(chunk_id==32'h20746d66) begin state<=FMT_DATA;audio_format<=0;channels<=0;sample_rate<=0;bits_per_sample<=0;end
              else if(chunk_id==32'h61746164) begin
                if(!format_ready) begin error<=3;state<=SKIP;end else begin state<=PCM;data_started<=1;pcm_low<=1;end
              end else state<=SKIP;
            end else pos<=pos+1'b1;
          end
          FMT_DATA: begin
            case(pos)
              0:audio_format[7:0]<=byte_data;1:audio_format[15:8]<=byte_data;
              2:channels[7:0]<=byte_data;3:channels[15:8]<=byte_data;
              4:sample_rate[7:0]<=byte_data;5:sample_rate[15:8]<=byte_data;6:sample_rate[23:16]<=byte_data;7:sample_rate[31:24]<=byte_data;
              14:bits_per_sample[7:0]<=byte_data;15:bits_per_sample[15:8]<=byte_data;
            endcase
            left<=left-1'b1;pos<=pos+1'b1;
            if(left==1) begin
              if(audio_format!=1 || channels!=1 || sample_rate!=48000 || {byte_data,bits_per_sample[7:0]}!=16) error<=2;
              else format_ready<=1;
              state<=CHUNK_ID;pos<=0;chunk_id<=0;
            end
          end
          SKIP: begin if(left!=32'hffffffff) begin left<=left-1'b1;if(left==1) begin state<=CHUNK_ID;pos<=0;chunk_id<=0;end end end
          PCM: begin
            left<=left-1'b1;
            if(pcm_low) begin low_byte<=byte_data;pcm_low<=0;end
            else begin sample<={byte_data,low_byte};sample_valid<=1;sample_position<=sample_position+1'b1;pcm_low<=1;end
            if(left==1) begin stream_done<=1;state<=SKIP;left<=32'hffffffff;end
          end
        endcase
        if(file_done && state!=PCM && left!=32'hffffffff && !stream_done && error==0) error<=4;
      end
    end
endmodule
