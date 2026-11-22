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

// Debounce the rotary encoder inputs
wire rot_A_raw = ui_in[0];
wire rot_B_raw = ui_in[1];
reg rot_A;
reg rot_B;
reg [3:0] debounce_counter;

always @(posedge clk) begin
    if (!rst_n) begin
        rot_A <= 0;
        rot_B <= 0;
        debounce_counter <= 0;
    end else if (rot_A == rot_A_raw && rot_B == rot_B_raw) begin
        debounce_counter <= 0;
    end else if (debounce_counter == 15) begin
        rot_A <= rot_A_raw;
        rot_B <= rot_B_raw;
        debounce_counter <= 0;
    end else begin
        debounce_counter <= debounce_counter + 1;
    end
end

// Decode the rotary inputs into a two-way rolling counter
reg [5:0] rot_counter;  // lowest bit is 0 in stable positions
reg [5:0] alt_counter;  // use an alternate counter if the encoder's button is pressed
reg rot_A_last;
reg rot_B_last;

always @(posedge clk) begin
    if (!rst_n) begin
        rot_counter <= 0;   // used for slide number
        alt_counter <= 42;  // used for QSPI to VGA delay finetuning
        rot_A_last <= 0;
        rot_B_last <= 0;
    end else begin
        if (rot_A == rot_A_last && rot_B != rot_B_last) begin
            if (ui_in[2]) begin
                // encoder's button is held down, use alternate counter
                if (rot_A != rot_B) begin
                    // right turn
                    if (alt_counter < 6'b111110) begin
                       alt_counter <= alt_counter + 1;
                    end
                end else begin
                    // left turn
                    if (alt_counter > 0) begin
                        alt_counter <= alt_counter - 1;
                    end
                end
            end else begin
                // encoder's button is released, use main counter
                if (rot_A != rot_B) begin
                    // right turn
                    if (rot_counter < 6'b111110) begin
                       rot_counter <= rot_counter + 1;
                    end
                end else begin
                    // left turn
                    if (rot_counter > 0) begin
                        rot_counter <= rot_counter - 1;
                    end
                end
            end
        end
        rot_A_last <= rot_A;
        rot_B_last <= rot_B;
    end
end

// Tweaking the QSPI delay for post-silicon debugging
wire [3:0] delay_pixels = alt_counter[5:2];
wire delay_half_pixel = alt_counter[1];

// Send QSPI read command slightly before the end of the line
// so that the streaming data starts just as we begin the next line
wire [9:0] start_pos = 777 + {6'b0, delay_pixels};
wire start_read = (hpos == start_pos) && (vga_clk_gate == delay_half_pixel);

// Stop reading once we get out of the visible screen area
wire stop_read = (hpos == 639);

// Ignore lowest bit of slide counter that's always 0 in stable positions
wire [4:0] slide_num = rot_counter[5:1];

// When we send the read command near the end of the line,
// we want to ask for the data in the next line
wire [9:0] next_vpos = (vpos == 524) ? 0 : (vpos + 1);

// Find memory address based on slide & line number
// (We waste some flash capacity here to keep things simple)
wire [23:0] qspi_addr = {slide_num, next_vpos[8:0], 10'b0};

// Use the QSPI state machine to send commands & read data
wire [3:0] qspi_data;

qspi qspi_inst (
    .clk,
    .rst_n,
    .addr(qspi_addr),
    .start_read,
    .stop_read,
    .uio_in,
    .uio_out,
    .uio_oe,
    .data(qspi_data)
);

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
    end else if (qspi_data[3]) begin
        red[1]   <= qspi_data[0];
        green[1] <= qspi_data[1];
        blue[1]  <= qspi_data[2];
    end else begin
        red[0]   <= qspi_data[0];
        green[0] <= qspi_data[1];
        blue[0]  <= qspi_data[2];
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
    end else if (!vga_clk_gate) begin
        // do nothing
    end else if (!display_on) begin
        R <= 2'b00;
        G <= 2'b00;
        B <= 2'b00;
    end else begin
        R <= red;
        G <= green;
        B <= blue;
    end
end

assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

// Suppress unused signals warning
wire _unused_ok = &{ena, ui_in[7:3], next_vpos[9], qspi_data[3]};

endmodule
