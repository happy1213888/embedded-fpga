`timescale 1ns/1ps
// EG4S20 2M x32 SDRAM: 4 banks, 2048 rows, 256 columns. BL8, CL3.
// Request addresses are word addresses and must be aligned to eight words.
module sdram_burst #(parameter POWER_CYCLES=20000,parameter REFRESH_CYCLES=700)(
    input clk,input rst,output reg initialized,
    input request,input write,input [20:0] address,input [255:0] write_data,
    output ready,output reg done,output reg read_valid,output reg [2:0] read_beat,
    output reg [31:0] read_data,
    output sdram_clk,output reg [10:0] sdram_addr,output reg [1:0] sdram_ba,
    output reg sdram_ras_n,output reg sdram_cas_n,output reg sdram_we_n,
    output sdram_cs_n,output sdram_cke,output [3:0] sdram_dm,inout [31:0] sdram_dq,input clk_sdram);
    localparam POWER=0,PRE_ALL=1,WAIT_INIT=2,REF1=3,REF2=4,MODE=5,IDLE=6,
        ACT=7,RCD=8,RD_CMD=9,RD_WAIT=10,RD_DATA=11,WR_CMD=12,WR_DATA=13,RECOVER=14,REFRESH=15;
    reg [3:0] state,next_init;
    reg [15:0] wait_count;
    reg [9:0] refresh_count;
    reg [20:0] saved_addr;
    reg [255:0] saved_data;
    reg saved_write;
    reg [2:0] beat;
    (* preserve = "true", keep = "true" *) reg driving;
    reg [3:0] command_state;
    reg [31:0] dq_sample;
    // Dedicated PLL output forwards the SDRAM clock; returned DQ is captured one cycle later.
    assign sdram_clk=clk_sdram;
    assign sdram_cs_n=0;assign sdram_cke=1;assign sdram_dm=0;
    assign sdram_dq=driving?saved_data[31:0]:32'bz;
    always @(posedge clk) dq_sample<=sdram_dq;
    assign ready=state==IDLE && refresh_count<REFRESH_CYCLES;
    always @* begin
        command_state=state;
        case(state)
            POWER:if(wait_count==0) command_state=PRE_ALL;
            PRE_ALL,REF1,REF2,MODE,REFRESH:command_state=WAIT_INIT;
            WAIT_INIT:if(wait_count==0) command_state=next_init;
            IDLE:if(refresh_count>=REFRESH_CYCLES) command_state=REFRESH;else if(request) command_state=ACT;
            ACT:command_state=RCD;
            RCD:if(wait_count==0) command_state=saved_write?WR_CMD:RD_CMD;
            RD_CMD:command_state=RD_WAIT;
            RD_WAIT:if(wait_count==0) command_state=RD_DATA;
            RD_DATA:if(beat==7) command_state=RECOVER;
            WR_CMD:command_state=WR_DATA;
            WR_DATA:if(beat==7) command_state=RECOVER;
            RECOVER:if(wait_count==0) command_state=IDLE;
        endcase
    end
    // Register command/address/OE at the same edge that advances the transaction FSM.
    always @(posedge clk) begin
        sdram_addr<=0;sdram_ba<=state==IDLE?address[20:19]:saved_addr[20:19];
        sdram_ras_n<=1;sdram_cas_n<=1;sdram_we_n<=1;
        if(state==ACT && saved_write) driving<=1;
        if(state==RECOVER || rst) driving<=0;
        case(command_state)
            PRE_ALL:begin sdram_ras_n<=0;sdram_we_n<=0;sdram_addr[10]<=1;end
            REF1,REF2,REFRESH:begin sdram_ras_n<=0;sdram_cas_n<=0;end
            MODE:begin sdram_ras_n<=0;sdram_cas_n<=0;sdram_we_n<=0;sdram_ba<=0;sdram_addr<=11'h033;end
            ACT:begin sdram_ras_n<=0;sdram_addr<=address[18:8];end
            RD_CMD:begin sdram_cas_n<=0;sdram_addr<={3'b100,saved_addr[7:0]};end
            WR_CMD:begin sdram_cas_n<=0;sdram_we_n<=0;sdram_addr<={3'b100,saved_addr[7:0]};end
        endcase
        if(rst) begin sdram_addr<=0;sdram_ba<=0;sdram_ras_n<=1;sdram_cas_n<=1;sdram_we_n<=1;driving<=0;end
    end
    always @(posedge clk) begin
        done<=0;read_valid<=0;
        if(rst) begin state<=POWER;wait_count<=POWER_CYCLES;refresh_count<=0;initialized<=0;
            saved_addr<=0;saved_data<=0;saved_write<=0;beat<=0;next_init<=0;read_beat<=0;read_data<=0;
        end else begin
            if(initialized && refresh_count<1023) refresh_count<=refresh_count+1'b1;
            case(state)
                POWER:if(wait_count==0) state<=PRE_ALL;else wait_count<=wait_count-1'b1;
                PRE_ALL:begin state<=WAIT_INIT;wait_count<=3;next_init<=REF1;end
                WAIT_INIT:if(wait_count==0) state<=next_init;else wait_count<=wait_count-1'b1;
                REF1:begin state<=WAIT_INIT;wait_count<=8;next_init<=REF2;end
                REF2:begin state<=WAIT_INIT;wait_count<=8;next_init<=MODE;end
                MODE:begin state<=WAIT_INIT;wait_count<=3;next_init<=IDLE;initialized<=1;refresh_count<=0;end
                IDLE:if(refresh_count>=REFRESH_CYCLES) state<=REFRESH;
                    else if(request) begin saved_addr<=address;saved_write<=write;saved_data<=write_data;state<=ACT;end
                ACT:begin state<=RCD;wait_count<=1;end
                RCD:if(wait_count==0) begin state<=saved_write?WR_CMD:RD_CMD;beat<=0;end else wait_count<=wait_count-1'b1;
                RD_CMD:begin state<=RD_WAIT;wait_count<=4;end
                RD_WAIT:if(wait_count==0) begin
                    read_data<=dq_sample;read_beat<=0;read_valid<=1;beat<=1;state<=RD_DATA;
                end else wait_count<=wait_count-1'b1;
                RD_DATA:begin
                    read_data<=dq_sample;read_beat<=beat;read_valid<=1;
                    if(beat==7) begin state<=RECOVER;wait_count<=4;end else beat<=beat+1'b1;
                end
                WR_CMD:begin state<=WR_DATA;beat<=1;saved_data<=saved_data>>32;end
                WR_DATA:begin saved_data<=saved_data>>32;if(beat==7) begin state<=RECOVER;wait_count<=5;end else beat<=beat+1'b1;end
                RECOVER:if(wait_count==0) begin state<=IDLE;done<=1;end else wait_count<=wait_count-1'b1;
                REFRESH:begin state<=WAIT_INIT;wait_count<=8;next_init<=IDLE;refresh_count<=0;end
                default:state<=POWER;
            endcase
        end
    end
endmodule
