`default_nettype none

module mmcm_clock_gen #(
    parameter integer CLK_DISPLAY_DIVIDE
)(
    input  wire logic clk_in_50mhz,  // 50 MHz input clock

    output wire logic clk_sys,       // 800 MHz / 80 = 10 MHz
    output wire logic clk_display,   // 800 MHz / CLK_DISPLAY_DIVIDE
    output wire logic clk_spi,       // 800 MHz / 4  = 200 MHz
    output wire logic locked
);

    logic clk_fb;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKIN1_PERIOD      (20.000), // 50 MHz
        .CLKFBOUT_MULT_F    (16.000), // M = 16 (VCO = 50 * 16 = 800 MHz)
        .DIVCLK_DIVIDE      (1),      // D = 1

        .CLKOUT0_DIVIDE_F   (80.000),
        .CLKOUT1_DIVIDE     (CLK_DISPLAY_DIVIDE),
        .CLKOUT2_DIVIDE     (4),

        .CLKOUT0_PHASE      (0.0),
        .CLKOUT1_PHASE      (0.0),
        .CLKOUT2_PHASE      (0.0),
        .CLKFBOUT_PHASE     (0.0),

        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKOUT2_DUTY_CYCLE (0.5),

        .STARTUP_WAIT       ("FALSE")
    ) mmcm_inst (
        .CLKOUT0            (clk_sys),
        .CLKOUT0B           (),
        .CLKOUT1            (clk_display),
        .CLKOUT1B           (),
        .CLKOUT2            (clk_spi),
        .CLKOUT2B           (),
        .CLKOUT3            (),
        .CLKOUT3B           (),
        .CLKOUT4            (),
        .CLKOUT5            (),
        .CLKOUT6            (),

        .CLKFBOUT           (clk_fb),
        .CLKFBOUTB          (),
        .CLKFBIN            (clk_fb),

        .LOCKED             (locked),
        .CLKIN1             (clk_in_50mhz),
        .PWRDWN             (1'b0),
        .RST                (1'b0)
    );

endmodule
