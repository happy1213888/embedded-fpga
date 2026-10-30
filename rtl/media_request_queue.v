`timescale 1ns/1ps
// Pixel-clock request FIFO.  Requests are retained while SD/BMP/audio loading
// or a fade is active, then dispatched one at a time in original order.
module media_request_queue #(parameter DEPTH=8,parameter HOLD_FRAMES=18)(
 input clk,input rst,input frame_tick,input source_toggle,input[4:0]source_index,
 input dispatch_ready,input transition_active,
 output reg dispatch_toggle,output reg[4:0]dispatch_index,output full,output reg[3:0]count);
 reg source_last;reg[4:0]fifo[0:DEPTH-1];reg[2:0]rd_ptr,wr_ptr;reg[5:0]hold_frames;integer i;
 wire source_event=source_toggle!=source_last;
 assign full=count==DEPTH;
 always@(posedge clk)begin
  if(rst)begin source_last<=0;rd_ptr<=0;wr_ptr<=0;count<=0;dispatch_toggle<=0;dispatch_index<=0;hold_frames<=0;for(i=0;i<DEPTH;i=i+1)fifo[i]<=0;end
  else begin
   if(source_event)begin
    source_last<=source_toggle;
    if(!full)begin fifo[wr_ptr]<=source_index;wr_ptr<=wr_ptr+1'b1;count<=count+1'b1;end
   end
   if(frame_tick)begin
    if(transition_active)hold_frames<=HOLD_FRAMES;
    else if(hold_frames!=0)hold_frames<=hold_frames-1'b1;
   end
   if(dispatch_ready&&!transition_active&&hold_frames==0&&count!=0&&!source_event)begin
    dispatch_index<=fifo[rd_ptr];rd_ptr<=rd_ptr+1'b1;count<=count-1'b1;dispatch_toggle<=~dispatch_toggle;
   end
  end
 end
endmodule
