`timescale 1ns/1ps
// Read-only FAT32, MBR or superfloppy, root-directory BMP enumeration.
module fat32_bmp_reader #(parameter MAX_FILES=32,parameter ROLE_MODE=1)(
    input clk,input rst,input sd_ready,input sd_busy,input [3:0] sd_error,
    output reg sector_start,output reg [31:0] sector_lba,
    input [7:0] sector_data,input sector_valid,input sector_done,
    output reg mounted,output reg [5:0] file_count,
    input open_file,input [4:0] file_index,output reg file_start,
    output [7:0] byte_data,output byte_valid,input byte_ready,
    output reg file_done,output reg busy,output reg [3:0] error,
    input validation_done,input [3:0] validation_error,input [15:0] validation_width,validation_height,
    output reg [9:0] role_present,role_valid,output [15:0] selected_width,selected_height,
    input open_audio,input open_subtitle,input open_thumbnail,input [2:0] thumbnail_index,input abort_file,
    output reg [9:0] audio_present,output reg [9:0] subtitle_present,output reg [4:0] thumbnail_present,output [31:0] selected_size);
    localparam BOOT=0,READ=1,WAIT_SD=2,PARSE0=3,BPB=4,ROOT=5,
        ENTRY=6,ROOT_NEXT=7,FAT_ROOT=8,READY=9,FILE_SECTOR=10,
        STREAM=11,FILE_NEXT=12,FAT_FILE=13,FAIL=14,STREAM_WAIT=15,
        ADDR_SHIFT=16,ADDR_BASE=17,ADDR_SECTOR=18,INIT_DATA=19,OPEN_PREP=20,
        FAT_ROOT_COMMIT=21,FAT_FILE_COMMIT=22;
    reg [4:0] state,return_state;
    reg [2:0] spc_shift;
    reg [31:0] cluster_offset;
    reg [7:0] buffer[0:511];
    reg [7:0] buffer_q;
    reg [31:0] clusters[0:MAX_FILES-1],sizes[0:MAX_FILES-1];
    reg [31:0] audio_clusters[0:9],audio_sizes[0:9],subtitle_clusters[0:9],subtitle_sizes[0:9];
    reg [31:0] thumbnail_clusters[0:4],thumbnail_sizes[0:4];
    reg [31:0] partition,fat_base,data_base,current_cluster,root_cluster;
    reg [31:0] pending_cluster;
    reg [31:0] sectors_per_fat,file_left,chain_steps;
    reg [7:0] spc,cluster_sector,fat_count;
    reg [8:0] pointer;
    (* max_fanout = 8 *) reg [8:0] write_pointer;
    reg [31:0] watchdog;
    wire [8:0] fat_offset={current_cluster[6:0],2'b0};
    reg [15:0] boot_signature,bytes_per_sector,reserved_sectors,root_entries,fat16_size;reg bytes_per_sector_512;
    reg [7:0] boot_spc,boot_fats,partition_type;
    reg [31:0] boot_fat_size,boot_root,partition_lba,next_cluster;
    reg [7:0] entry_first,entry_attr,ext0,ext1,ext2;
    reg entry_basic_valid,entry_commit_pending;
    reg [31:0] entry_cluster,entry_cluster_q;
    reg [31:0] entry_size;
    reg directory_end;
    reg card_fault;
    reg metadata_boot,metadata_fat,metadata_dir;
    reg [63:0] entry_name;
    localparam ROLE_COUNT=(ROLE_MODE==2)?4:(ROLE_MODE==3?10:6);
    localparam [9:0] ROLE_MASK=(ROLE_MODE==2)?10'h00f:(ROLE_MODE==3?10'h3ff:10'h03f);
    reg [3:0] entry_role,entry_role_q;reg[2:0]entry_thumbnail_q;
    reg duplicate_role,duplicate_audio,duplicate_thumbnail,active_audio,active_subtitle,active_thumbnail;
    reg [4:0] active_index;
    reg [15:0] widths[0:MAX_FILES-1],heights[0:MAX_FILES-1];
    integer mi;
    wire [7:0] upper_data=(sector_data>=8'h61 && sector_data<=8'h7a)?sector_data-8'd32:sector_data;
    function [3:0] role_for_name(input [63:0] name);
        begin
        role_for_name=15;
        if(ROLE_MODE==2) begin
            case(name)
                "PIC1    ":role_for_name=0;"PIC2    ":role_for_name=1;
                "PIC3    ":role_for_name=2;"PIC4    ":role_for_name=3;
            endcase
        end else if(ROLE_MODE==3) begin
            case(name)
                "PIC01   ":role_for_name=0;"PIC02   ":role_for_name=1;
                "PIC03   ":role_for_name=2;"PIC04   ":role_for_name=3;
                "PIC05   ":role_for_name=4;"PIC06   ":role_for_name=5;
                "PIC07   ":role_for_name=6;"PIC08   ":role_for_name=7;
                "PIC09   ":role_for_name=8;"PIC10   ":role_for_name=9;
                "SUB02   ":role_for_name=1;"SUB04   ":role_for_name=3;
                "SUB06   ":role_for_name=5;"SUB08   ":role_for_name=7;
                "SUB10   ":role_for_name=9;
            endcase
        end else case(name)
            "RAIN    ":role_for_name=0;"FLOOD   ":role_for_name=1;"HEAT    ":role_for_name=2;
            "TYPHOON ":role_for_name=3;"THUNDER ":role_for_name=4;"SNOW    ":role_for_name=5;
        endcase
        end
    endfunction
    function [2:0] thumbnail_for_name(input [63:0] name);
        begin case(name)
            "THM01   ":thumbnail_for_name=0;"THM02   ":thumbnail_for_name=1;
            "THM03   ":thumbnail_for_name=2;"THM04   ":thumbnail_for_name=3;
            "THM05   ":thumbnail_for_name=4;default:thumbnail_for_name=7;
        endcase end
    endfunction
    always @* entry_role=role_for_name(entry_name);
    assign selected_width=widths[file_index];
    assign selected_height=heights[file_index];
    wire is_bmp=(ext0==8'h42 || ext0==8'h62) &&
        (ext1==8'h4d || ext1==8'h6d) && (ext2==8'h50 || ext2==8'h70);
    wire is_wav=(ext0==8'h57 || ext0==8'h77) &&
        (ext1==8'h41 || ext1==8'h61) && (ext2==8'h56 || ext2==8'h76);
    wire is_bin=(ext0==8'h42 || ext0==8'h62) && (ext1==8'h49 || ext1==8'h69) && (ext2==8'h4e || ext2==8'h6e);
    // Directory entry sizes are assembled one byte at a time.  Avoid a
    // 32-bit magnitude comparator on the byte-31 commit path: for these
    // small header minima, any non-zero upper byte already satisfies the
    // test, otherwise only the low byte needs comparing.
    wire entry_size_upper_nonzero = |entry_size[31:8];
    wire entry_size_ge_16 = entry_size_upper_nonzero || entry_size[7:0]>=8'd16;
    wire entry_size_ge_44 = entry_size_upper_nonzero || entry_size[7:0]>=8'd44;
    wire entry_size_ge_54 = entry_size_upper_nonzero || entry_size[7:0]>=8'd54;
    wire paired_roles=(role_present==ROLE_MASK) && (ROLE_MODE!=3 || (audio_present==10'h3ff && subtitle_present==10'h2aa));
    assign byte_data=buffer_q;
    assign byte_valid=state==STREAM;
    // Parallel source decode avoids a deep priority-mux chain across four
    // asynchronous metadata arrays on the 100 MHz memory-domain path.
    reg [31:0] selected_size_mux;
    reg [31:0] open_cluster_mux,open_size_mux;
    always @* begin
        case ({active_thumbnail,active_subtitle,active_audio})
            3'b100:selected_size_mux=thumbnail_sizes[active_index[2:0]];
            3'b010:selected_size_mux=subtitle_sizes[active_index];
            3'b001:selected_size_mux=audio_sizes[active_index];
            default:selected_size_mux=sizes[active_index];
        endcase
        open_cluster_mux=clusters[file_index];
        open_size_mux=sizes[file_index];
    end
    assign selected_size=selected_size_mux;
    // One synchronous read port permits a 512-byte sector BRAM.
    always @(posedge clk) begin
        if(sector_valid && state==WAIT_SD) buffer[write_pointer]<=sector_data;
        buffer_q<=buffer[pointer];
    end
    task read_sector;
        input [31:0] lba;input [4:0] next;
        begin sector_lba<=lba;return_state<=next;state<=READ;end
    endtask
    always @(posedge clk) begin
        sector_start<=0;file_start<=0;file_done<=0;
        card_fault<=sd_error!=0;
        if(sector_valid && state==WAIT_SD) write_pointer<=write_pointer+1'b1;
        if(rst) begin
            state<=BOOT;mounted<=0;file_count<=0;error<=0;busy<=1;
            partition<=0;fat_base<=0;data_base<=0;current_cluster<=0;root_cluster<=0;pending_cluster<=0;
            sectors_per_fat<=0;file_left<=0;chain_steps<=0;spc<=0;cluster_sector<=0;
            fat_count<=0;pointer<=0;write_pointer<=0;watchdog<=0;
            sector_lba<=0;return_state<=0;
            boot_signature<=0;bytes_per_sector<=0;bytes_per_sector_512<=0;reserved_sectors<=0;root_entries<=0;fat16_size<=0;
            boot_spc<=0;boot_fats<=0;partition_type<=0;boot_fat_size<=0;boot_root<=0;partition_lba<=0;
            next_cluster<=0;entry_first<=0;entry_attr<=0;ext0<=0;ext1<=0;ext2<=0;
            entry_cluster<=0;entry_cluster_q<=0;entry_size<=0;directory_end<=0;entry_basic_valid<=0;entry_commit_pending<=0;
            spc_shift<=0;cluster_offset<=0;
            card_fault<=0;
            metadata_boot<=0;metadata_fat<=0;metadata_dir<=0;
            entry_name<=0;entry_role_q<=15;entry_thumbnail_q<=7;role_present<=0;role_valid<=0;duplicate_role<=0;duplicate_audio<=0;duplicate_thumbnail<=0;active_index<=0;active_audio<=0;active_subtitle<=0;active_thumbnail<=0;audio_present<=0;subtitle_present<=0;thumbnail_present<=0;
            for(mi=0;mi<MAX_FILES;mi=mi+1) begin widths[mi]<=0;heights[mi]<=0;end
            for(mi=0;mi<10;mi=mi+1) begin audio_clusters[mi]<=0;audio_sizes[mi]<=0;subtitle_clusters[mi]<=0;subtitle_sizes[mi]<=0;end
            for(mi=0;mi<5;mi=mi+1) begin thumbnail_clusters[mi]<=0;thumbnail_sizes[mi]<=0;end
        end else if(card_fault) begin state<=FAIL;error<=1;busy<=0;end
        else begin
            if(validation_done) begin
                widths[active_index]<=validation_width;heights[active_index]<=validation_height;
                if(ROLE_MODE && active_index<ROLE_COUNT) role_valid[active_index]<=1;
            end
            if(busy && validation_error!=0 && ROLE_MODE && active_index<ROLE_COUNT) role_valid[active_index]<=0;
            // Metadata is decoded as bytes arrive, avoiding parallel asynchronous RAM reads.
            if(sector_valid) begin
                if(metadata_boot) begin
                    case(write_pointer)
                        11:bytes_per_sector[7:0]<=sector_data;
                        12:begin bytes_per_sector[15:8]<=sector_data;bytes_per_sector_512<={sector_data,bytes_per_sector[7:0]}==16'd512;end
                        13:boot_spc<=sector_data;
                        14:reserved_sectors[7:0]<=sector_data;
                        15:reserved_sectors[15:8]<=sector_data;
                        16:boot_fats<=sector_data;
                        17:root_entries[7:0]<=sector_data;
                        18:root_entries[15:8]<=sector_data;
                        22:fat16_size[7:0]<=sector_data;
                        23:fat16_size[15:8]<=sector_data;
                        36:boot_fat_size[7:0]<=sector_data;
                        37:boot_fat_size[15:8]<=sector_data;
                        38:boot_fat_size[23:16]<=sector_data;
                        39:boot_fat_size[31:24]<=sector_data;
                        44:boot_root[7:0]<=sector_data;
                        45:boot_root[15:8]<=sector_data;
                        46:boot_root[23:16]<=sector_data;
                        47:boot_root[31:24]<=sector_data;
                        450:partition_type<=sector_data;
                        454:partition_lba[7:0]<=sector_data;
                        455:partition_lba[15:8]<=sector_data;
                        456:partition_lba[23:16]<=sector_data;
                        457:partition_lba[31:24]<=sector_data;
                        510:boot_signature[7:0]<=sector_data;
                        511:boot_signature[15:8]<=sector_data;
                    endcase
                end
                if(metadata_fat) begin
                    if(write_pointer[8:2]==fat_offset[8:2]) case(write_pointer[1:0])
                        0:next_cluster[7:0]<=sector_data;
                        1:next_cluster[15:8]<=sector_data;
                        2:next_cluster[23:16]<=sector_data;
                        3:next_cluster[31:24]<={4'd0,sector_data[3:0]};
                    endcase
                end
                if(metadata_dir && !directory_end) begin
                    if(write_pointer[4:0]<8) begin
                        entry_name<={entry_name[55:0],upper_data};
                        if(write_pointer[4:0]==7) begin entry_role_q<=role_for_name({entry_name[55:0],upper_data});entry_thumbnail_q<=thumbnail_for_name({entry_name[55:0],upper_data});end
                    end
                    case(write_pointer[4:0])
                        0:begin entry_first<=sector_data;entry_basic_valid<=0;if(sector_data==0) directory_end<=1;end
                        8:ext0<=sector_data;
                        9:ext1<=sector_data;
                        10:ext2<=sector_data;
                        11:entry_attr<=sector_data;
                        12:entry_basic_valid<=(entry_first!=8'he5 && entry_attr!=8'h0f && (entry_attr&8'h18)==0);
                        20:entry_cluster[23:16]<=sector_data;
                        21:entry_cluster[31:24]<=sector_data;
                        26:entry_cluster[7:0]<=sector_data;
                        27:entry_cluster[15:8]<=sector_data;
                        28:begin entry_size[7:0]<=sector_data;entry_cluster_q<=entry_cluster;end
                        29:entry_size[15:8]<=sector_data;
                        30:entry_size[23:16]<=sector_data;
                        31:begin entry_size[31:24]<=sector_data;entry_commit_pending<=1'b1;end
                    endcase
                end
            end
            if(entry_commit_pending) begin
                entry_commit_pending<=1'b0;
                if(file_count<MAX_FILES && entry_basic_valid && is_bmp &&
                    ((|entry_cluster_q[31:2]) || entry_cluster_q[1]) && entry_size_ge_54) begin
                    if(!ROLE_MODE) begin
                        clusters[file_count[4:0]]<=entry_cluster_q;sizes[file_count[4:0]]<=entry_size;
                        file_count<=file_count+1'b1;
                    end else if(entry_role_q<ROLE_COUNT) begin
                        if(role_present[entry_role_q]) duplicate_role<=1;
                        else begin
                            clusters[entry_role_q]<=entry_cluster_q;sizes[entry_role_q]<=entry_size;
                            role_present[entry_role_q]<=1;file_count<=file_count+1'b1;
                        end
                    end
                end else if(ROLE_MODE==3 && entry_basic_valid && is_wav &&
                    ((|entry_cluster_q[31:2]) || entry_cluster_q[1]) && entry_size_ge_44 && entry_role_q<10) begin
                    if(audio_present[entry_role_q]) duplicate_audio<=1;
                    else begin
                        audio_clusters[entry_role_q]<=entry_cluster_q;audio_sizes[entry_role_q]<=entry_size;
                        audio_present[entry_role_q]<=1'b1;
                    end
                end else if(ROLE_MODE==3 && entry_basic_valid && is_bin &&
                    ((|entry_cluster_q[31:2]) || entry_cluster_q[1]) && entry_size_ge_16 &&
                    entry_role_q<10 && entry_role_q[0]) begin
                    subtitle_clusters[entry_role_q]<=entry_cluster_q;subtitle_sizes[entry_role_q]<=entry_size;
                    subtitle_present[entry_role_q]<=1'b1;
                end else if(ROLE_MODE==3 && entry_basic_valid && is_bin &&
                    ((|entry_cluster_q[31:2]) || entry_cluster_q[1]) && entry_size==4016 && entry_thumbnail_q<5) begin
                    if(thumbnail_present[entry_thumbnail_q]) duplicate_thumbnail<=1'b1;
                    else begin
                        thumbnail_clusters[entry_thumbnail_q]<=entry_cluster_q;thumbnail_sizes[entry_thumbnail_q]<=entry_size;
                        thumbnail_present[entry_thumbnail_q]<=1'b1;
                    end
                end
            end
            if(state==WAIT_SD) begin
                watchdog<=watchdog+1'b1;
                if(watchdog==100000000) begin state<=FAIL;error<=1;busy<=0;end
            end else watchdog<=0;
            case(state)
                BOOT: if(sd_ready) read_sector(0,PARSE0);
                READ: if(sd_ready && !sd_busy) begin
                    metadata_boot<=return_state==PARSE0 || return_state==BPB;
                    metadata_fat<=return_state==FAT_ROOT || return_state==FAT_FILE;
                    metadata_dir<=return_state==ENTRY;
                    sector_start<=1;write_pointer<=0;state<=WAIT_SD;
                end
                WAIT_SD: if(sector_done) begin state<=return_state==STREAM?STREAM_WAIT:return_state;pointer<=0;end
                PARSE0: if(boot_signature!=16'haa55) begin state<=FAIL;error<=2;end
                    else if(bytes_per_sector_512 && boot_spc!=0 && root_entries==0) begin partition<=0;state<=BPB;end
                    else if(partition_type==8'h0b || partition_type==8'h0c) begin
                        partition<=partition_lba;read_sector(partition_lba,BPB);
                    end else begin state<=FAIL;error<=2;end
                BPB: if(boot_signature!=16'haa55 || !bytes_per_sector_512 || root_entries!=0 || fat16_size!=0 ||
                    boot_fat_size==0 || boot_spc==0 || (boot_spc&(boot_spc-1'b1))!=0 ||
                    boot_spc>128 || boot_fats==0 || boot_fats>2 || reserved_sectors==0 || boot_root<2) begin
                        state<=FAIL;error<=3;
                    end else begin
                        spc<=boot_spc;fat_count<=boot_fats;sectors_per_fat<=boot_fat_size;
                        case(boot_spc)
                            1:spc_shift<=0;2:spc_shift<=1;4:spc_shift<=2;8:spc_shift<=3;
                            16:spc_shift<=4;32:spc_shift<=5;64:spc_shift<=6;128:spc_shift<=7;
                        endcase
                        fat_base<=partition+reserved_sectors;
                        root_cluster<=boot_root;pending_cluster<=boot_root;cluster_sector<=0;
                        chain_steps<=0;state<=INIT_DATA;
                    end
                INIT_DATA:begin
                    current_cluster<=pending_cluster;
                    data_base<=fat_base+(boot_fats==2?(boot_fat_size<<1):boot_fat_size);state<=ROOT;
                end
                ROOT:begin cluster_offset<=current_cluster-2;return_state<=ENTRY;state<=ADDR_SHIFT;end
                ADDR_SHIFT:begin cluster_offset<=cluster_offset<<spc_shift;state<=ADDR_BASE;end
                ADDR_BASE:begin sector_lba<=data_base+cluster_offset;state<=ADDR_SECTOR;end
                ADDR_SECTOR:begin sector_lba<=sector_lba+cluster_sector;state<=READ;end
                ENTRY: begin
                    if(duplicate_role || duplicate_audio || duplicate_thumbnail) begin mounted<=0;state<=FAIL;busy<=0;error<=7;end
                    else if(directory_end || file_count==MAX_FILES) begin
                        mounted<=ROLE_MODE?paired_roles:(file_count!=0);state<=READY;busy<=0;
                        if(ROLE_MODE && !paired_roles) begin error<=8;state<=FAIL;end
                        else if(file_count==0) error<=4;
                    end
                    else state<=ROOT_NEXT;
                end
                ROOT_NEXT: if(cluster_sector+1'b1<spc) begin cluster_sector<=cluster_sector+1'b1;state<=ROOT;end
                    else begin cluster_sector<=0;read_sector(fat_base+(current_cluster>>7),FAT_ROOT);end
                FAT_ROOT: if(next_cluster>=32'h0ffffff8) begin
                        mounted<=ROLE_MODE?paired_roles:(file_count!=0);state<=READY;busy<=0;
                        if(ROLE_MODE && !paired_roles) begin error<=8;state<=FAIL;end
                        else if(file_count==0) error<=4;
                    end
                    else if(next_cluster<2 || chain_steps==65535) begin state<=FAIL;error<=5;end
                    else begin pending_cluster<=next_cluster;state<=FAT_ROOT_COMMIT;end
                FAT_ROOT_COMMIT: begin
                    current_cluster<=pending_cluster;chain_steps<=chain_steps+1'b1;state<=ROOT;
                end
                READY: if((open_file || open_audio || open_subtitle || open_thumbnail) && mounted &&
                    ((open_thumbnail && thumbnail_index<5) || (!open_thumbnail && (!ROLE_MODE || file_index<ROLE_COUNT)))) begin
                    active_index<=open_thumbnail?{2'd0,thumbnail_index}:file_index;
                    active_audio<=open_audio;
                    active_subtitle<=open_subtitle;
                    active_thumbnail<=open_thumbnail;
                    if(open_file && ROLE_MODE && file_index<ROLE_COUNT) role_valid[file_index]<=0;
                    if(open_thumbnail) begin
                        current_cluster<=thumbnail_clusters[thumbnail_index];
                        file_left<=thumbnail_sizes[thumbnail_index];
                    end else if(open_subtitle) begin
                        current_cluster<=subtitle_clusters[file_index];
                        file_left<=subtitle_sizes[file_index];
                    end else if(open_audio) begin
                        current_cluster<=audio_clusters[file_index];
                        file_left<=audio_sizes[file_index];
                    end else begin
                        current_cluster<=open_cluster_mux;
                        file_left<=open_size_mux;
                    end
                    cluster_sector<=0;state<=OPEN_PREP;
                end
                OPEN_PREP:begin
                    chain_steps<=0;file_start<=1;busy<=1;state<=FILE_SECTOR;
                end
                FILE_SECTOR:begin cluster_offset<=current_cluster-2;return_state<=STREAM;state<=ADDR_SHIFT;end
                STREAM: if(byte_ready) begin
                    file_left<=file_left-1'b1;
                    if(file_left==1) begin file_done<=1;state<=READY;busy<=0;end
                    else if(pointer==511) begin pointer<=0;state<=FILE_NEXT;end
                    else begin pointer<=pointer+1'b1;state<=STREAM_WAIT;end
                end
                STREAM_WAIT: state<=STREAM;
                FILE_NEXT: if(cluster_sector+1'b1<spc) begin cluster_sector<=cluster_sector+1'b1;state<=FILE_SECTOR;end
                    else begin cluster_sector<=0;read_sector(fat_base+(current_cluster>>7),FAT_FILE);end
                FAT_FILE: if(next_cluster<2 || next_cluster>=32'h0ffffff8 || chain_steps==65535) begin state<=FAIL;error<=6;end
                    else begin pending_cluster<=next_cluster;state<=FAT_FILE_COMMIT;end
                FAT_FILE_COMMIT: begin
                    current_cluster<=pending_cluster;chain_steps<=chain_steps+1'b1;state<=FILE_SECTOR;
                end
                FAIL: busy<=0;
                default:state<=FAIL;
            endcase
            if(abort_file && busy && state>=FILE_SECTOR) begin state<=READY;busy<=0;file_done<=1;pointer<=0;cluster_sector<=0;end
        end
    end
endmodule
