module demo_core
#(
    parameter int  DISPLAY_DIVIDER
)
(
    input  logic        clock,
    input  logic        reset,
    input  logic        clocks_clockIn50M,
    output logic        clocks_clockOutSystem,
    output logic        clocks_clockOutDisplay,
    output logic        clocks_clockOutSpi,
    output logic        clocks_locked,
    output logic [4:0]  video_data_r,
    output logic [4:0]  video_data_g,
    output logic [4:0]  video_data_b,
    output logic        video_dataEnable,
    output logic        video_vblank,
    output logic        video_hblank,
    output logic [15:0] audio_left,
    output logic [15:0] audio_right,
    input  logic [31:0] host_mem_address,
    input  logic        host_mem_enable,
    input  logic        host_mem_write,
    output logic [31:0] host_mem_dataRead,
    input  logic [31:0] host_mem_dataWrite,
    input  logic [3:0]  host_mem_writeStrobe,
    output logic        host_mem_done,
    input  logic        host_commandHost_request,
    output logic        host_commandHost_busy,
    output logic        host_commandHost_done,
    output logic        host_commandHost_error,
    output logic        host_commandCore_request,
    input  logic        host_commandCore_busy,
    input  logic        host_commandCore_done,
    input  logic        host_commandCore_error,
    input  logic        input_buttons_a,
    input  logic        input_buttons_b,
    input  logic        input_buttons_x,
    input  logic        input_buttons_y,
    input  logic        input_buttons_up,
    input  logic        input_buttons_down,
    input  logic        input_buttons_left,
    input  logic        input_buttons_right,
    input  logic        input_buttons_l,
    input  logic        input_buttons_r,
    input  logic        input_buttons_start,
    input  logic        input_buttons_select
);
    // =========================================================================
    // Clock generation
    // =========================================================================
    mmcm_clock_gen #(.CLK_DISPLAY_DIVIDE  (DISPLAY_DIVIDER))
    mmcm (
        .clk_in_50mhz (clocks_clockIn50M),
        .clk_sys      (clocks_clockOutSystem),
        .clk_display  (clocks_clockOutDisplay),
        .clk_spi      (clocks_clockOutSpi),
        .locked       (clocks_locked)
    );
    logic clk_10mhz;
    assign clk_10mhz = clocks_clockOutSystem;

    // =========================================================================
    // Host MCU communication
    // =========================================================================
    localparam ADDR_CONFIG_COLOR = 32'h00001000;
    localparam ADDR_REG0 = 32'hF0000000;
    localparam ADDR_REG1 = 32'hF0000004;
    localparam CMD_GET_STATUS     = 16'h0000;
    localparam CMD_CORE_RUN       = 16'h0100;
    localparam CMD_CORE_HALT      = 16'h0101;
    localparam CMD_SETUP_COMPLETE = 16'h0102;
    localparam CMD_NOTIFY_FOCUS   = 16'h0200;

    logic reg_core_setup = 1'b0;
    logic reg_core_reset = 1'b1;
    logic reg_core_focus = 1'b0;

    logic [31:0] reg_command_host_0, reg_command_host_1;
    logic mem_busy;

    typedef enum logic [2:0] {
        STATUS_UNKNOWN    = 3'd0,
        STATUS_INITIALIZE = 3'd1,
        STATUS_SETUP      = 3'd2,
        STATUS_CORE_HALT  = 3'd3,
        STATUS_CORE_RUN   = 3'd4
    } status_t;

    // Command Channel State
    typedef enum logic [1:0] {
        CMD_STATE_IDLE  = 2'b00,
        CMD_STATE_BUSY  = 2'b01,
        CMD_STATE_DONE  = 2'b10,
        CMD_STATE_ERROR = 2'b11
    } command_state_t;

    command_state_t command_host_state;

    assign host_mem_done = mem_busy;
    assign host_commandHost_busy = (command_host_state == CMD_STATE_BUSY);
    assign host_commandHost_done = (command_host_state == CMD_STATE_DONE);
    assign host_commandHost_error = (command_host_state == CMD_STATE_ERROR);
    assign host_commandCore_request = 1'b0;

    logic [15:0] cmd_opcode;
    assign cmd_opcode = reg_command_host_0[15:0];

    logic [23:0] reg_config_color;

    always_ff @(posedge clk_10mhz) begin
        if (reset) begin
            host_mem_dataRead  <= 32'h0;
            reg_command_host_0 <= 32'h0;
            reg_command_host_1 <= 32'h0;
            command_host_state <= CMD_STATE_IDLE;
            reg_core_setup     <= 1'b0;
            reg_core_reset     <= 1'b1;
            reg_core_focus     <= 1'b0;

            reg_config_color   <= 24'hFFFFFF;
        end else begin
            // Host memory interface
            if (host_mem_enable && !mem_busy) begin
                mem_busy      <= 1'b1;

                if (host_mem_write) begin
                    case (host_mem_address)
                        ADDR_REG0: reg_command_host_0 <= host_mem_dataWrite;
                        ADDR_REG1: reg_command_host_1 <= host_mem_dataWrite;
                        ADDR_CONFIG_COLOR: reg_config_color <= host_mem_dataWrite;
                        default: ;
                    endcase
                end else begin
                    case (host_mem_address)
                        ADDR_REG0: host_mem_dataRead <= reg_command_host_0;
                        ADDR_REG1: host_mem_dataRead <= reg_command_host_1;
                        default:   host_mem_dataRead <= 32'h0;
                    endcase
                end
            end else begin
                mem_busy      <= 1'b0;
            end

            // Host command channel
            if (host_commandHost_request) begin
                if (command_host_state == CMD_STATE_IDLE) begin
                    command_host_state <= CMD_STATE_DONE;
                    reg_command_host_0 <= 32'h0;

                    if (cmd_opcode == CMD_GET_STATUS) begin
                        reg_command_host_0 <= reg_core_setup
                            ? (reg_core_reset ? STATUS_CORE_HALT : STATUS_CORE_RUN)
                            : (STATUS_SETUP);
                    end else if (cmd_opcode == CMD_SETUP_COMPLETE) begin
                        reg_core_setup <= 1'b1;
                    end else if (cmd_opcode == CMD_CORE_RUN) begin
                        reg_core_reset <= 1'b0;
                    end else if (cmd_opcode == CMD_CORE_HALT) begin
                        reg_core_reset <= 1'b1;
                    end else if (cmd_opcode == CMD_NOTIFY_FOCUS) begin
                        reg_core_focus <= reg_command_host_1[0];
                    end else begin
                        // Unknown command opcode
                        command_host_state <= CMD_STATE_ERROR;
                    end
                end
            end else begin
                command_host_state <= CMD_STATE_IDLE;
            end
        end
    end

    // =========================================================================
    // Video: frame timing
    // =========================================================================
    // (10 MHz) / (320 * 521) = ~59.98 Hz
    localparam H_ACTIVE = 240, H_TOTAL = 320;
    localparam V_ACTIVE = 160, V_TOTAL = 521;

    logic [9:0] h_cnt = '0;
    logic [9:0] v_cnt = '0;
    logic frame_tick;

    always_ff @(posedge clk_10mhz) begin
        if (reset || reg_core_reset) begin
            h_cnt <= '0;
            v_cnt <= '0;
        end else begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= '0;
                if (v_cnt == V_TOTAL - 1)
                    v_cnt <= '0;
                else
                    v_cnt <= v_cnt + 1'b1;
            end else begin
                h_cnt <= h_cnt + 1'b1;
            end
        end
    end

    assign video_hblank = (h_cnt >= H_ACTIVE);
    assign video_vblank = (v_cnt >= V_ACTIVE);
    assign video_dataEnable = !video_hblank && !video_vblank;
    
    // Run logic once per frame.
    assign frame_tick = (h_cnt == H_ACTIVE) && (v_cnt == V_ACTIVE) && reg_core_focus;

    // =========================================================================
    // Game logic
    // =========================================================================
    localparam PADDLE_X     = 8;
    localparam PADDLE_W     = 4;
    localparam PADDLE_H     = 28;
    localparam BALL_SIZE    = 4;

    logic [8:0] paddle_y    = 66;
    logic [8:0] ball_x      = 120;
    logic [8:0] ball_y      = 80;
    logic       ball_dir_x  = 1'b1;
    logic       ball_dir_y  = 1'b1;

    logic sound_wall_trigger;
    logic sound_paddle_trigger;
    logic sound_lose_trigger;

    always_ff @(posedge clk_10mhz) begin
        if (reset) begin
            paddle_y     <= 66;
            ball_x       <= 120;
            ball_y       <= 80;
            ball_dir_x   <= 1'b1;
            ball_dir_y   <= 1'b1;
            sound_wall_trigger <= 1'b0;
            sound_paddle_trigger <= 1'b0;
            sound_lose_trigger <= 1'b0;
        end else begin
            sound_wall_trigger <= 1'b0;
            sound_paddle_trigger <= 1'b0;
            sound_lose_trigger <= 1'b0;
            
            if (frame_tick) begin
                // Move Paddle
                if (input_buttons_up && (paddle_y > 2))
                    paddle_y <= paddle_y - 2;
                else if (input_buttons_down && (paddle_y < V_ACTIVE - PADDLE_H - 2))
                    paddle_y <= paddle_y + 2;

                // Move Ball (Horizontal)
                if (ball_dir_x) begin
                    ball_x <= ball_x + 2;
                    if (ball_x >= H_ACTIVE - BALL_SIZE - 2) begin
                        ball_dir_x  <= 1'b0;
                        sound_wall_trigger <= 1'b1;
                    end
                end else begin
                    ball_x <= ball_x - 2;
                    // Paddle Collision Check
                    if ((ball_x <= PADDLE_X + PADDLE_W) && 
                        (ball_y + BALL_SIZE >= paddle_y) && 
                        (ball_y <= paddle_y + PADDLE_H)) begin
                        ball_dir_x  <= 1'b1;
                        sound_paddle_trigger <= 1'b1;
                    end else if (ball_x <= 2) begin
                        // Missed paddle
                        ball_x     <= 120;
                        ball_y     <= 80;
                        ball_dir_x <= 1'b1;
                        sound_lose_trigger <= 1'b1;
                    end
                end

                // Move Ball (Vertical)
                if (ball_dir_y) begin
                    ball_y <= ball_y + 2;
                    if (ball_y >= V_ACTIVE - BALL_SIZE - 2) begin
                        ball_dir_y  <= 1'b0;
                        sound_wall_trigger <= 1'b1;
                    end
                end else begin
                    ball_y <= ball_y - 2;
                    if (ball_y <= 2) begin
                        ball_dir_y  <= 1'b1;
                        sound_wall_trigger <= 1'b1;
                    end
                end
            end
        end
    end

    // =========================================================================
    // Video: pixel generation
    // =========================================================================
    logic is_paddle, is_ball, is_border;

    assign is_paddle = (h_cnt >= PADDLE_X) && (h_cnt < PADDLE_X + PADDLE_W) &&
                       (v_cnt >= paddle_y) && (v_cnt < paddle_y + PADDLE_H);

    assign is_ball   = (h_cnt >= ball_x) && (h_cnt < ball_x + BALL_SIZE) &&
                       (v_cnt >= ball_y) && (v_cnt < ball_y + BALL_SIZE);

    assign is_border = (v_cnt < 2) || (v_cnt >= V_ACTIVE - 2) || (h_cnt >= H_ACTIVE - 2);

    always_comb begin
        video_data_r = 5'd0;
        video_data_g = 5'd0;
        video_data_b = 5'd0;

        if (is_paddle) begin
            video_data_r = reg_config_color[23:19];
            video_data_g = reg_config_color[15:11];
            video_data_b = reg_config_color[7:3];
        end else if (is_ball) begin
            // White
            video_data_r = 5'h1F;
            video_data_g = 5'h1F;
            video_data_b = 5'h1F;
        end else if (is_border) begin
            // Green
            video_data_g = 5'h1F;
        end
    end

    // =========================================================================
    // Audio output
    // =========================================================================
    localparam CLOCKS_PER_SAMPLE = 208; // 10MHz / 208 = 48.077 kHz

    // Frequency counters (Sample Rate / (2 * MAX))
    localparam TONE_WALL   = 106; // ~226 Hz
    localparam TONE_PADDLE = 53;  // ~452 Hz
    localparam TONE_LOSE   = 133;  // ~180 Hz

    // Durations in sample ticks
    localparam DURATION_WALL    = 3072;  // 64 ms
    localparam DURATION_PADDLE  = 3072;  // 64 ms
    localparam DURATION_LOSE    = 12288; // 256 ms

    logic [7:0]  sample_counter = '0;
    logic        sample_tick;
    logic [15:0] sound_counter  = '0;
    logic [8:0]  tone_counter   = '0;
    logic [8:0]  tone_max       = '0;
    logic        square_wave    = 1'b0;

    // 48 kHz tick generator
    always_ff @(posedge clk_10mhz) begin
        if (reset || sample_counter == CLOCKS_PER_SAMPLE - 1) begin
            sample_counter <= '0;
            sample_tick    <= 1'b1;
        end else begin
            sample_counter <= sample_counter + 1'b1;
            sample_tick    <= 1'b0;
        end
    end

    // Tone generation
    always_ff @(posedge clk_10mhz) begin
        if (reset) begin
            sound_counter <= '0;
            tone_counter  <= '0;
            tone_max      <= '0;
            square_wave   <= 1'b0;
        end else begin
            // Trigger sounds
            if (sound_lose_trigger) begin
                sound_counter <= DURATION_LOSE;
                tone_max      <= TONE_LOSE;
            end else if (sound_paddle_trigger && sound_counter == 0) begin
                sound_counter <= DURATION_PADDLE;
                tone_max      <= TONE_PADDLE;
            end else if (sound_wall_trigger && sound_counter == 0) begin
                sound_counter <= DURATION_WALL;
                tone_max      <= TONE_WALL;
            end

            if (sample_tick) begin
                if (sound_counter > 0) begin
                    sound_counter <= sound_counter - 1'b1;

                    if (tone_counter == 0) begin
                        tone_counter <= tone_max;
                        square_wave  <= ~square_wave;
                    end else begin
                        tone_counter <= tone_counter - 1'b1;
                    end
                end else begin
                    square_wave  <= 1'b0;
                    tone_counter <= '0;
                end
            end
        end
    end

    // 16-bit signed output
    assign audio_left = square_wave ? 16'sh2000 : -16'sh2000;
    assign audio_right = audio_left;
endmodule
