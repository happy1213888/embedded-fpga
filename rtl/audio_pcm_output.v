`timescale 1ns/1ps
module audio_pcm_output(input clk,input rst,input pause,input mute,input [8:0] gain,input [8:0] weather_gain,input lightning_boost,input fifo_empty,input signed [15:0] fifo_data,
    output reg fifo_read,output reg sample_clock,output reg [15:0] sample,output reg [31:0] played_samples,
    output reg spectrum_clock,output reg signed [15:0] spectrum_sample);
    reg [24:0] accumulator; reg primed; reg signed [24:0] scaled;reg signed[17:0] weather_sample;reg[8:0] effective_weather_gain;
    always @(posedge clk) begin
      sample_clock<=0;fifo_read<=0;spectrum_clock<=0;
      if(rst) begin accumulator<=0;sample<=0;primed<=0;scaled<=0;played_samples<=0;spectrum_sample<=0;end
      // Keep the HDMI audio sample cadence alive while programme playback is
      // paused.  The FIFO and played_samples stay frozen, so the first WAV
      // word and subtitle position are preserved, but the HDMI sink continues
      // receiving silent packets and does not need to reacquire audio at the
      // first automatic page change.
      else if(accumulator>=25000000-48000) begin
        accumulator<=accumulator+48000-25000000;sample_clock<=1;
        if(pause) begin sample<=0;spectrum_sample<=0;
        end else if(!fifo_empty) begin
          if(primed && !mute) begin
           if(lightning_boost && weather_gain<9'd218) effective_weather_gain=weather_gain+9'd38; else effective_weather_gain=weather_gain;
           case(effective_weather_gain)
            9'd102:weather_sample=($signed(fifo_data)>>>1)-($signed(fifo_data)>>>3)+($signed(fifo_data)>>>5);
            9'd141:weather_sample=($signed(fifo_data)>>>1)+($signed(fifo_data)>>>5)+($signed(fifo_data)>>>6);
            9'd179:weather_sample=($signed(fifo_data)>>>1)+($signed(fifo_data)>>>3)+($signed(fifo_data)>>>4)+($signed(fifo_data)>>>7);
            9'd218:weather_sample=$signed(fifo_data)-($signed(fifo_data)>>>3)-($signed(fifo_data)>>>5);
            default:weather_sample=$signed(fifo_data);
           endcase
           // Dedicated analyser tap: capture the real decoded/programme PCM
           // inside this module, after weather shaping but before transition
           // gain.  The strobe and data are therefore aligned by construction.
           spectrum_sample<=weather_sample[15:0];spectrum_clock<=1;
           scaled=$signed(weather_sample)*$signed({1'b0,gain});sample<=scaled>>>8;
          end else begin sample<=0;spectrum_sample<=0;end
          fifo_read<=1;
          // Match the D44 reference exactly: every accepted FIFO word advances
          // the common audio/subtitle position, including the priming read.
          primed<=1;played_samples<=played_samples+1'b1;
        end else begin sample<=0;spectrum_sample<=0;primed<=0;end
      end else accumulator<=accumulator+48000;
    end
endmodule
