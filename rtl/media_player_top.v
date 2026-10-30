`timescale 1ns/1ps
module media_player_top #(parameter MEDIA_ROLE_MODE=3, parameter BMP_MIN_WIDTH=640)(input sys_clk,input [3:0] key_n,input [3:0] sw,
    output reg SD_nCS,output SD_DCLK,output SD_MOSI,input SD_MISO,
    output HDMI_CLK_P,output HDMI_D0_P,output HDMI_D1_P,output HDMI_D2_P,
    output [3:0] led);
    wire clk_mem,clk_pixel,clk_serial,clk_sdram,locked,rst_mem,rst_pixel;
    // All four keys are user controls; a power-on hold and PLL lock drive reset.
    reg [15:0] power_count=0;
    always @(posedge sys_clk) if(!(&power_count)) power_count<=power_count+1'b1;
    wire power_reset=!(&power_count);
    media_pll clocks(sys_clk,power_reset,clk_mem,clk_pixel,clk_serial,locked,clk_sdram);
    reset_sync mem_reset(clk_mem,power_reset || !locked,rst_mem);
    reset_sync pixel_reset(clk_pixel,power_reset || !locked,rst_pixel);
    wire sd_ready,sd_busy,sd_valid,sd_done,sd_cs_internal;
    wire [7:0] sd_data;wire [3:0] sd_error;
    wire sector_start;wire [31:0] sector_lba;
    wire [95:0] sd_diagnostic;
    reg [95:0] diag_meta,diag_pixel;
    always @(posedge clk_pixel) begin diag_meta<=sd_diagnostic;diag_pixel<=diag_meta;end
    sd_spi_reader sd(.clk(clk_mem),.rst(rst_mem),.read_start(sector_start),.read_lba(sector_lba),
        .ready(sd_ready),.busy(sd_busy),.data(sd_data),.data_valid(sd_valid),.done(sd_done),.error(sd_error),
        .sd_cs_n(sd_cs_internal),.sd_clk(SD_DCLK),.sd_mosi(SD_MOSI),.sd_miso(SD_MISO),.diagnostic(sd_diagnostic));
    // Isolate the board pin register from the SD state-machine decode.  The
    // SPI byte engine has divider latency, so this one mem_clk stage still
    // settles CS before the first SCK edge and after the final edge.
    always @(posedge clk_mem) begin
        if(rst_mem) SD_nCS<=1'b1;
        else SD_nCS<=sd_cs_internal;
    end
    wire mounted,fat_busy,file_start,file_done,byte_valid,byte_ready;
    wire [15:0] source_width,source_height;
    wire [9:0] role_present,role_valid,audio_present,subtitle_present;
    wire image_done;wire [3:0] bmp_error;
    wire [5:0] file_count;wire [7:0] byte_data;wire [3:0] fat_error;
    reg open_file,open_audio,open_subtitle,open_thumbnail,abort_file;reg [4:0] open_index;reg [2:0] thumbnail_open_index;reg [3:0] load_state;
    wire [4:0] thumbnail_present;
    wire [31:0] selected_size;
    fat32_bmp_reader #(.ROLE_MODE(MEDIA_ROLE_MODE)) files(.clk(clk_mem),.rst(rst_mem),.sd_ready(sd_ready),.sd_busy(sd_busy),.sd_error(sd_error),
        .sector_start(sector_start),.sector_lba(sector_lba),.sector_data(sd_data),.sector_valid(sd_valid),.sector_done(sd_done),
        .mounted(mounted),.file_count(file_count),.open_file(open_file),.file_index(open_index),.file_start(file_start),
        .byte_data(byte_data),.byte_valid(byte_valid),.byte_ready(byte_ready),.file_done(file_done),.busy(fat_busy),.error(fat_error),
        .validation_done(image_done),.validation_error(bmp_error),.validation_width(source_width),.validation_height(source_height),
        .role_present(role_present),.role_valid(role_valid),.selected_width(),.selected_height(),
        .open_audio(open_audio),.open_subtitle(open_subtitle),.open_thumbnail(open_thumbnail),.thumbnail_index(thumbnail_open_index),.abort_file(abort_file),
        .audio_present(audio_present),.subtitle_present(subtitle_present),.thumbnail_present(thumbnail_present),.selected_size(selected_size));
    wire [23:0] bmp_pixel;wire [18:0] bmp_address;
    wire bmp_valid,bmp_ready;
    wire bmp_byte_ready,wav_byte_ready,subtitle_byte_ready;
    localparam AUDIO_ENABLED=(MEDIA_ROLE_MODE==3);
    wire thumbnail_stream=load_state==9 || load_state==10;
    wire subtitle_stream=load_state==7 || load_state==8;
    wire audio_stream=AUDIO_ENABLED && (load_state==3 || load_state==4 || load_state==2 || load_state==6);
    wire thumbnail_byte_ready;
    assign byte_ready=thumbnail_stream?thumbnail_byte_ready:(subtitle_stream?subtitle_byte_ready:(audio_stream?wav_byte_ready:bmp_byte_ready));
    bmp24_decoder #(.MIN_WIDTH(BMP_MIN_WIDTH)) bitmap(clk_mem,rst_mem,file_start && !audio_stream && !subtitle_stream,byte_data,byte_valid && !audio_stream && !subtitle_stream,bmp_byte_ready,file_done && !audio_stream && !subtitle_stream,
        bmp_valid,bmp_ready,bmp_pixel,bmp_address,image_done,bmp_error,source_width,source_height);
    wire wav_sample_valid,wav_sample_ready,wav_format_ready,wav_data_started,wav_stream_done;
    wire signed [15:0] wav_sample; wire [3:0] wav_error; wire [31:0] wav_position;
    reg wav_start;
    wav_pcm_decoder wav_decoder(clk_mem,rst_mem,wav_start,byte_data,byte_valid && audio_stream,wav_byte_ready,file_done && audio_stream,
        wav_sample_valid,wav_sample_ready,wav_sample,wav_format_ready,wav_data_started,wav_stream_done,wav_error,wav_position);
    wire pcm_full,pcm_empty; wire [9:0] pcm_wr_level,pcm_rd_level; wire signed [15:0] pcm_rd_data;
    reg audio_fifo_reset_mem; reg audio_reset_toggle; reg [1:0] audio_reset_sync; reg audio_reset_last;
    reg audio_candidate_hold_mem;reg[1:0]audio_candidate_hold_sync;
    wire audio_fifo_reset_pixel=audio_reset_sync[1]!=audio_reset_last;
    assign wav_sample_ready=!pcm_full;
    wire pcm_read_enable;
    audio_pcm_fifo pcm_fifo(clk_mem,rst_mem || audio_fifo_reset_mem,wav_sample_valid,wav_sample,pcm_full,pcm_wr_level,
        clk_pixel,rst_pixel || audio_fifo_reset_pixel,pcm_read_enable,pcm_rd_data,pcm_empty,pcm_rd_level);
    wire mem_initialized,mem_ready,mem_done,mem_read_valid,mem_request,mem_write;
    wire [20:0] mem_address;wire [255:0] mem_data;wire [2:0] mem_beat;wire [31:0] mem_read_data;
    wire sdram_clk,sdram_ras_n,sdram_cas_n,sdram_we_n,sdram_cs_n,sdram_cke;
    wire [10:0] sdram_addr;wire [1:0] sdram_ba;wire [3:0] sdram_dm;wire [31:0] sdram_dq;
    sdram_burst memory(.clk(clk_mem),.rst(rst_mem),.initialized(mem_initialized),.request(mem_request),.write(mem_write),
        .address(mem_address),.write_data(mem_data),.ready(mem_ready),.done(mem_done),.read_valid(mem_read_valid),
        .read_beat(mem_beat),.read_data(mem_read_data),.sdram_clk(sdram_clk),.sdram_addr(sdram_addr),.sdram_ba(sdram_ba),
        .sdram_ras_n(sdram_ras_n),.sdram_cas_n(sdram_cas_n),.sdram_we_n(sdram_we_n),.sdram_cs_n(sdram_cs_n),
        .sdram_cke(sdram_cke),.sdram_dm(sdram_dm),.sdram_dq(sdram_dq),.clk_sdram(clk_sdram));
    EG_PHY_SDRAM_2M_32 ram(.clk(sdram_clk),.ras_n(sdram_ras_n),.cas_n(sdram_cas_n),.we_n(sdram_we_n),
        .addr(sdram_addr),.ba(sdram_ba),.dq(sdram_dq),.cs_n(sdram_cs_n),.cke(sdram_cke),
        .dm0(sdram_dm[0]),.dm1(sdram_dm[1]),.dm2(sdram_dm[2]),.dm3(sdram_dm[3]));
    wire [9:0] x,y;wire frame_tick=x==0 && y==480;
    wire scenario_request_toggle;wire [4:0] scenario_requested_index;
    wire request_toggle;wire [4:0] requested_index;wire request_queue_full;wire[3:0]request_queue_count;
    wire transition_active;
    wire signed [8:0] brightness;wire [8:0] contrast;wire[6:0] brightness_percent,contrast_percent;wire [2:0] scale;wire osd_enable,auto_mode;
    wire [3:0] key_press;wire [2:0] control_mode;wire long_reset;
    reg [1:0] busy_sync,mounted_sync;
    reg [5:0] count_pixel;
    reg [4:0] current_index;
    wire loader_busy;
    // State 6 is steady WAV playback, not a media load.  Keeping busy high in
    // this state pauses weather_scenario, so neither threshold switching nor
    // manual page keys can issue the next request.
    assign loader_busy=!mounted || !mem_initialized ||
        load_state==1 || load_state==2 || load_state==3 || load_state==4 || load_state==5 || load_state==7 || load_state==8;
    always @(posedge clk_pixel) begin
        if(rst_pixel) begin busy_sync<=3;mounted_sync<=0;count_pixel<=0;end
        else begin busy_sync<={busy_sync[0],loader_busy};mounted_sync<={mounted_sync[0],mounted};
            if(mounted_sync[1]) count_pixel<=file_count;
        end
    end
    wire [1:0] settings_target;wire settings_dec,settings_inc;
    keys_control controls(clk_pixel,rst_pixel,key_n,sw,frame_tick,settings_target,settings_dec,settings_inc,key_press,control_mode,long_reset,
        brightness,contrast,brightness_percent,contrast_percent,scale,osd_enable,auto_mode);
    wire menu_open,menu_choose,menu_back,menu_preview_pulse;wire[2:0] menu_selected;wire[4:0] menu_preview_index;reg menu_preview_toggle;
    reg menu_open_last_audio;
    wire menu_anim_active,menu_anim_dir;wire[4:0]menu_anim_frame;wire preview_ready;
    wire settings_open,settings_weather_request;wire ui_pause=settings_open||menu_open;
    wire[2:0] settings_selected;
    wire [7:0] rain_mm,temperature,snow_mm;wire [4:0] wind_level;
    wire [2:0] lightning_level,warning_level,breath_phase;wire alert_page,exercise_complete;
    wire[2:0] menu_thumb_slot;wire[12:0] menu_thumb_address;wire[7:0] menu_thumb_pixel;wire[4:0] thumbnail_loaded_mem;
    wire[4:0] thumbnail_pending=thumbnail_present & ~thumbnail_loaded_mem;
    wire[2:0] thumbnail_preload_index=thumbnail_pending[0]?0:thumbnail_pending[1]?1:thumbnail_pending[2]?2:thumbnail_pending[3]?3:4;
    weather_scenario scenario(clk_pixel,rst_pixel,frame_tick,busy_sync[1],ui_pause,control_mode,key_press,long_reset,
        auto_mode,current_index,count_pixel,menu_choose,menu_selected,scenario_request_toggle,scenario_requested_index,rain_mm,temperature,
        wind_level,lightning_level,snow_mm,warning_level,breath_phase,alert_page,exercise_complete);
    wire menu_audio_restart=menu_open_last_audio&&!menu_open;reg menu_audio_restart_toggle;
    media_request_queue requests(clk_pixel,rst_pixel,frame_tick,scenario_request_toggle,scenario_requested_index,
        !busy_sync[1],transition_active,request_toggle,requested_index,request_queue_full,request_queue_count);
    reg [1:0] front_bank,write_bank,completed_bank,front_meta,front_mem; reg front_valid;
    reg [1:0] preview_bank;reg preview_ready_toggle;reg [1:0] preview_request_sync;reg preview_request_last;reg preview_load;reg[4:0] preview_index_meta,preview_index_mem;
    reg[1:0]preview_bank_sync,preview_display_bank;reg preview_commit_pending;reg[1:0]preview_warmup;
    reg [3:0] cache_valid; reg [4:0] cache_tag[0:3];reg[4:0]compact_preview_loaded;reg compact_preload;
    reg [1:0] replacement_bank; reg cache_hit; reg [1:0] hit_bank;reg[4:0]requested_index_meta,requested_index_mem; integer ci;
    always @* begin
        cache_hit=0;hit_bank=0;replacement_bank=front_mem==2?0:front_mem+2'd1;
        for(ci=0;ci<3;ci=ci+1) begin
            if(!cache_valid[ci] && ci!=front_mem) replacement_bank=ci;
            if(cache_valid[ci] && cache_tag[ci]==requested_index_mem) begin cache_hit=1;hit_bank=ci;end
        end
    end
    reg completed_toggle,swap_ack;
    reg [4:0] completed_index;
    reg [1:0] completed_sync,request_sync,ack_sync;
    reg last_completed,last_request,last_ack;reg[1:0]audio_restart_sync;reg audio_restart_last,audio_restart_pending,audio_restart_only;reg[4:0]audio_restart_index_meta,audio_restart_index_mem;
    reg image_seen,file_seen;
    wire write_idle;
    always @(posedge clk_mem) begin
        open_file<=0;open_audio<=0;open_subtitle<=0;open_thumbnail<=0;abort_file<=0;wav_start<=0;audio_fifo_reset_mem<=0;
        if(rst_mem) begin
            request_sync<=0;requested_index_meta<=0;requested_index_mem<=0;preview_request_sync<=0;preview_request_last<=0;preview_index_meta<=0;preview_index_mem<=0;preview_load<=0;preview_bank<=0;preview_ready_toggle<=0;compact_preview_loaded<=0;compact_preload<=0;front_meta<=0;front_mem<=0;cache_valid<=0;completed_bank<=0;for(ci=0;ci<4;ci=ci+1) cache_tag[ci]<=0;ack_sync<=0;last_request<=0;last_ack<=0;audio_restart_sync<=0;audio_restart_last<=0;audio_restart_pending<=0;audio_restart_only<=0;audio_restart_index_meta<=0;audio_restart_index_mem<=0;
            load_state<=0;write_bank<=1;completed_toggle<=0;completed_index<=0;
            open_index<=0;image_seen<=0;file_seen<=0;
            open_audio<=0;open_subtitle<=0;open_thumbnail<=0;thumbnail_open_index<=0;abort_file<=0;wav_start<=0;audio_fifo_reset_mem<=0;audio_reset_toggle<=0;audio_candidate_hold_mem<=0;
        end else begin
            request_sync<={request_sync[0],request_toggle};requested_index_meta<=requested_index;requested_index_mem<=requested_index_meta;preview_request_sync<={preview_request_sync[0],menu_preview_toggle};preview_index_meta<=menu_preview_index;preview_index_mem<=preview_index_meta;front_meta<=front_bank;front_mem<=front_meta;ack_sync<={ack_sync[0],swap_ack};audio_restart_sync<={audio_restart_sync[0],menu_audio_restart_toggle};audio_restart_index_meta<=current_index;audio_restart_index_mem<=audio_restart_index_meta;
            // Latch menu-close audio restarts independently of the loader
            // state.  Thumbnail preload and image/subtitle transfers may keep
            // the loader away from state 6 for many milliseconds; comparing
            // the toggle only in state 6 could therefore strand the restart
            // forever.  A pending bit makes the event lossless.
            if(audio_restart_sync[1]!=audio_restart_last) begin
                audio_restart_last<=audio_restart_sync[1];
                audio_restart_pending<=1;
            end
            if(image_done) image_seen<=1;
            if(file_done) file_seen<=1;
            case(load_state)
                0: if(audio_restart_pending && mounted && mem_initialized && !fat_busy) begin
                    open_index<=audio_restart_index_mem;audio_restart_pending<=0;audio_restart_only<=1;load_state<=3;
                   end else if(preview_request_sync[1]!=preview_request_last && mounted && mem_initialized) begin
                    preview_request_last<=preview_request_sync[1];
                   end else if(mounted && thumbnail_pending!=0 && !fat_busy) begin thumbnail_open_index<=thumbnail_preload_index;load_state<=9;end
                   else if(mounted && mem_initialized && compact_preview_loaded!=5'b11111 && !fat_busy) begin
                    open_index<=!compact_preview_loaded[0]?0:!compact_preview_loaded[1]?2:!compact_preview_loaded[2]?4:!compact_preview_loaded[3]?6:8;
                    compact_preload<=1;write_bank<=replacement_bank;cache_valid[replacement_bank]<=0;image_seen<=0;file_seen<=0;load_state<=5;
                   end
                   else if(request_sync[1]!=last_request && mounted && mem_initialized) begin
                    last_request<=request_sync[1];open_index<=requested_index_mem;
                    if(fat_busy) abort_file<=1;
                    // Keep current programme audio running while the next
                    // picture and subtitle assets load.
                    if(cache_hit) begin
                        completed_bank<=hit_bank;completed_index<=requested_index_mem;
                        if(AUDIO_ENABLED && requested_index_mem[0]) load_state<=7;
                        else if(AUDIO_ENABLED) load_state<=3;
                        else begin completed_toggle<=~completed_toggle;load_state<=2;end
                    end else begin
                        write_bank<=replacement_bank;
                        cache_valid[replacement_bank]<=0;
                        image_seen<=0;file_seen<=0;load_state<=5;
                    end
                end
                5: if(!fat_busy) begin open_file<=1;load_state<=1;end
                1: if(file_seen && !fat_busy && write_idle && (image_seen || bmp_error!=0)) begin
                    if(image_seen && bmp_error==0 && fat_error==0 && sd_error==0) begin
                        cache_valid[write_bank]<=1;cache_tag[write_bank]<=open_index;completed_bank<=write_bank;
                        completed_index<=open_index;
                        if(compact_preload) begin compact_preview_loaded[open_index[3:1]]<=1;compact_preload<=0;load_state<=0;end
                        else if(preview_load) begin preview_bank<=write_bank;preview_ready_toggle<=~preview_ready_toggle;preview_load<=0;load_state<=0;end
                        else if(AUDIO_ENABLED && open_index[0]) load_state<=7;
                        else if(AUDIO_ENABLED) load_state<=3;
                        else begin completed_toggle<=~completed_toggle;load_state<=2;end
                    end else begin preview_load<=0;load_state<=0;end
                end else if(fat_error!=0 || sd_error!=0) load_state<=0;
                3: if(!fat_busy) begin audio_candidate_hold_mem<=1;audio_fifo_reset_mem<=1;audio_reset_toggle<=~audio_reset_toggle;open_audio<=1;wav_start<=1;file_seen<=0;load_state<=4;end
                4: begin
                    if(pcm_wr_level>=10'd256 && completed_sync[1]==last_completed) begin
                        if(audio_restart_only)begin audio_restart_only<=0;audio_candidate_hold_mem<=0;load_state<=6;end
                        else begin completed_toggle<=~completed_toggle;load_state<=2;end
                    end
                    // Reopen on FAT end-of-file, not decoder data-chunk end.
                    // Exported WAVs may contain trailing metadata after the
                    // PCM data chunk; wav_stream_done can therefore occur
                    // while FAT remains busy and must not be used as EOF.
                    else if(file_seen && !fat_busy) begin open_audio<=1;wav_start<=1;file_seen<=0;end
                    else if(wav_error!=0 || fat_error!=0 || sd_error!=0) begin
                        // Never leave the pixel-domain player permanently
                        // held after a failed/retried WAV transaction.
                        audio_candidate_hold_mem<=0;audio_restart_only<=0;load_state<=0;
                    end
                end
                2: begin
                    if(file_seen && !fat_busy) begin open_audio<=1;wav_start<=1;file_seen<=0;end
                    if(ack_sync[1]!=last_ack) begin last_ack<=ack_sync[1];audio_candidate_hold_mem<=0;load_state<=AUDIO_ENABLED?6:0;end
                end
                6: begin
                    if(audio_restart_pending)begin open_index<=audio_restart_index_mem;audio_restart_pending<=0;audio_restart_only<=1;load_state<=3;end
                    else if(request_sync[1]!=last_request || preview_request_sync[1]!=preview_request_last) load_state<=0;
                    else if(file_seen && !fat_busy) begin open_audio<=1;wav_start<=1;file_seen<=0;end
                end
                7: if(!fat_busy) begin open_subtitle<=1;file_seen<=0;load_state<=8;end
                8: begin
                    if(file_done && !fat_busy) load_state<=3;
                    else if(fat_error!=0 || sd_error!=0) load_state<=0;
                end
                9: if(!fat_busy) begin open_thumbnail<=1;load_state<=10;end
                10: begin
                    if(file_done && !fat_busy) load_state<=0;
                    else if(fat_error!=0 || sd_error!=0) load_state<=0;
                end
            endcase
        end
    end
    wire completed_event=completed_sync[1]!=last_completed;
    wire transition_commit;
    wire [8:0] transition_gain_level;
    // Five frames out plus five frames in is about 167 ms at 60 Hz.
    transition_fade #(.HALF_FRAMES(5)) transition_control(
        .clk(clk_pixel),.rst(rst_pixel),.frame_tick(frame_tick),.image_valid(front_valid),
        .change_event(completed_event),.commit_pulse(transition_commit),
        .active(transition_active),.gain(transition_gain_level));
    always @(posedge clk_pixel) begin
        if(rst_pixel) begin front_bank<=0;front_valid<=0;swap_ack<=0;completed_sync<=0;last_completed<=0;current_index<=0;audio_reset_sync<=0;audio_reset_last<=0;audio_candidate_hold_sync<=0;menu_preview_toggle<=0;menu_open_last_audio<=0;menu_audio_restart_toggle<=0;end
        else begin
            menu_open_last_audio<=menu_open;
            if(menu_audio_restart)menu_audio_restart_toggle<=~menu_audio_restart_toggle;
            if(menu_preview_pulse) menu_preview_toggle<=~menu_preview_toggle;
            completed_sync<={completed_sync[0],completed_toggle};
            audio_reset_sync<={audio_reset_sync[0],audio_reset_toggle};audio_candidate_hold_sync<={audio_candidate_hold_sync[0],audio_candidate_hold_mem};
            if(audio_fifo_reset_pixel) audio_reset_last<=audio_reset_sync[1];
            if(frame_tick && completed_event) last_completed<=completed_sync[1];
            if(transition_commit) begin
                front_bank<=completed_bank;front_valid<=1;current_index<=completed_index;
                swap_ack<=~swap_ack;
            end
        end
    end
    reg line_toggle,line_bank;reg[1:0]menu_background_bank;reg menu_open_last;
    reg [8:0] line_source_y,preview_line_source_y;reg line_dual_fetch;
    wire [9:0] next_y=y==524?10'd0:y+1'b1;
    wire [9:0] scale1_y_delta=next_y-10'd80;
    wire [8:0] mapped_y_normal=scale==0?((next_y>=120 && next_y<360)?((next_y-120)<<1):0):
        scale==1?((next_y>=80 && next_y<400)?(scale1_y_delta+(scale1_y_delta>>1)):0):
        scale==3?(9'd60+next_y-(next_y>>2)):
        scale==4?((next_y>>1)+9'd120):next_y;
    wire [8:0] mapped_y=mapped_y_normal;
    // The high-resolution menu preview displays a native 320x240 center crop.
    // Background and preview use independent
    // SDRAM reads, so normal background scaling remains untouched.
    wire [8:0] menu_preview_source_y=next_y-10'd104;
    wire [9:0] scale1_x_delta=x-10'd107;
    wire [9:0] source_x_normal=scale==0?((x>=160 && x<480)?((x-160)<<1):0):
        scale==1?((x>=107 && x<533)?(scale1_x_delta+(scale1_x_delta>>1)):0):
        scale==3?(10'd80+x-(x>>2)):
        scale==4?((x>>1)+10'd160):x;
    wire [9:0] source_x=source_x_normal;
    wire visible=x<640 && y<480 && (scale>=2 ||
        (scale==0 && x>=160 && x<480 && y>=120 && y<360) ||
        (scale==1 && x>=107 && x<533 && y>=80 && y<400));
    reg visible_d;reg [9:0] x_d,y_d;
    wire [23:0] line_pixel,adjusted_pixel,transition_pixel,osd_rgb,weather_rgb,weather_fx_rgb,subtitle_rgb,spectrum_rgb,output_rgb;
    wire line_done_toggle,line_overrun;
    reg [1:0] done_sync;reg last_done;
    reg [1:0] valid_lines;
    reg requested_line_bank;
    reg underrun;
    always @(posedge clk_pixel) begin
        if(rst_pixel) begin
            line_toggle<=0;line_bank<=0;line_source_y<=0;preview_line_source_y<=0;line_dual_fetch<=0;x_d<=0;y_d<=0;visible_d<=0;
            done_sync<=0;last_done<=0;valid_lines<=0;requested_line_bank<=0;underrun<=0;menu_background_bank<=0;menu_open_last<=0;
        end else begin
            x_d<=x;y_d<=y;visible_d<=visible;
            menu_open_last<=menu_open;
            if(menu_open&&!menu_open_last)menu_background_bank<=front_bank;
            done_sync<={done_sync[0],line_done_toggle};
            if(done_sync[1]!=last_done) begin last_done<=done_sync[1];valid_lines[requested_line_bank]<=1;end
            if(x==0 && front_valid && (y<479 || y==524)) begin
                line_source_y<=mapped_y;preview_line_source_y<=menu_preview_source_y;
                // Never compete for SDRAM bandwidth while the carousel is
                // moving.  Only stable cached thumbnails are drawn then.
                line_dual_fetch<=menu_open&&preview_ready&&!menu_anim_active&&next_y>=104&&next_y<344;
                line_bank<=next_y[0];requested_line_bank<=next_y[0];
                line_toggle<=~line_toggle;valid_lines[next_y[0]]<=0;
            end
            if(x==0 && y<480 && front_valid && !valid_lines[y[0]]) underrun<=1;
        end
    end
    // D3: identical RGB bars through SDRAM and directly into HDMI.
    function [23:0] color_bar;
        input [9:0] px;
        begin
            if(px<80) color_bar=24'hff0000;
            else if(px<160) color_bar=24'h00ff00;
            else if(px<240) color_bar=24'h0000ff;
            else if(px<320) color_bar=24'hffff00;
            else if(px<400) color_bar=24'h00ffff;
            else if(px<480) color_bar=24'hff00ff;
            else if(px<560) color_bar=24'hffffff;
            else color_bar=24'h000000;
        end
    endfunction
    reg [9:0] diagnostic_write_x;reg[8:0]diagnostic_write_y;reg[16:0]preview_row_base;
    always @(posedge clk_mem) begin
        if(rst_mem || file_start) begin diagnostic_write_x<=0;diagnostic_write_y<=0;preview_row_base<=17'd76480;end
        else if(bmp_valid && bmp_ready) begin
            if(diagnostic_write_x==639)begin diagnostic_write_x<=0;if(diagnostic_write_y!=479)diagnostic_write_y<=diagnostic_write_y+1'b1;if(!diagnostic_write_y[0]&&diagnostic_write_y!=478)preview_row_base<=preview_row_base-17'd320;end
            else diagnostic_write_x<=diagnostic_write_x+1'b1;
        end
    end
    wire [23:0] diagnostic_write_pixel=
        bmp_pixel;
    wire [7:0] diagnostic_gray=x_d<256?x_d[7:0]:x_d<512?~x_d[7:0]:8'h80;
    wire [23:0] diagnostic_rgb=output_rgb;
    wire[23:0]menu_preview_pixel;
    framebuffer_engine framebuffer(.clk(clk_mem),.rst(rst_mem),.pixel_clk(clk_pixel),.write_bank(write_bank),
        .write_abort(bmp_error!=0 || fat_error!=0 || sd_error!=0),
        .preview_capture(!open_index[0]&&!compact_preview_loaded[open_index[3:1]]&&!diagnostic_write_x[0]&&!diagnostic_write_y[0]),.preview_slot(open_index[3:1]),.preview_address(preview_row_base+(diagnostic_write_x>>1)),
        .pixel_address(bmp_address),.pixel(diagnostic_write_pixel),.pixel_valid(bmp_valid),.pixel_ready(bmp_ready),.write_idle(write_idle),
        .line_toggle(line_toggle),.line_source_y(line_source_y),.line_bank(line_bank),.front_bank(menu_open?menu_background_bank:front_bank),
        .dual_fetch(line_dual_fetch),.second_source_y(preview_line_source_y),.second_front_bank(preview_display_bank),.compact_preview(menu_open),.compact_slot(menu_selected),
        .read_x(source_x),.second_read_x(x_d),.read_bank(y[0]),.line_pixel(line_pixel),.second_line_pixel(menu_preview_pixel),.line_done_toggle(line_done_toggle),.line_overrun(line_overrun),
        .mem_request(mem_request),.mem_write(mem_write),.mem_address(mem_address),.mem_data(mem_data),
        .mem_ready(mem_ready),.mem_done(mem_done),.mem_read_valid(mem_read_valid),.mem_read_beat(mem_beat),.mem_read_data(mem_read_data));
    image_effects effects(line_pixel,brightness,contrast,adjusted_pixel);
    reg [7:0] error_meta,error_pixel;
    wire [7:0] error_code=sd_error!=0?{4'd1,sd_error}:fat_error!=0?{4'd2,fat_error}:
        bmp_error!=0?{4'd3,bmp_error}:line_overrun?8'h41:underrun?8'h42:0;
    always @(posedge clk_pixel) begin error_meta<=error_code;error_pixel<=error_meta;end
    // Observe the black test bar at source coordinate (600,400).
    reg [31:0] diagnostic_mem;
    reg [31:0] diagnostic_mem_meta,diagnostic_mem_pixel;
    reg [23:0] diagnostic_raw,diagnostic_adjusted;
    always @(posedge clk_mem) begin
        if(rst_mem) diagnostic_mem<=0;
        else if(mem_read_valid && !mem_write && mem_address[18:0]==19'd256600 && mem_beat==0)
            diagnostic_mem<=mem_read_data;
    end
    always @(posedge clk_pixel) begin
        if(rst_pixel) begin
            diagnostic_mem_meta<=0;diagnostic_mem_pixel<=0;
            diagnostic_raw<=0;diagnostic_adjusted<=0;
        end else begin
            diagnostic_mem_meta<=diagnostic_mem;diagnostic_mem_pixel<=diagnostic_mem_meta;
            if(x_d==600 && y_d==400 && front_valid && valid_lines[y_d[0]]) begin
                diagnostic_raw<=line_pixel;diagnostic_adjusted<=adjusted_pixel;
            end
        end
    end
    wire [95:0] color_diagnostic={diagnostic_mem_pixel,diagnostic_raw,diagnostic_adjusted,16'h0000};
    // Exact identity settings need no multiplier or clamp.
    wire [23:0] display_pixel=(brightness==0 && contrast==128)?line_pixel:adjusted_pixel;
    transition_gain transition_pixels(display_pixel,transition_gain_level,transition_pixel);
    wire [23:0] background=(visible_d && front_valid && valid_lines[y_d[0]])?transition_pixel:24'h101820;
    // Draw all scene overlays in the same virtual 640x480 coordinate space
    // as the framebuffer.  This makes data, warnings, weather animation and
    // subtitles shrink/zoom together with the picture instead of remaining
    // fixed at the physical HDMI resolution.
    wire [9:0] ui_x0=(x_d>=160)?((x_d-160)<<1):10'd0;
    wire [9:0] ui_x1_delta=(x_d>=107)?(x_d-107):10'd0;
    wire [9:0] ui_x=scale==0?ui_x0:
        scale==1?(ui_x1_delta+(ui_x1_delta>>1)):
        scale==3?(10'd80+x_d-(x_d>>2)):
        scale==4?((x_d>>1)+10'd160):x_d;
    wire [9:0] ui_y0=(y_d>=120)?((y_d-120)<<1):10'd0;
    wire [9:0] ui_y1_delta=(y_d>=80)?(y_d-80):10'd0;
    wire [9:0] ui_y=scale==0?ui_y0:
        scale==1?(ui_y1_delta+(ui_y1_delta>>1)):
        scale==3?(10'd60+y_d-(y_d>>2)):
        scale==4?((y_d>>1)+10'd120):y_d;
    wire scene_overlay_enable=visible_d&&front_valid&&!settings_open&&!menu_open;
    // The legacy diagnostic OSD is permanently disabled in the product UI.
    // Bypass it completely so its unused character decode does not consume
    // placement resources or disturb the 100 MHz FAT/SDRAM timing paths.
    osd overlay(ui_x,ui_y,background,1'b0,brightness,contrast,scale,auto_mode,current_index,count_pixel,busy_sync[1],error_pixel,osd_rgb,color_diagnostic);
    weather_overlay weather_text(ui_x,ui_y,osd_rgb,scene_overlay_enable,current_index,rain_mm,temperature,wind_level,
        lightning_level,snow_mm,warning_level,breath_phase,exercise_complete,weather_rgb);
    wire lightning_fx_pulse;
    weather_effects_overlay weather_fx(clk_pixel,rst_pixel,frame_tick,ui_pause||transition_active,scene_overlay_enable&&current_index<10&&!current_index[0],
        ui_x,ui_y,current_index,warning_level,weather_rgb,weather_fx_rgb,lightning_fx_pulse);
    wire audio_clock;wire [15:0] audio_sample;
    reg [1:0] mute_sync;
    always @(posedge clk_pixel) if(rst_pixel) mute_sync<=0;else mute_sync<={mute_sync[0],sw[3]};
    reg[8:0]weather_audio_gain;reg[8:0]weather_audio_target;
    always @* begin
     if(current_index[0]||current_index>=10)weather_audio_target=9'd256;
     else case(warning_level)0:weather_audio_target=9'd102;1:weather_audio_target=9'd141;2:weather_audio_target=9'd179;3:weather_audio_target=9'd218;default:weather_audio_target=9'd256;endcase
    end
    always @(posedge clk_pixel)begin
     if(rst_pixel)weather_audio_gain<=9'd102;
     else if(frame_tick&&!ui_pause)begin
      if(weather_audio_gain+4<weather_audio_target)weather_audio_gain<=weather_audio_gain+4;
      else if(weather_audio_gain>weather_audio_target+4)weather_audio_gain<=weather_audio_gain-4;
      else weather_audio_gain<=weather_audio_target;
     end
    end
    wire [31:0] audio_played_samples;wire spectrum_audio_clock;wire signed[15:0]spectrum_audio_sample;
    // D44 hardware reference: pause programme audio only during the visible
    // page transition.  Holding it throughout subtitle/WAV loading can stop
    // HDMI audio packets for more than a second on automatic changes, making
    // the sink reacquire after the beginning of the new WAV has passed.
    wire media_start_hold=transition_active;
    audio_pcm_output pcm_output(clk_pixel,rst_pixel || audio_fifo_reset_pixel,ui_pause||transition_active,!front_valid || mute_sync[1],transition_gain_level,weather_audio_gain,lightning_fx_pulse,pcm_empty,pcm_rd_data,pcm_read_enable,audio_clock,audio_sample,audio_played_samples,spectrum_audio_clock,spectrum_audio_sample);
    wire subtitle_visible; wire [2:0] subtitle_sentence;
    wire [31:0] subtitle_sentence_samples,subtitle_sentence_duration;
    wire subtitle_loaded_mem; wire [11:0] subtitle_width_mem; wire [1:0] subtitle_pixel_code;
    wire [15:0] subtitle_pixel_address;
    subtitle_asset_ram subtitle_memory(clk_mem,rst_mem,file_start && subtitle_stream,byte_valid && subtitle_stream,byte_data,
        subtitle_byte_ready,subtitle_loaded_mem,subtitle_width_mem,clk_pixel,subtitle_pixel_address,subtitle_pixel_code);
    subtitle_timeline subtitle_time(clk_pixel,rst_pixel,audio_played_samples,current_index,subtitle_visible,subtitle_sentence,
        subtitle_sentence_samples,subtitle_sentence_duration);
    subtitle_overlay subtitles(clk_pixel,ui_x,ui_y,weather_fx_rgb,subtitle_visible && scene_overlay_enable && !ui_pause && !transition_active,current_index,
        subtitle_sentence,subtitle_sentence_samples,subtitle_sentence_duration,subtitle_width_mem,subtitle_pixel_address,subtitle_pixel_code,subtitle_rgb);
    // The spectrum is a fixed HUD in the physical 640x480 bottom strip.
    // Do not feed the image-scaled ui_x/ui_y coordinates here: at 50/75/100%
    // scale they remap screen y=400..479 outside the overlay's 400..479 test,
    // leaving only the artwork's reserved blank strip visible.
    // The spectrum belongs only to the first/risk page of each weather pair.
    // Do not include visible_d in the state-update enable.  frame_tick occurs
    // at y=480 in vertical blanking, where visible_d is necessarily zero;
    // using scene_overlay_enable here cleared every accumulated bar exactly
    // when heights were committed.  Pixel drawing is already bounded to the
    // physical 400..479 visible strip inside the overlay.
    // Audio loading remains active while a WAV is streamed, therefore it must
    // not gate the analyser.  Analyse the exact final PCM sent to HDMI so mute,
    // weather gain and the transition envelope are all represented.
    wire spectrum_enable=front_valid&&!transition_active&&!settings_open&&!menu_open&&current_index<10&&!current_index[0];
    audio_spectrum_overlay spectrum(clk_pixel,rst_pixel,frame_tick,audio_clock,$signed(audio_sample),
        spectrum_enable,current_index,x_d,y_d,subtitle_rgb,spectrum_rgb);
    // Break the long scene-overlay-to-menu combinational chain.  Coordinates
    // advance through the same stage so menu edges and text remain aligned.
    reg[23:0] menu_background_pipe;reg[9:0] menu_x_pipe,menu_y_pipe;
    always @(posedge clk_pixel)begin
     if(rst_pixel)begin menu_background_pipe<=0;menu_x_pipe<=0;menu_y_pipe<=0;end
     else begin menu_background_pipe<=spectrum_rgb;menu_x_pipe<=x_d;menu_y_pipe<=y_d;end
    end
    thumbnail_cache thumbnail_memory(clk_mem,rst_mem,file_start && thumbnail_stream,thumbnail_open_index,byte_valid && thumbnail_stream,byte_data,
        thumbnail_byte_ready,thumbnail_loaded_mem,clk_pixel,menu_thumb_slot,menu_thumb_address,menu_thumb_pixel);
    reg[1:0] preview_ready_sync;reg preview_ready_last,preview_valid;reg[4:0]compact_loaded_meta,compact_loaded_pixel;
    always @(posedge clk_pixel) begin
        preview_ready_sync<={preview_ready_sync[0],preview_ready_toggle};compact_loaded_meta<=compact_preview_loaded;compact_loaded_pixel<=compact_loaded_meta;
        preview_bank_sync<=preview_bank;
        if(rst_pixel)begin preview_ready_last<=0;preview_valid<=0;preview_bank_sync<=0;preview_display_bank<=0;preview_commit_pending<=0;preview_warmup<=0;end
        else begin
            if(menu_open&&!menu_open_last)begin preview_display_bank<=front_bank;preview_valid<=front_valid&&!current_index[0];preview_commit_pending<=0;preview_warmup<=0;end
            if(menu_preview_pulse)begin preview_valid<=0;preview_commit_pending<=0;preview_warmup<=0;end
            // Preserve the previous complete preview while the next candidate
            // loads in a different SDRAM bank.  The ready toggle replaces it
            // atomically, so an incomplete frame is never exposed.
            // The first menu item is the current complete front frame.  Commit
            // it immediately when the menu opens; later selections still use
            // the normal atomic preview-ready toggle.
            if(menu_open&&!menu_open_last)begin
                if(!current_index[0])begin preview_display_bank<=front_bank;preview_valid<=1;end
                else preview_valid<=0;
                preview_commit_pending<=0;
            end
            if(preview_ready_sync[1]!=preview_ready_last)begin preview_ready_last<=preview_ready_sync[1];preview_commit_pending<=1;preview_warmup<=0;end
            if(frame_tick&&preview_commit_pending)begin preview_display_bank<=preview_bank_sync;preview_valid<=1;preview_commit_pending<=0;preview_warmup<=0;end
        end
    end
    // Hiding readiness during movement prevents stale/partially refreshed
    // preview scanlines from becoming visible as barcode-like stripes.
    assign preview_ready=menu_open && compact_loaded_pixel[menu_selected] && !menu_anim_active;
    wire[23:0] settings_rgb,menu_rgb;
    wire[23:0] dimmed_menu_background={1'b0,settings_rgb[23:17],1'b0,settings_rgb[15:9],1'b0,settings_rgb[7:1]};
    settings_menu settings(clk_pixel,rst_pixel,key_press,control_mode,menu_open,menu_back,menu_choose,settings_open,settings_weather_request,settings_target,settings_dec,settings_inc,settings_selected,menu_x_pipe,menu_y_pipe,menu_background_pipe,settings_rgb);
    weather_menu menu(clk_pixel,rst_pixel,key_press,control_mode,current_index,settings_weather_request,menu_open,menu_selected,menu_choose,menu_back,menu_preview_pulse,menu_preview_index,
        menu_x_pipe,menu_y_pipe,menu_open?dimmed_menu_background:settings_rgb,preview_ready,menu_preview_pixel,thumbnail_loaded_mem,menu_thumb_slot,menu_thumb_address,menu_thumb_pixel,menu_rgb,menu_anim_active,menu_anim_dir,menu_anim_frame);
    reg[23:0] menu_rgb_pipe;reg[9:0] menu2_x_pipe,menu2_y_pipe;
    always @(posedge clk_pixel)begin
     if(rst_pixel)begin menu_rgb_pipe<=0;menu2_x_pipe<=0;menu2_y_pipe<=0;end
     else begin menu_rgb_pipe<=menu_rgb;menu2_x_pipe<=menu_x_pipe;menu2_y_pipe<=menu_y_pipe;end
    end
    menu_text_overlay menu_text(clk_pixel,menu2_x_pipe,menu2_y_pipe,menu_rgb_pipe,settings_open&&!menu_open,menu_open,1'b1,settings_selected,menu_selected,brightness_percent,contrast_percent,scale,menu_anim_active,menu_anim_dir,menu_anim_frame,output_rgb);
    wire [2:0] tmds;wire tmds_clock;
    media_hdmi hdmi_out(clk_pixel,clk_serial,rst_pixel,diagnostic_rgb,audio_clock,audio_sample,x,y,tmds,tmds_clock);
    assign HDMI_D0_P=tmds[0];assign HDMI_D1_P=tmds[1];assign HDMI_D2_P=tmds[2];assign HDMI_CLK_P=tmds_clock;
    assign led={error_code!=0 || wav_error!=0,load_state!=0,mounted,locked};
endmodule








