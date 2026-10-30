`timescale 1ns/1ps
// Frame-synchronous fade controller.  A completed image is faded through
// black, committed on a frame boundary, then faded back to full brightness.
module transition_fade #(
    parameter integer HALF_FRAMES = 16
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_tick,
    input  wire       image_valid,
    input  wire       change_event,
    output reg        commit_pulse,
    output reg        active,
    output reg  [8:0] gain
);
    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_OUT  = 2'd1;
    localparam [1:0] ST_IN   = 2'd2;

    reg [1:0] state;
    reg [7:0] frame_count;

    function [8:0] fade_level;
        input [7:0] step;
        reg [16:0] scaled;
        begin
            scaled = step * 9'd256;
            fade_level = 9'd256 - scaled / HALF_FRAMES;
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state        <= ST_IDLE;
            frame_count  <= 8'd0;
            commit_pulse <= 1'b0;
            active       <= 1'b0;
            gain         <= 9'd256;
        end else begin
            commit_pulse <= 1'b0;
            if (frame_tick) begin
                case (state)
                    ST_IDLE: begin
                        gain <= 9'd256;
                        if (change_event) begin
                            if (!image_valid) begin
                                // The first image appears immediately; there is
                                // no previous valid frame to fade away.
                                commit_pulse <= 1'b1;
                                active       <= 1'b0;
                            end else begin
                                state       <= ST_OUT;
                                frame_count <= 8'd0;
                                active      <= 1'b1;
                            end
                        end
                    end
                    ST_OUT: begin
                        if (frame_count == HALF_FRAMES-1) begin
                            gain         <= 9'd0;
                            frame_count  <= 8'd0;
                            state        <= ST_IN;
                            commit_pulse <= 1'b1;
                        end else begin
                            frame_count <= frame_count + 1'b1;
                            gain <= fade_level(frame_count + 1'b1);
                        end
                    end
                    default: begin
                        if (frame_count == HALF_FRAMES-1) begin
                            gain        <= 9'd256;
                            frame_count <= 8'd0;
                            state       <= ST_IDLE;
                            active      <= 1'b0;
                        end else begin
                            frame_count <= frame_count + 1'b1;
                            gain <= 9'd256 - fade_level(frame_count + 1'b1);
                        end
                    end
                endcase
            end
        end
    end
endmodule

module transition_gain(
    input  wire [23:0] pixel,
    input  wire [8:0]  gain,
    output wire [23:0] result
);
    wire [16:0] red_scaled   = pixel[23:16] * gain;
    wire [16:0] green_scaled = pixel[15:8]  * gain;
    wire [16:0] blue_scaled  = pixel[7:0]   * gain;
    assign result[23:16] = gain[8] ? pixel[23:16] : red_scaled[15:8];
    assign result[15:8]  = gain[8] ? pixel[15:8]  : green_scaled[15:8];
    assign result[7:0]   = gain[8] ? pixel[7:0]   : blue_scaled[15:8];
endmodule
