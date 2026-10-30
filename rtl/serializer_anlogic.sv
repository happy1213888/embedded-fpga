`timescale 1ns/1ps
// hdl-util HDMI serializer interface, implemented using Anlogic DDR output FFs.
module serializer #(parameter int NUM_CHANNELS=3,parameter real VIDEO_RATE=25E6)(
    input logic clk_pixel,input logic clk_pixel_x5,input logic reset,
    input logic [9:0] tmds_internal[NUM_CHANNELS-1:0],
    output wire [NUM_CHANNELS-1:0] tmds,output wire tmds_clock);
    reg toggle;
    reg [2:0] sync;
    wire load=sync[2]^sync[1];
    reg [9:0] shift[NUM_CHANNELS-1:0];
    reg [9:0] clock_shift;
    wire [9:0] next_clock=load?10'b0000011111:clock_shift;
    always @(posedge clk_pixel) if(reset) toggle<=0;else toggle<=~toggle;
    always @(posedge clk_pixel_x5) begin
        if(reset) begin sync<=0;clock_shift<=10'b0000011111;end
        else begin sync<={sync[1:0],toggle};clock_shift<={next_clock[1:0],next_clock[9:2]};end
    end
    genvar i;
    generate for(i=0;i<NUM_CHANNELS;i=i+1) begin: lanes
        wire [9:0] next_word=load?tmds_internal[i]:shift[i];
        always @(posedge clk_pixel_x5) if(reset) shift[i]<=0;else shift[i]<=next_word>>2;
        EG_LOGIC_ODDR #(.ASYNCRST("ENABLE")) ddr(.q(tmds[i]),.clk(clk_pixel_x5),.d0(next_word[0]),.d1(next_word[1]),.rst(reset));
    end endgenerate
    EG_LOGIC_ODDR #(.ASYNCRST("ENABLE")) clock_ddr(.q(tmds_clock),.clk(clk_pixel_x5),.d0(next_clock[0]),.d1(next_clock[1]),.rst(reset));
endmodule
