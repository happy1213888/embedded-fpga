`timescale 1ns/1ps
// SD v2 SPI reader, including OCR/CCS detection and sector CRC16 verification.
module sd_spi_reader # (parameter CLK_HZ=100000000,parameter LOW_DIV=124,parameter HIGH_DIV=2)(
    input clk,input rst,input read_start,input [31:0] read_lba,
    output reg ready,output reg busy,output reg [7:0] data,
    output reg data_valid,output reg done,output reg [3:0] error,
    output reg sd_cs_n,output sd_clk,output sd_mosi,input sd_miso,
    output [95:0] diagnostic);
    localparam POWER=0,CLOCKS=1,PRE=2,SEND=3,RESP=4,TAIL=5,
        DISPATCH=6,RELEASE=7,IDLE=8,TOKEN=9,DATA=10,CRC_HI=11,CRC_LO=12,FAULT=13,CMD_CRC=14;
    reg [3:0] state,after_release;
    reg [31:0] timer,arg,ocr,latched_lba;
    reg [5:0] command;
    reg [7:0] cmd_crc,divider,tx;
    reg [39:0] command_bits;
    reg [6:0] command_crc7;
    reg [5:0] crc_bit;
    wire [6:0] next_crc7={command_crc7[5:0],1'b0} ^ ((command_crc7[6]^command_bits[39])?7'h09:7'h00);
    reg r1_idle,r1_ok;
    reg [9:0] index;
    reg [2:0] byte_index;
    reg start,inflight,high_capacity;
    wire spi_busy,spi_done;
    wire [7:0] rx;
    reg [15:0] crc,received_crc;
    reg [15:0] head_bytes,tail_bytes;
    assign diagnostic={latched_lba,crc,received_crc,head_bytes,tail_bytes};
    function [15:0] crc16;
        input [15:0] old; input [7:0] value;
        reg [15:0] c; integer i;
        begin c=old ^ {value,8'd0};for(i=0;i<8;i=i+1) c=c[15]?(c<<1)^16'h1021:c<<1;crc16=c;end
    endfunction
    spi_byte spi(clk,rst,start,tx,divider,sd_miso,sd_clk,sd_mosi,spi_busy,spi_done,rx);
    task issue;
        input [5:0] cmd;input [31:0] a;
        begin command<=cmd;arg<=a;command_bits<={2'b01,cmd,a};command_crc7<=0;crc_bit<=0;byte_index<=0;state<=CMD_CRC;timer<=0; end
    endtask
    always @(posedge clk) begin
        start<=0;data_valid<=0;done<=0;
        if(rst) begin
            state<=POWER;timer<=0;ready<=0;busy<=1;error<=0;sd_cs_n<=1;
            divider<=LOW_DIV;inflight<=0;index<=0;high_capacity<=0;crc<=0;
            command<=0;arg<=0;ocr<=0;latched_lba<=0;r1_idle<=0;r1_ok<=0;cmd_crc<=0;
            byte_index<=0;tx<=8'hff;data<=0;received_crc<=0;after_release<=0;
            head_bytes<=0;tail_bytes<=0;command_bits<=0;command_crc7<=0;crc_bit<=0;
        end else begin
            if(spi_done) inflight<=0;
            if(state!=IDLE && state!=POWER && state!=FAULT) begin
                timer<=timer+1'b1;
                if(timer==CLK_HZ) begin state<=FAULT;error<=1;ready<=0;sd_cs_n<=1;busy<=0;end
            end
            if(timer!=CLK_HZ || state==IDLE || state==POWER || state==FAULT) case(state)
                POWER: if(timer==CLK_HZ/100) begin timer<=0;index<=0;state<=CLOCKS;end else timer<=timer+1'b1;
                CLOCKS: begin
                    if(!inflight) begin tx<=8'hff;start<=1;inflight<=1;end
                    if(spi_done) if(index==9) issue(0,0);else index<=index+1'b1;
                end
                CMD_CRC: begin
                    command_crc7<=next_crc7;command_bits<={command_bits[38:0],1'b0};
                    if(crc_bit==39) begin cmd_crc<={next_crc7,1'b1};state<=PRE;end
                    else crc_bit<=crc_bit+1'b1;
                end
                PRE: begin
                    sd_cs_n<=1;
                    if(!inflight) begin tx<=8'hff;start<=1;inflight<=1;end
                    if(spi_done) begin sd_cs_n<=0;state<=SEND;byte_index<=0;end
                end
                SEND: begin
                    if(!inflight) begin
                        case(byte_index)
                            0:tx<={2'b01,command};1:tx<=arg[31:24];2:tx<=arg[23:16];
                            3:tx<=arg[15:8];4:tx<=arg[7:0];default:tx<=cmd_crc;
                        endcase
                        start<=1;inflight<=1;
                    end
                    if(spi_done) if(byte_index==5) begin state<=RESP;index<=0;end else byte_index<=byte_index+1'b1;
                end
                RESP: begin
                    if(!inflight) begin tx<=8'hff;start<=1;inflight<=1;end
                    if(spi_done) begin
                        if(!rx[7]) begin
                            r1_idle<=rx==1;r1_ok<=rx==0;ocr<=0;byte_index<=0;
                            if(command==8 || command==58) state<=TAIL;
                            else state<=DISPATCH;
                        end else if(index==255) begin state<=FAULT;error<=2;ready<=0;sd_cs_n<=1;busy<=0;end
                        else index<=index+1'b1;
                    end
                end
                TAIL: begin
                    if(!inflight) begin tx<=8'hff;start<=1;inflight<=1;end
                    if(spi_done) begin ocr<={ocr[23:0],rx};if(byte_index==3) state<=DISPATCH;else byte_index<=byte_index+1'b1;end
                end
                DISPATCH: case(command)
                    0: if(r1_idle) issue(8,32'h1aa);else issue(0,0);
                    8: if(r1_idle && ocr[11:0]==12'h1aa) issue(55,0);else begin state<=FAULT;error<=3;busy<=0;sd_cs_n<=1;end
                    55: if(r1_idle || r1_ok) issue(41,32'h40000000);else begin state<=FAULT;error<=3;busy<=0;sd_cs_n<=1;end
                    41: if(r1_ok) issue(58,0);else issue(55,0);
                    58: if(r1_ok && ocr[31]) begin high_capacity<=ocr[30];if(ocr[30]) issue(59,1);else issue(16,512);end
                        else begin state<=FAULT;error<=3;busy<=0;sd_cs_n<=1;end
                    16: if(r1_ok) issue(59,1); else begin state<=FAULT;error<=3;busy<=0;sd_cs_n<=1;end
                    59: if(r1_ok) begin after_release<=IDLE;state<=RELEASE;end
                        else begin state<=FAULT;error<=7;ready<=0;busy<=0;sd_cs_n<=1;end
                    17: if(r1_ok) begin state<=TOKEN;timer<=0;end else begin state<=FAULT;error<=4;ready<=0;busy<=0;sd_cs_n<=1;end
                    default: begin state<=FAULT;error<=3;end
                endcase
                RELEASE: begin
                    sd_cs_n<=1;
                    if(!inflight) begin tx<=8'hff;start<=1;inflight<=1;end
                    if(spi_done) begin state<=after_release;ready<=1;busy<=0;divider<=HIGH_DIV;end
                end
                IDLE: begin
                    timer<=0;
                    if(read_start) begin busy<=1;latched_lba<=read_lba;issue(17,high_capacity?read_lba:(read_lba<<9));end
                end
                TOKEN: begin
                    if(!inflight) begin tx<=8'hff;start<=1;inflight<=1;end
                    if(spi_done && rx!=8'hff) begin
                        if(rx==8'hfe) begin state<=DATA;index<=0;crc<=0;end
                        else begin state<=FAULT;error<=5;ready<=0;busy<=0;sd_cs_n<=1;end
                    end
                end
                DATA: begin
                    if(spi_done) begin
                        if(index<2) head_bytes<={head_bytes[7:0],rx};
                        tail_bytes<={tail_bytes[7:0],rx};
                    end
                    if(!inflight) begin tx<=8'hff;start<=1;inflight<=1;end
                    if(spi_done) begin data<=rx;data_valid<=1;crc<=crc16(crc,rx);if(index==511) state<=CRC_HI;else index<=index+1'b1;end
                end
                CRC_HI: begin
                    if(!inflight) begin tx<=8'hff;start<=1;inflight<=1;end
                    if(spi_done) begin received_crc[15:8]<=rx;state<=CRC_LO;end
                end
                CRC_LO: begin
                    if(!inflight) begin tx<=8'hff;start<=1;inflight<=1;end
                    if(spi_done) begin
                        received_crc[7:0]<=rx;
                        if({received_crc[15:8],rx}==crc) begin done<=1;after_release<=IDLE;state<=RELEASE;end
                        else begin state<=FAULT;error<=6;ready<=0;busy<=0;sd_cs_n<=1;end
                    end
                end
                FAULT: begin busy<=0;sd_cs_n<=1;end
                default:state<=FAULT;
            endcase
        end
    end
endmodule

