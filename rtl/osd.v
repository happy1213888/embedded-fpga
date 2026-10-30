`timescale 1ns/1ps
module osd(input [9:0] x,input [9:0] y,input [23:0] background,
    input enable,input signed [8:0] brightness,input [8:0] contrast,input [2:0] scale,
    input auto_mode,input [4:0] picture_index,input [5:0] file_count,input busy,
    input [7:0] error,output reg [23:0] rgb,input [95:0] diagnostic);
    function [7:0] hexchar;
        input [3:0] n;
        begin hexchar=n<10?8'd48+n:8'd65+n-10;end
    endfunction
    reg [7:0] character;
    reg [34:0] glyph;
    reg [8:0] magnitude;
    reg [6:0] col;
    reg [2:0] row;
    function [34:0] font;
        input [7:0] c;
        begin case(c)
            "0":font=35'b01110_10001_10011_10101_11001_10001_01110;
            "1":font=35'b00100_01100_00100_00100_00100_00100_01110;
            "2":font=35'b01110_10001_00001_00010_00100_01000_11111;
            "3":font=35'b11110_00001_00001_01110_00001_00001_11110;
            "4":font=35'b00010_00110_01010_10010_11111_00010_00010;
            "5":font=35'b11111_10000_10000_11110_00001_00001_11110;
            "6":font=35'b01110_10000_10000_11110_10001_10001_01110;
            "7":font=35'b11111_00001_00010_00100_01000_01000_01000;
            "8":font=35'b01110_10001_10001_01110_10001_10001_01110;
            "9":font=35'b01110_10001_10001_01111_00001_00001_01110;
            "A":font=35'b01110_10001_10001_11111_10001_10001_10001;
            "B":font=35'b11110_10001_10001_11110_10001_10001_11110;
            "C":font=35'b01111_10000_10000_10000_10000_10000_01111;
            "D":font=35'b11110_10001_10001_10001_10001_10001_11110;
            "E":font=35'b11111_10000_10000_11110_10000_10000_11111;
            "F":font=35'b11111_10000_10000_11110_10000_10000_10000;
            "H":font=35'b10001_10001_10001_11111_10001_10001_10001;
            "I":font=35'b01110_00100_00100_00100_00100_00100_01110;
            "L":font=35'b10000_10000_10000_10000_10000_10000_11111;
            "M":font=35'b10001_11011_10101_10101_10001_10001_10001;
            "N":font=35'b10001_11001_11001_10101_10011_10011_10001;
            "O":font=35'b01110_10001_10001_10001_10001_10001_01110;
            "P":font=35'b11110_10001_10001_11110_10000_10000_10000;
            "R":font=35'b11110_10001_10001_11110_10100_10010_10001;
            "S":font=35'b01111_10000_10000_01110_00001_00001_11110;
            "T":font=35'b11111_00100_00100_00100_00100_00100_00100;
            "U":font=35'b10001_10001_10001_10001_10001_10001_01110;
            "W":font=35'b10001_10001_10001_10101_10101_11011_10001;
            "X":font=35'b10001_10001_01010_00100_01010_10001_10001;
            "+":font=35'b00000_00100_00100_11111_00100_00100_00000;
            "-":font=35'b00000_00000_00000_11111_00000_00000_00000;
            "/":font=35'b00001_00001_00010_00100_01000_10000_10000;
            ":":font=35'b00000_00100_00100_00000_00100_00100_00000;
            ".":font=35'b00000_00000_00000_00000_00000_00100_00100;
            default:font=0;
        endcase end
    endfunction
    always @* begin
        rgb=background;character=" ";magnitude=brightness<0?-brightness:brightness;
        col=(x-16)>>4;row=(y-16)>>4;
        if(row==0) case(col)
            0:character="P";1:character="I";2:character="C";3:character=":";
            4:character="0"+(picture_index+1)/10;5:character="0"+(picture_index+1)%10;
            6:character="/";7:character="0"+file_count/10;8:character="0"+file_count%10;
            10:character=auto_mode?"A":"M";11:character=auto_mode?"U":"A";
            12:character=auto_mode?"T":"N";13:character=auto_mode?"O":" ";
            15:character=busy?"L":" ";16:character=busy?"O":" ";17:character=busy?"A":" ";18:character=busy?"D":" ";
        endcase
        if(row==1) case(col)
            0:character="B";1:character=":";2:character=brightness<0?"-":"+";
            3:character="0"+magnitude/100;4:character="0"+(magnitude/10)%10;5:character="0"+magnitude%10;
            8:character="C";9:character=":";10:character="0"+contrast/100;
            11:character="0"+(contrast/10)%10;12:character="0"+contrast%10;
        endcase
        if(row==2) case(col)
            0:character="S";1:character=":";
            2:character=scale==4?"1":"0";
            3:character=scale==4?"0":scale==0?"0":scale==1?"2":scale==2?"5":"7";
            4:character=scale==1||scale==3?"5":"0";5:character="%";
            8:character="E";9:character=":";10:character="0"+error/100;
            11:character="0"+(error/10)%10;12:character="0"+error%10;
        endcase
        if(row==3) begin
            case(col) 0:character="M";1:character="E";2:character="M";3:character=":";endcase
            if(col>=4 && col<12) character=hexchar(diagnostic[95-(col-4)*4 -:4]);
        end
        if(row==4) begin
            case(col) 0:character="R";1:character="A";2:character="W";3:character=":";endcase
            if(col>=4 && col<10) character=hexchar(diagnostic[63-(col-4)*4 -:4]);
        end
        if(row==5) begin
            case(col) 0:character="O";1:character="U";2:character="T";3:character=":";endcase
            if(col>=4 && col<10) character=hexchar(diagnostic[39-(col-4)*4 -:4]);
        end
        if(row==6) case(col)
            0:character="S";1:character="D";2:character="1";3:character="6";
            5:character="D";6:character="8";8:character="C";9:character="R";10:character="C";
            12:character="O";13:character="N";
        endcase
        glyph=font(character);
        if(enable && x>=16 && x<336 && y>=16 && y<128) begin
            rgb={2'b00,background[23:18],2'b00,background[15:10],2'b00,background[7:2]};
            if(((x-16)&15)<10 && ((y-16)&15)<14 && glyph[34-(((y-16)&15)>>1)*5-(((x-16)&15)>>1)]) rgb=24'hf0fff0;
        end
    end
endmodule



