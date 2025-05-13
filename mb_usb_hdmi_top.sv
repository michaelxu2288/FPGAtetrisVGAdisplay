//-------------------------------------------------------------------------
//    mb_usb_hdmi_top.sv
//    Zuofu Cheng  -- UPDATED for multi-cell Tetris (May 2025)
//-------------------------------------------------------------------------
//


module mb_usb_hdmi_top(
    input  logic Clk,
    input  logic reset_rtl_0,

    // USB-SPI bridge
    input  logic [0:0] gpio_usb_int_tri_i,
    output logic       gpio_usb_rst_tri_o,
    input  logic       usb_spi_miso,
    output logic       usb_spi_mosi,
    output logic       usb_spi_sclk,
    output logic       usb_spi_ss,

    // UART passthrough
    input  logic uart_rtl_0_rxd,
    output logic uart_rtl_0_txd,

    // HDMI (TMDS)
    output logic hdmi_tmds_clk_n,
    output logic hdmi_tmds_clk_p,
    output logic [2:0] hdmi_tmds_data_n,
    output logic [2:0] hdmi_tmds_data_p,

    // 4-digit HEX displays (two banks)
    output logic [7:0] hex_segA,
    output logic [3:0] hex_gridA,
    output logic [7:0] hex_segB,
    output logic [3:0] hex_gridB
);

    logic clk_25MHz, clk_125MHz;
    logic locked;
    logic game_over;
    logic reset_ah;          // active-high reset for our modules
    assign reset_ah = reset_rtl_0;


    logic [31:0] keycode0_gpio, keycode1_gpio;

    logic [9:0] drawX, drawY;
    logic       hsync, vsync, vde;
    logic [3:0] red, green, blue;
    logic [15:0] tetris_score; 

    logic [3:0] board_cells [0:199];  
    logic [2:0] cur_shape;             
    logic [4:0] cur_row;            
    logic signed [5:0] cur_col; 
    logic [3:0] cur_clr;               

    hex_driver HexA (
        .clk   (Clk),
        .reset (reset_ah),
        .in    ({ tetris_score[15:12], tetris_score[11:8],
                  tetris_score[7:4],   tetris_score[3:0] }),
        .hex_seg (hex_segA),
        .hex_grid(hex_gridA)
    );

    hex_driver HexB ( .clk(Clk), .reset(reset_ah), .in('{ 4'h0, 4'h0, 4'h0, 4'h0 } ),
                  .hex_seg(hex_segB), .hex_grid(hex_gridB) );

    design_1 mb_block_i (
        .clk_100MHz        (Clk),
        .reset_rtl_0       (~reset_ah),          
        .gpio_usb_int_tri_i(gpio_usb_int_tri_i),
        .gpio_usb_rst_tri_o(gpio_usb_rst_tri_o),
        .gpio_usb_keycode_0_tri_o(keycode0_gpio),
        .gpio_usb_keycode_1_tri_o(keycode1_gpio),
        .usb_spi_miso      (usb_spi_miso),
        .usb_spi_mosi      (usb_spi_mosi),
        .usb_spi_sclk      (usb_spi_sclk),
        .usb_spi_ss        (usb_spi_ss),
        .uart_rtl_0_rxd    (uart_rtl_0_rxd),
        .uart_rtl_0_txd    (uart_rtl_0_txd)
    );

   
    clk_wiz_0 clk_wiz (
        .clk_in1 (Clk),
        .reset   (reset_ah),
        .clk_out1(clk_25MHz),
        .clk_out2(clk_125MHz),
        .locked  (locked)
    );

   
    vga_controller vga (
        .pixel_clk    (clk_25MHz),
        .reset        (reset_ah),
        .hs           (hsync),
        .vs           (vsync),
        .active_nblank(vde),
        .drawX        (drawX),
        .drawY        (drawY)
    );


    hdmi_tx_0 vga_to_hdmi (
        .pix_clk      (clk_25MHz),
        .pix_clkx5    (clk_125MHz),
        .pix_clk_locked(locked),
        .rst          (reset_ah),        
        .red          (red),
        .green        (green),
        .blue         (blue),
        .hsync        (hsync),
        .vsync        (vsync),
        .vde          (vde),
        .aux0_din     (4'b0),
        .aux1_din     (4'b0),
        .aux2_din     (4'b0),
        .ade          (1'b0),
        .TMDS_CLK_P   (hdmi_tmds_clk_p),
        .TMDS_CLK_N   (hdmi_tmds_clk_n),
        .TMDS_DATA_P  (hdmi_tmds_data_p),
        .TMDS_DATA_N  (hdmi_tmds_data_n)
    );
    
    logic [1:0] cur_orient;


    tetris_core game_core (
        .Reset     (reset_ah),
        .vsync     (vsync),                 // 60?Hz pulse
        .keycodes   (keycode0_gpio),    
        .board     (board_cells),
        .cur_shape (cur_shape),
        .cur_row   (cur_row),
        .cur_col   (cur_col),
        .cur_clr   (cur_clr),
        .cur_orient (cur_orient),
        .score (tetris_score),
        .game_over(game_over)
    );

    tetris_render renderer (
        .DrawX     (drawX),
        .DrawY     (drawY),
        .board     (board_cells),
        .cur_shape (cur_shape),
        .cur_row   (cur_row),
        .cur_col   (cur_col),
        .cur_clr   (cur_clr),
        .cur_orient (cur_orient),
        .Red       (red),
        .Green     (green),
        .Blue      (blue),
        .game_over(game_over)
        
    );

endmodule
