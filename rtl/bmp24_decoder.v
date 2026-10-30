`timescale 1ns/1ps
// Centre crop BI_RGB BGR24; TEST_ONLY permits legacy 640 input.
module bmp24_decoder #(parameter TEST_ONLY=0, parameter MIN_WIDTH=680)(input clk,input rst,input start,input [7:0] byte_data,
    input byte_valid,output byte_ready,input file_done,
    output reg pixel_valid,input pixel_ready,output reg [23:0] pixel,
    output reg [18:0] pixel_address,output reg image_done,output reg [3:0] error,
    output reg [15:0] source_width,output reg [15:0] source_height);
    reg [15:0] signature,planes,bits_per_pixel;
    reg [31:0] height,width,data_offset,dib_size,compression,position;
    reg [15:0] x,storage_y,crop_x,crop_y;
    reg [13:0] row_byte,row_stride,row_pixels;
    reg [18:0] output_row;
    reg [9:0] output_x;
    reg [1:0] component;
    reg [7:0] blue,green;
    reg active,header_checked,header_pause,top_down,payload_started,payload_complete,file_ended;
    reg [18:0] accepted_pixels;
    wire [31:0] absolute_height=height[31]?(~height+32'd1):height;
    wire in_row=storage_y>=crop_y && storage_y<crop_y+16'd480;
    wire in_crop=x>=crop_x && x<crop_x+16'd640 && in_row;
    assign byte_ready=(!pixel_valid || pixel_ready) && (!active || header_checked || !header_pause);
    always @(posedge clk) begin
        image_done<=0;
        if(rst || start) begin
            position<=0;x<=0;storage_y<=0;row_byte<=0;row_stride<=0;row_pixels<=0;component<=0;
            output_row<=0;output_x<=0;
            pixel_valid<=0;pixel<=0;pixel_address<=0;image_done<=0;error<=0;active<=start;
            header_checked<=0;header_pause<=0;top_down<=0;payload_started<=0;payload_complete<=0;file_ended<=0;
            accepted_pixels<=0;blue<=0;green<=0;source_width<=0;source_height<=0;crop_x<=0;crop_y<=0;
            signature<=0;planes<=0;bits_per_pixel<=0;
            height<=0;width<=0;data_offset<=0;dib_size<=0;compression<=0;
        end else begin
            if(pixel_valid && pixel_ready) begin pixel_valid<=0;accepted_pixels<=accepted_pixels+1'b1;end
            if(active && !header_checked && header_pause) begin
                header_checked<=1;
                // At this point position already points to the first byte
                // after the 54-byte BMP header.  Arm payload processing here;
                // otherwise the first post-header byte can never set the flag
                // and the framebuffer remains completely black.
                payload_started<=position>=data_offset;
                // Latch the derived geometry independently of header validity.
                // Invalid files stop below, while valid files retain identical
                // behavior.  This keeps the long height validation comparator
                // out of the output_row clock-enable timing path.
                source_width<=width[15:0];source_height<=absolute_height[15:0];
                crop_x<=(width-640)>>1;
                crop_y<=top_down?((absolute_height-480)>>1):(absolute_height-480-((absolute_height-480)>>1));
                output_row<=top_down?0:306560;row_pixels<=width*3;
                row_stride<=((width*3+3)>>2)<<2;
                if(signature!=16'h4d42 || planes!=1 || bits_per_pixel!=24 || compression!=0)
                    begin error<=1;active<=0;end
                else if(width<(TEST_ONLY?640:MIN_WIDTH) || width>4096 || absolute_height<480 || absolute_height>4096)
                    begin error<=3;active<=0;end
                else if(data_offset<54 || data_offset>65536 || dib_size<40 || dib_size>data_offset-14)
                    begin error<=4;active<=0;end
            end
            if(byte_valid && byte_ready) begin
                position<=position+1'b1;
                if(active && !header_checked) begin
                    if(position==53) header_pause<=1;
                    case(position[5:0])
                        0:signature[7:0]<=byte_data;1:signature[15:8]<=byte_data;
                        10:data_offset[7:0]<=byte_data;11:data_offset[15:8]<=byte_data;
                        12:data_offset[23:16]<=byte_data;13:data_offset[31:24]<=byte_data;
                        14:dib_size[7:0]<=byte_data;15:dib_size[15:8]<=byte_data;
                        16:dib_size[23:16]<=byte_data;17:dib_size[31:24]<=byte_data;
                        18:width[7:0]<=byte_data;19:width[15:8]<=byte_data;
                        20:width[23:16]<=byte_data;21:width[31:24]<=byte_data;
                        22:height[7:0]<=byte_data;23:height[15:8]<=byte_data;
                        24:height[23:16]<=byte_data;25:begin height[31:24]<=byte_data;top_down<=byte_data[7];end
                        26:planes[7:0]<=byte_data;27:planes[15:8]<=byte_data;
                        28:bits_per_pixel[7:0]<=byte_data;29:bits_per_pixel[15:8]<=byte_data;
                        30:compression[7:0]<=byte_data;31:compression[15:8]<=byte_data;
                        32:compression[23:16]<=byte_data;33:compression[31:24]<=byte_data;
                    endcase
                end else if(active && header_checked && payload_started && !payload_complete && error==0) begin
                    if(row_byte<row_pixels) begin
                        case(component)
                            0:begin blue<=byte_data;component<=1;end
                            1:begin green<=byte_data;component<=2;end
                            2:begin
                                if(in_crop) begin
                                    pixel<={byte_data,green,blue};
                                    pixel_address<=output_row+output_x;
                                    output_x<=output_x+1'b1;
                                    pixel_valid<=1;
                                end
                                x<=x+1'b1;component<=0;
                            end
                        endcase
                    end
                    if(row_byte==row_stride-1'b1) begin
                        row_byte<=0;x<=0;component<=0;output_x<=0;
                        if(in_row) output_row<=top_down?output_row+19'd640:output_row-19'd640;
                        if(storage_y==source_height-1'b1) payload_complete<=1;
                        else storage_y<=storage_y+1'b1;
                    end else row_byte<=row_byte+1'b1;
                end
            end
            if(file_done) file_ended<=1;
            // EOF gates success even if the cropped window completed earlier.
            if(file_ended && active && !pixel_valid) begin
                active<=0;
                if(!payload_complete || accepted_pixels!=307200) error<=2;
                else if(error==0) image_done<=1;
            end
        end
    end
endmodule
