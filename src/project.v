`default_nettype none

module tt_um_htfab_presenter (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

// Run VGA clock at half the project clock rate for faster QSPI access
reg vga_clk_gate;
always @(posedge clk) begin
    if (!rst_n) begin
        vga_clk_gate <= 1'b0;
    end else begin
        vga_clk_gate <= ~vga_clk_gate;
    end
end

// Generate VGA coordinates & sync signals
wire [9:0] hpos;
wire [9:0] vpos;
wire hsync;
wire vsync;
wire display_on;

hvsync_generator hvsync_inst (
    .clk,
    .clk_gate(vga_clk_gate),
    .rst_n,
    .hsync,
    .vsync,
    .display_on,
    .hpos,
    .vpos
);

// Debounce the rotary encoder / switch inputs
wire rot_A_raw = ui_in[0];
wire rot_B_raw = ui_in[1];
wire sw_C_raw = ui_in[2];
wire sw_D_raw = ui_in[3];
reg rot_A, rot_B, sw_C, sw_D;
reg [5:0] rot_A_debounce, rot_B_debounce,
          sw_C_debounce, sw_D_debounce;

always @(posedge clk) begin
    if (!rst_n) begin
        rot_A <= 0;
        rot_B <= 0;
        sw_C <= 0;
        sw_D <= 0;
        rot_A_debounce <= 0;
        rot_B_debounce <= 0;
        sw_C_debounce <= 0;
        sw_D_debounce <= 0;
    end else begin
        if (rot_A == rot_A_raw) begin
            rot_A_debounce <= 0;
        end else if (rot_A_debounce == 50) begin
            rot_A <= rot_A_raw;
            rot_A_debounce <= 0;
        end else begin
            rot_A_debounce <= rot_A_debounce + 1;
        end
        if (rot_B == rot_B_raw) begin
            rot_B_debounce <= 0;
        end else if (rot_B_debounce == 50) begin
            rot_B <= rot_B_raw;
            rot_B_debounce <= 0;
        end else begin
            rot_B_debounce <= rot_B_debounce + 1;
        end
        if (sw_C == sw_C_raw) begin
            sw_C_debounce <= 0;
        end else if (sw_C_debounce == 50) begin
            sw_C <= sw_C_raw;
            sw_C_debounce <= 0;
        end else begin
            sw_C_debounce <= sw_C_debounce + 1;
        end
        if (sw_D == sw_D_raw) begin
            sw_D_debounce <= 0;
        end else if (sw_D_debounce == 50) begin
            sw_D <= sw_D_raw;
            sw_D_debounce <= 0;
        end else begin
            sw_D_debounce <= sw_D_debounce + 1;
        end
    end
end

// Decode the rotary inputs into a two-way rolling counter,
// with switches as alternate inputs to increase / decrease the counter
reg [5:0] rot_counter;  // lowest bit is 0 in stable positions
reg [4:0] rot_max;      // max value for rot_counter, ignoring the lowest bit
reg rot_A_last;
reg rot_B_last;
reg sw_C_last;
reg sw_D_last;

always @(posedge clk) begin
    if (!rst_n) begin
        rot_counter <= 0;   // used for slide number
        rot_A_last <= 0;
        rot_B_last <= 0;
        sw_C_last <= 0;
        sw_D_last <= 0;
    end else begin
        if (rot_A == rot_A_last && rot_B != rot_B_last) begin
            if (rot_A != rot_B) begin
                // right turn
                if (rot_counter < {rot_max, 1'b0}) begin
                   rot_counter <= rot_counter + 1;
                end
            end else begin
                // left turn
                if (rot_counter > 0) begin
                    rot_counter <= rot_counter - 1;
                end
            end
        end else if (sw_C && !sw_C_last) begin
            // forward button / switch
            if (rot_max == 0) begin
                rot_counter <= 0;
            end else if (rot_counter > {rot_max, 1'b0} - 2) begin
                rot_counter <= {rot_max, 1'b0};
            end else begin
                rot_counter <= rot_counter + 2;
            end
        end else if (sw_D && !sw_D_last) begin
            // back button / switch
            if (rot_counter < 2) begin
                rot_counter <= 0;
            end else begin
                rot_counter <= rot_counter - 2;
            end
        end
        rot_A_last <= rot_A;
        rot_B_last <= rot_B;
        sw_C_last <= sw_C;
        sw_D_last <= sw_D;
    end
end

// Compensate for the QSPI read delay based on a fixed pattern
// at the beginning of each line read
reg [4:0] qspi_delay_correction;

// Send QSPI read command slightly before the end of the line
// so that the streaming data starts just as we begin the next line
wire [9:0] start_pos = 775 + {6'b0, qspi_delay_correction[4:1]};
wire start_read = (hpos == start_pos) && (vga_clk_gate == qspi_delay_correction[0]);

// Stop reading once we get out of the visible screen area
wire stop_read = (hpos == 639);

// Ignore lowest bit of rotary counter that's always 0 in stable positions
wire [4:0] slide_num = rot_counter[5:1];

// When we send the read command near the end of the line,
// we want to ask for the data in the next line
wire [9:0] next_vpos = (vpos == 524) ? 0 : (vpos + 1);

// Find memory address based on slide & line number
// (We waste some flash capacity here to keep things simple)
wire [23:0] qspi_addr = {slide_num, next_vpos[8:0], 10'b0};

// Use the QSPI state machine to send commands & read data
wire [3:0] qspi_data;
wire qspi_start_data;

qspi qspi_inst (
    .clk,
    .rst_n,
    .addr(qspi_addr),
    .start_read,
    .stop_read,
    .uio_in,
    .uio_out,
    .uio_oe,
    .data(qspi_data),
    .start_data(qspi_start_data)
);

// Detect the delay of the incoming QSPI data and perform two adjustments:
// - coarse: change the time we ask for the next line
// - fine: use a delay buffer we can tweak by +/- 1 clock tick

reg [2:0] delay_detection_state;
reg [1:0] qspi_delay_fine_tuning;

always @(posedge clk) begin
    if (!rst_n) begin
        qspi_delay_correction <= 0;
        qspi_delay_fine_tuning <= 0;
        delay_detection_state <= 0;
    end else if ((delay_detection_state > 0 || qspi_start_data) && hpos < 640) begin
        // we are in visible screen area but didn't yet figure out the right delay
        // => this line is already ruined, start from scratch and recalibrate
        qspi_delay_correction <= 0;
        qspi_delay_fine_tuning <= 0;
        delay_detection_state <= 0;
    end else if (qspi_start_data) begin
        // near end of line, we just switched the bidir pins to inputs
        qspi_delay_fine_tuning <= 0;
        delay_detection_state <= 1;
    end else begin
        // waiting for the "magic line header" preceding the raw pixel data
        case (delay_detection_state)
            0: ; // delay detection finished or inactive, do nothing
            1: if (qspi_data == 4'ha) delay_detection_state <= 2;
            2: if (qspi_data == 4'h5) delay_detection_state <= 3;
            3: if (qspi_data == 4'hc) delay_detection_state <= 4;
            4: if (qspi_data == 4'h3) delay_detection_state <= 5;
            5: begin
                // pattern just found => current qspi_data is first pixel of next line
                if (hpos == 799 && vga_clk_gate) begin
                    // we are 2 ticks late, this line is already ruined but we
                    // can fix the next one
                    qspi_delay_correction <= qspi_delay_correction - 2;
                    delay_detection_state <= 0;
                end else if (hpos == 799 && ~vga_clk_gate) begin
                    // we are 1 tick late, compensate for it in the delay buffer
                    qspi_delay_fine_tuning <= 0;    // too late to set for first pixel,
                                                    // that's why it's the default value
                    qspi_delay_correction <= qspi_delay_correction - 1;
                    delay_detection_state <= 0;
                end else if (hpos == 798 && vga_clk_gate) begin
                    // we are right on time, use middle "neutral" position for delay buffer
                    qspi_delay_fine_tuning <= 1;
                    delay_detection_state <= 0;
                end else if (hpos == 798 && ~vga_clk_gate) begin
                    // we are 1 tick early, compensate for it in the delay buffer
                    qspi_delay_fine_tuning <= 2;
                    qspi_delay_correction <= qspi_delay_correction + 1;
                    delay_detection_state <= 0;
                end else begin
                    // more than 1 tick early, this line is already ruined but
                    // stay in this state until the end of the line to find
                    // the right delay value by counting
                    qspi_delay_fine_tuning <= 2;
                    qspi_delay_correction <= qspi_delay_correction + 1;
                end
               end
            default: delay_detection_state <= 0;
        endcase
    end
end

// Delay buffer of 1/2/3 ticks based on qspi_delay_fine_tuning

reg [3:0] qspi_buf_1;
reg [3:0] qspi_buf_2;
reg [3:0] qspi_buf;

always @(posedge clk) begin
    if (!rst_n) begin
        qspi_buf_1 <= 0;
        qspi_buf_2 <= 0;
        qspi_buf <= 0;
    end else begin
        qspi_buf_1 <= qspi_data;
        qspi_buf_2 <= qspi_buf_1;
        case (qspi_delay_fine_tuning)
            0: qspi_buf <= qspi_data;
            1: qspi_buf <= qspi_buf_1;
            2: qspi_buf <= qspi_buf_2;
            default: qspi_buf <= qspi_data;
        endcase
    end
end

// Calculate screen colors based on data returned from the QSPI PMOD

// QSPI streaming data is at twice the rate of the VGA clock,
// so we combine two 4-bit frames (and drop 2 bits) to get the 6-bit color
reg [1:0] red;
reg [1:0] green;
reg [1:0] blue;

always @(posedge clk) begin
    if (!rst_n) begin
        red   <= 2'b00;
        green <= 2'b00;
        blue  <= 2'b00;
    end else if (qspi_buf[3]) begin
        red[1]   <= qspi_buf[0];
        green[1] <= qspi_buf[1];
        blue[1]  <= qspi_buf[2];
    end else begin
        red[0]   <= qspi_buf[0];
        green[0] <= qspi_buf[1];
        blue[0]  <= qspi_buf[2];
    end
end

// We need to keep the number of slides in the bitstream to prevent
// going past the last slide and displaying random data. To keep the
// code simple, it is recorded as the color of an off-screen pixel.

always @(posedge clk) begin
    if (!rst_n) begin
        rot_max <= 0;
    end else if (vga_clk_gate) begin
        if (hpos == 0 && vpos == 480) begin
            rot_max <= {green[0], red[0], blue[1], green[1], red[1]};
        end
    end
end

// Output pixel data for the TinyVGA PMOD
reg [1:0] R;
reg [1:0] G;
reg [1:0] B;
always @(posedge clk) begin
    if (!rst_n) begin
        R <= 2'b00;
        G <= 2'b00;
        B <= 2'b00;
    end else if (vga_clk_gate) begin
        if (!display_on) begin
            R <= 2'b00;
            G <= 2'b00;
            B <= 2'b00;
        end else begin
            R <= red;
            G <= green;
            B <= blue;
        end
    end
end

assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

// Suppress unused signals warning
wire _unused_ok = &{ena, ui_in[7:4], next_vpos[9], qspi_data[3]};

endmodule
