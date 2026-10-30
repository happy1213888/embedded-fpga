`timescale 1ns/1ps
module image_effects(input [23:0] pixel,input signed [8:0] brightness,
    input [8:0] contrast,output [23:0] result);
    // Independent unsigned channel datapaths avoid signed function mapping.
    image_effect_channel red(pixel[23:16],brightness,contrast,result[23:16]);
    image_effect_channel green(pixel[15:8],brightness,contrast,result[15:8]);
    image_effect_channel blue(pixel[7:0],brightness,contrast,result[7:0]);
endmodule

module image_effect_channel(input [7:0] value,input [8:0] brightness,
    input [8:0] contrast,output [7:0] result);
    // Same floor-and-clamp formula, expressed using unsigned positive and
    // negative terms. XOR maps signed brightness [-256,255] to [0,511].
    wire [8:0] biased_brightness=brightness ^ 9'h100;
    wire [16:0] scaled_value=value * contrast;
    wire [18:0] positive_term={2'b00,scaled_value}
        + {3'b000,biased_brightness,7'b0000000} + 19'd16384;
    wire [18:0] negative_term={3'b000,contrast,7'b0000000}+19'd32768;
    wire [18:0] difference=positive_term-negative_term;
    assign result=(positive_term<=negative_term)?8'd0:
        (difference>=19'd32640)?8'd255:difference[14:7];
endmodule
