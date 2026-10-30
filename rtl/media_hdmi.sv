`timescale 1ns/1ps
module media_hdmi(input clk_pixel,input clk_serial,input rst,input [23:0] rgb,
    input clk_audio,input [15:0] audio_sample,output [9:0] x,output [9:0] y,
    output [2:0] tmds,output tmds_clock);
    wire [15:0] audio_words[1:0];
    assign audio_words[0]=audio_sample;assign audio_words[1]=audio_sample;
    hdmi #(.VIDEO_ID_CODE(1),.DVI_OUTPUT(0),.VIDEO_REFRESH_RATE(59.5238095238),
        .AUDIO_RATE(48000),.AUDIO_BIT_WIDTH(16),.AUDIO_CLOCK_ENABLE(1),.VENDOR_NAME("ANLOGIC "),
        .PRODUCT_DESCRIPTION("MEDIA PLAYER    "),.START_Y(480)) transmitter(
        .clk_pixel_x5(clk_serial),.clk_pixel(clk_pixel),.clk_audio(clk_pixel),.audio_sample_enable(clk_audio),.reset(rst),
        .rgb(rgb),.audio_sample_word(audio_words),.tmds(tmds),.tmds_clock(tmds_clock),
        .cx(x),.cy(y),.frame_width(),.frame_height(),.screen_width(),.screen_height());
endmodule
