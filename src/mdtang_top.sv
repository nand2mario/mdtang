// Mega Drive / Genesis core for Tang FPGA boards
// nand2mario, 10/2024
module mdtang_top (
    input clk50,                    // 50Mhz

`ifdef VERILATOR
	input clk_sys,
    input clk_z80,                  // 1/2 clk_sys

	input [11:0] joy_btns,          // snes layout: R L X A RT LT DN UP START SELECT Y B, active high
    input [11:0] joy2_btns,

    input [2:0] loading,            // 0: gba on, 1: loading rom, 2: loading cartram, 3: set up flash backup
    input [7:0] loader_do,
    input loader_do_valid,
`endif

    // MicroSD
    output sd_clk,
    inout  sd_cmd,                  // MOSI
    input  sd_dat0,                 // MISO
    output sd_dat1,
    output sd_dat2,
    output sd_dat3,

    // SPI flash
    output flash_spi_cs_n,          // chip select
    input flash_spi_miso,           // master in slave out
    output flash_spi_mosi,          // mster out slave in
    output flash_spi_clk,           // spi clock
    output flash_spi_wp_n,          // write protect
    output flash_spi_hold_n,        // hold operations

    // dualshock controller
    output ds_clk,
    input ds_miso,
    output ds_mosi,
    output ds_cs,
    output ds2_clk,
    input ds2_miso,
    output ds2_mosi,
    output ds2_cs,

    // SDRAM
    output O_sdram_clk,
    output O_sdram_cs_n,            // chip select
    output O_sdram_cas_n,           // columns address select
    output O_sdram_ras_n,           // row address select
    output O_sdram_wen_n,           // write enable
    inout [15:0] IO_sdram_dq,       // 16 bit bidirectional data bus
    output [12:0] O_sdram_addr,     // 13 bit multiplexed address bus
    output [1:0] O_sdram_dqm,       // 
    output [1:0] O_sdram_ba,        // 4 banks

    // UART
    input UART_RXD,
    output UART_TXD,    

    output reg [7:0] led,           // debug leds on pmod1
    input s0,
    input s1,

    // HDMI output
    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p    
);

// Clocking and global signals -----------------------------------------------------------
// 53.69Mhz master clock
`ifndef VERILATOR

wire clk_sys, clk27;
wire hclk, hclk5;   // 74.25Mhz hdmi 720p pixel clock
wire clk_z80;       // 26.85Mhz (1/2 clk_sys)

// use interal OSC
// OSC u_osc (.OSCOUT(clk_in) );
// defparam u_osc.FREQ_DIV = 4;//210/4=52.5MHz

// pll_27b pll27(.clkin(clk_in),.clkout0(clk27));
// pll_all pllall(.clkout0(clk_sys),.clkout1(O_sdram_clk),.clkout2(hclk), .clkout3(hclk5),.clkin(clk27));

// use external osc
pll pll(.clkin(clk50), .clkout0(clk_sys), .clkout1(O_sdram_clk), .clkout2(clk_z80));
pll_27 pll27(.clkin(clk50), .clkout0(clk27));
pll_74 pll74(.clkin(clk27), .clkout0(hclk), .clkout1(hclk5));

wire [2:0]  loading;
wire        loader_do_valid;
wire [7:0]  loader_do;
wire [11:0] joy_btns, joy2_btns;
wire [11:0] hid1, hid2;
`endif

localparam FREQ = 53_750_000;

// reset logic
reg        reset /* verilator public */ = 1;
reg [15:0]  reset_cnt = 65535;
always @(posedge clk_sys) begin
    if (reset_cnt != 0) reset_cnt <= reset_cnt - '1;
    // if (reset_cnt == 0 && s1 == 0)       // press s1 to start
    if (reset_cnt == 0)
        reset <= 0;
end


/* verilator public_on */
reg        md_on;
wire [1:0] resolution;          // {V30, H40}, V30: verticle 240 vs 224, H40: horizontal 320 vs 256
wire ce_pix, hblank, vblank, hsync;
wire       pause_core;
wire [3:0] red   /* xsynthesis syn_keep=1 */, 
           green /* xsynthesis syn_keep=1 */, 
           blue  /* xsynthesis syn_keep=1 */;
wire [15:0] audio_left, audio_right;
/* verilator public_off */

wire [24:1] mem_addr;
wire [15:0] mem_data, mem_wdata;
wire [1:0] mem_be;
wire mem_req, mem_ack, mem_we;

wire [11:0] joy1 = btn_snes2md(joy_btns | hid1);
wire [11:0] joy2 = btn_snes2md(joy2_btns | hid2);

// MegaDrive system -------------------------------------------------------------------
system megadrive (
    .MCLK(clk_sys), .CLK_Z80(clk_z80), .RESET_N(md_on),
    .LPF_MODE('1), .ENABLE_FM('1), .ENABLE_PSG('1), .DAC_LDATA(audio_left), .DAC_RDATA(audio_right),
    .LOADING(loading != 0), .PAL('0), .EXPORT('1), .FAST_FIFO('0), .SRAM_QUIRK('0), .SRAM00_QUIRK('0),
    .NORAM_QUIRK('0), .PIER_QUIRK('0), .SVP_QUIRK('0), .FMBUSY_QUIRK('0), .SCHAN_QUIRK('0), .TURBO('0), 
    .GG_RESET('0), .GG_EN('0), .GG_CODE('0), .GG_AVAILABLE(),
    .BRAM_A(), .BRAM_DI(), .BRAM_DO(), .BRAM_WE(), .BRAM_CHANGE(),
    .RED(red), .GREEN(green), .BLUE(blue), .VS(), .HS(hsync), .HBL(hblank), .VBL(vblank), .CE_PIX(ce_pix), 
    .BORDER('0), .CRAM_DOTS('0), .INTERLACE(), .FIELD(), .RESOLUTION(resolution),
    .J3BUT('0), .JOY_1(joy1), .JOY_2(joy2), .JOY_3(), .JOY_4(), .JOY_5(), .MULTITAP('0),
    .MOUSE('0), .MOUSE_OPT('0), .GUN_OPT('0), .GUN_TYPE('0), .GUN_SENSOR('0), .GUN_A('0),
    .GUN_B('0), .GUN_C('0), .GUN_START('0),
    .SERJOYSTICK_IN('0), .SERJOYSTICK_OUT(), .SER_OPT('0),
    .MEM_ADDR(mem_addr), .MEM_DATA(mem_data), .MEM_WDATA(mem_wdata), .MEM_WE(mem_we), .MEM_BE(mem_be),
    .MEM_REQ(mem_req), .MEM_ACK(mem_ack), .ROMSZ(loader_addr[21:1]),
    .EN_HIFI_PCM('0), .LADDER('0), .OBJ_LIMIT_HIGH('0), .TRANSP_DETECT(),
    .PAUSE_EN(pause_core), .BGA_EN('1), .BGB_EN('1), .SPR_EN('1), .DBG_M68K_A(), .DBG_VBUS_A()
);


reg [2:0] loading_r;
reg [21:0] loader_addr, loader_addr_next;       // 4MB byte address, rom size after load complete
reg loader_req;
wire sdram_busy;
always @(posedge clk_sys) begin
    if (loader_do_valid) begin
        loader_req <= ~loader_req;
        loader_addr <= loader_addr_next;
        loader_addr_next <= loader_addr_next + 1;
    end
    loading_r <= loading;
    if (loading  && !loading_r) begin           // start loading, turn megadrive off
        loader_addr_next <= 0;
        md_on <= 0;
    end else if (!loading && loading_r) begin   // loading finished, turn megadrive on
        loader_addr <= loader_addr_next;        // this is the proper ROMSZ
        md_on <= 1;
    end
end

`ifdef VERILATOR

sdram_sim u_sdram (
    .clk(clk_sys), .resetn(1'b1), .busy(sdram_busy),
    .addr0(mem_addr), .req0(mem_req), .ack0(mem_ack), .wr0(mem_we), .be0(mem_be),
	.din0(mem_wdata), .dout0(mem_data),
    .addr1(loader_addr[21:1]), .req1(loader_req), .ack1(), .wr1('1), .be1(loader_addr[0] ? 2'b01 : 2'b10),    // big-endian
	.din1({2{loader_do}}), .dout1(), 
    .addr2(), .req2(), .ack2(), .wr2(), .be2(),
	.din2('0), .dout2()
);

`else

// iosys RV memory interface
wire        rv_valid        /* xsynthesis syn_keep=1 */;
wire        rv_ready        /* xsynthesis syn_keep=1 */;
wire [22:0] rv_addr         /* xsynthesis syn_keep=1 */;
wire [31:0] rv_wdata        /* xsynthesis syn_keep=1 */;
wire [3:0]  rv_wstrb        /* xsynthesis syn_keep=1 */;
wire [31:0] rv_rdata        /* xsynthesis syn_keep=1 */;

// sdram-side interface
wire [22:1] rv_mem_addr     /* xsynthesis syn_keep=1 */;    // 8MB space for RV in bank 1
wire [15:0] rv_mem_din      /* xsynthesis syn_keep=1 */;
wire [1:0]  rv_mem_ds       /* xsynthesis syn_keep=1 */;
wire [15:0] rv_mem_dout     /* xsynthesis syn_keep=1 */;
wire        rv_mem_req      /* xsynthesis syn_keep=1 */;
wire        rv_mem_ack      /* xsynthesis syn_keep=1 */;
wire        rv_mem_we       /* xsynthesis syn_keep=1 */;

// SDRAM layout: total 32MB
// 0000000 - 07FFFFF: cartridge ROM (max Genesis game is 5MB, Super Street Fighter II: The New Challengers)
// 0800000 - 080FFFF: 68K RAM       (64KB)
// 0820000 - 083FFFF: SRAM          (128KB)
// 1000000 - 10FFFFF: Risc-V memory (1MB)
sdram #(.FREQ(FREQ)) u_sdram (
    .clk(clk_sys), .resetn(1'b1), .refresh_allowed(1'b1), .busy(sdram_busy),
    .addr0(mem_addr), .req0(mem_req), .ack0(mem_ack), .wr0(mem_we), .be0(mem_be),
	.din0(mem_wdata), .dout0(mem_data),

    .addr1(loader_addr[21:1]), .req1(loader_req), .ack1(), .wr1('1), .be1(loader_addr[0] ? 2'b01 : 2'b10),    // big-endian
	.din1({2{loader_do}}), .dout1(), 

    .addr2({2'b10, rv_mem_addr}), .req2(rv_mem_req), .ack2(rv_mem_ack), .wr2(rv_mem_we), .be2(rv_mem_ds),
	.din2(rv_mem_din), .dout2(rv_mem_dout),

    .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba),      
    .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nWE(O_sdram_wen_n),  .SDRAM_nRAS(O_sdram_ras_n), 
    .SDRAM_nCAS(O_sdram_cas_n), .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm)
);

// iosys for menu, rom loading and other functions -----------------------------------------
wire iosys_loaded;
wire overlay;
wire [7:0] overlay_x;
wire [7:0] overlay_y;
wire [14:0] overlay_color;

`ifdef MCU_BL616

iosys_bl616 #(.CORE_ID(4), .FREQ(FREQ), .COLOR_LOGO(15'b00000_00100_11111)) iosys (
    .clk(clk_sys), .hclk(hclk), .resetn(~reset),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),
    .joy1(joy_btns), .joy2(joy2_btns), .hid1(hid1), .hid2(hid2),
    .rom_loading(loading), .rom_do(loader_do), .rom_do_valid(loader_do_valid), 
    .uart_tx(UART_TXD), .uart_rx(UART_RXD)
);

`else

iosys_picorv32 #(.CORE_ID(4), .FREQ(FREQ), .COLOR_LOGO(15'b00000_00100_11111)) iosys (
    .clk(clk_sys), .hclk(hclk), .resetn(~reset),

    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),
    .joy1(joy_btns), .joy2(joy2_btns),

    .rom_loading(loading), .rom_do(loader_do), .rom_do_valid(loader_do_valid), 
    .ram_busy(sdram_busy),

    .rv_valid(rv_valid), .rv_ready(rv_ready), .rv_addr(rv_addr), .rv_wdata(rv_wdata), 
    .rv_wstrb(rv_wstrb), .rv_rdata(rv_rdata), 

    .flash_spi_cs_n(flash_spi_cs_n), .flash_spi_miso(flash_spi_miso),
    .flash_spi_mosi(flash_spi_mosi), .flash_spi_clk(flash_spi_clk),
    .flash_spi_wp_n(flash_spi_wp_n), .flash_spi_hold_n(flash_spi_hold_n),
    .flash_loaded(iosys_loaded),

    .uart_tx(UART_TXD), .uart_rx(UART_RXD),

    .sd_clk(sd_clk), .sd_cmd(sd_cmd), .sd_dat0(sd_dat0), .sd_dat1(sd_dat1),
    .sd_dat2(sd_dat2), .sd_dat3(sd_dat3)
);

rv_sdram_adapter rv_adapt (
    .clk(clk_sys), .resetn(~reset), 
    .rv_valid(rv_valid), .rv_addr(rv_addr), .rv_wdata(rv_wdata),
    .rv_wstrb(rv_wstrb), .rv_ready(rv_ready), .rv_rdata(rv_rdata),

    .mem_addr(rv_mem_addr), .mem_req(rv_mem_req), .mem_ds(rv_mem_ds),
    .mem_din(rv_mem_din), .mem_we(rv_mem_we), .mem_req_ack(rv_mem_ack),
    .mem_dout(rv_mem_dout)
);

`endif

// Gamepads ------------------------------------------------------------------------------
dualshock_controller #(.FREQ(FREQ)) ds (
    .clk(clk_sys), .I_RSTn(1'b1), 
    .O_psCLK(ds_clk), .O_psSEL(ds_cs), .O_psTXD(ds_mosi), .I_psRXD(ds_miso),
    .O_RXD_1(), .O_RXD_2(), .O_RXD_3(), .O_RXD_4(), .O_RXD_5(), .O_RXD_6(),
    .snes_btns(joy_btns)
);

dualshock_controller #(.FREQ(FREQ)) ds2 (
    .clk(clk_sys), .I_RSTn(1'b1), 
    .O_psCLK(ds2_clk), .O_psSEL(ds2_cs), .O_psTXD(ds2_mosi), .I_psRXD(ds2_miso),
    .O_RXD_1(), .O_RXD_2(), .O_RXD_3(), .O_RXD_4(), .O_RXD_5(), .O_RXD_6(),
    .snes_btns(joy2_btns)
);

// HDMI output ---------------------------------------------------------------------------
reg ce_pix_r, hblank_r;
reg [8:0] x;
reg [7:0] y;

// there are 15 dummy pixels after VBLANK before the first HBLANK
reg hsync_seen;
always @(posedge clk_sys) begin
    ce_pix_r <= ce_pix;

    // maintain y position
    if (vblank) begin
        y <= 0;
        hsync_seen <= 0;
    end
    if (hsync)
        hsync_seen <= 1;

    hblank_r <= hblank;
    if (hsync_seen) begin           // start frame after first hsync
        if (ce_pix & ~ce_pix_r & ~hblank & ~vblank)
            x <= x + 1;
        if (hblank) begin
            x <= 0;
            if (!hblank_r)
                y <= y + 1;
        end
    end
end

framebuffer #(
    .WIDTH(320), .HEIGHT(240), .COLOR_BITS(4)
) fb (
    .clk(clk_sys), .resetn(~reset), .clk_pixel(hclk), .clk_5x_pixel(hclk5),
    .ce_pix(ce_pix & hsync_seen), .r(red), .g(green), .b(blue), .x(x), .y(y), 
    .width(resolution[0] ? 320 : 256), .height(resolution[1] ? 240 : 224),      // resolution: 0: 256x224, 1: 320x224, 2: 256x240, 3: 320x240
    .audio_left(audio_left), .audio_right(audio_right),
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),
    .pause_core(pause_core),
    
    .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
    .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p)
);

assign led = ~{2'b0, vblank, md_on, loading != 0, overlay, iosys_loaded, ~reset};

`endif

// snes layout: R L X A RT LT DN UP START SELECT Y B, high active
// md layout:   Z,Y,X,Mode,Start,C,B,A,Up,Down,Left,Right
function [11:0] btn_snes2md([11:0] snes);
    reg [11:0] md;
    md[0] = snes[7];    // Right
    md[1] = snes[6];    // Left
    md[2] = snes[5];    // Down
    md[3] = snes[4];    // Left
    md[4] = snes[1];    // A
    md[5] = snes[0];    // B
    md[6] = snes[8];    // C
    md[7] = snes[3];    // Start
    md[8] = 0;          // Mode
    md[9] = 0;          // X
    md[10] = 0;         // Y
    md[11] = 0;         // Z
    return md;
endfunction

endmodule
