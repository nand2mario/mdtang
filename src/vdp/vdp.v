// Copyright (c) 2010 Gregory Estrade (greg@torlus.com)
// Copyright (c) 2018 Till Harbaum
// Copyright (c) 2018-2019 Alexey Melnikov
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Please report bugs to the author, but before you do so, please
// make sure that this is not a derivative work and that
// you have the latest version of this file.

// TODOs/Known issues (according to http://md.squee.co/VDP)
// - window has priority over sprites?

module vdp(
   input            RST_N,
   input            CLK,
   input            CE,                // nand2mario: CE=0: VDP is paused and no pixels are output
   
   input            SEL,               // MMIO interface, C00000-C0001F
   input [4:0]      A,
   input            RNW,
   input [15:0]     DI,
   output [15:0]    DO,
   output           DTACK_N,
   
   output           vram_req,          // VRAM interface for CPU
   input            vram_ack,
   output           vram_we,
   output [15:1]    vram_a,
   output [15:0]    vram_d,
   input [15:0]     vram_q,
   output           vram_u_n,
   output           vram_l_n,
   
   output           vram32_req,        // VRAM interface for rendering
   input            vram32_ack,
   output [15:1]    vram32_a,
   input [31:0]     vram32_q,
   
   output           EXINT,             // Interrupts
   input            HL,                
   output           HINT,
   output           VINT_TG68,
   output           VINT_T80,
   input            INTACK,            
   output reg       BR_N,              // Bus request
   input            BG_N,              
   output           BGACK_N,
   
   output [23:1]    VBUS_ADDR,
   input [15:0]     VBUS_DATA,
   
   output           VBUS_SEL,
   input            VBUS_DTACK_N,
   
   input            PAL,
   
   output reg       CE_PIX,            // pixel valid
   output reg       FIELD_OUT,
   output           INTERLACE,
   output [1:0]     RESOLUTION,        // 00 - 256x224, 01 - 256x240, 10 - 320x224, 11 - 320x240
   output reg       HBL,               // HBLANK
   output reg       VBL,               // VBLANK
   
   output [3:0]     R,
   output [3:0]     G,
   output [3:0]     B,
   output reg       HS,                // HSYNC
   output reg       VS,                // VSYNC
   
   input            SVP_QUIRK,
   input            VRAM_SPEED,		   // 0 - full speed, 1 - FIFO throttle emulation
   input            VSCROLL_BUG,		   // 0 - use nicer effect, 1 - HW original
   input            BORDER_EN,		   // Enable border
   input            CRAM_DOTS,		   // Enable CRAM dots
   input            OBJ_LIMIT_HIGH_EN,	// Enable more sprites and pixels per line
   
   output reg       TRANSP_DETECT,
   
   //debug
   input            BGA_EN,
   input            BGB_EN,
   input            SPR_EN,
   input      [7:0] dbg_in,
   output reg [7:0] dbg_out
);

`include "vdp_common.v"  

   // debug
   wire [15:0] vram_a_full = {vram_a, 1'b0}; // for verilator
   wire [15:0] vram32_a_full = {vram32_a, 1'b0};
   assign dbg_out = REG[dbg_in[4:0]];

   wire [16:1]      vram_a_reg;
   reg [15:1]       vram32_a_reg;
   reg [15:1]       vram32_a_next;
   
   reg              vram32_req_reg;
   //--------------------------------------------------------------
   // ON-CHIP RAMS
   //--------------------------------------------------------------
   reg [5:0]        CRAM_ADDR_A;
   reg [5:0]        CRAM_ADDR_B;
   reg [8:0]        CRAM_D_A;
   reg              CRAM_WE_A;
   wire             CRAM_WE_B;
   wire [8:0]       CRAM_Q_A;
   wire [8:0]       CRAM_Q_B;
   wire [8:0]       CRAM_DATA;
   
   reg [4:0]        VSRAM0_ADDR_A;
   reg [4:0]        VSRAM0_ADDR_B;
   reg [10:0]       VSRAM0_D_A;
   reg              VSRAM0_WE_A;
   wire             VSRAM0_WE_B;
   wire [10:0]      VSRAM0_Q_A;
   wire [10:0]      VSRAM0_Q_B;
   
   reg [4:0]        VSRAM1_ADDR_A;
   reg [4:0]        VSRAM1_ADDR_B;
   reg [10:0]       VSRAM1_D_A;
   reg              VSRAM1_WE_A;
   wire             VSRAM1_WE_B;
   wire [10:0]      VSRAM1_Q_A;
   wire [10:0]      VSRAM1_Q_B;
   
   //--------------------------------------------------------------
   // CPU INTERFACE
   //--------------------------------------------------------------
   reg              FF_DTACK_N;
   reg [15:0]       FF_DO;
   
   reg [7:0]        REG[0:31];
   reg              PENDING /* xsynthesis syn_keep=1 */;
   reg [5:0]        CODE;
   
   reg [16:0]       FIFO_ADDR[0:3] /* synthesis syn_ramstyle="distributed_ram" */;
   reg [15:0]       FIFO_DATA[0:3] /* synthesis syn_ramstyle="distributed_ram" */;
   reg [3:0]        FIFO_CODE[0:3] /* synthesis syn_ramstyle="distributed_ram" */;
   reg [1:0]        FIFO_DELAY[0:3];
   reg [1:0]        FIFO_WR_POS;
   reg [1:0]        FIFO_RD_POS;
   reg [2:0]        FIFO_QUEUE;
   wire             FIFO_EMPTY;
   wire             FIFO_FULL;
   wire             REFRESH_SLOT;
   reg              REFRESH_FLAG;
   reg              REFRESH_EN;
   reg              FIFO_EN;
   reg              FIFO_PARTIAL;
   reg              SLOT_EN;
   
   wire             IN_DMA;
   reg              IN_HBL;
   reg              M_HBL;
   reg              IN_VBL;		// VBL flag to the CPU
   reg              VBL_AREA;		// outside of borders
   
   reg              SOVR;
   reg              SOVR_SET;
   reg              SOVR_CLR;
   
   reg              SCOL;
   reg              SCOL_SET;
   reg              SCOL_CLR;
   
   //--------------------------------------------------------------
   // INTERRUPTS
   //--------------------------------------------------------------
   reg              EXINT_PENDING;
   reg              EXINT_PENDING_SET;
   reg              EXINT_FF;
   
   reg [7:0]        HINT_COUNT;
   reg              HINT_EN;
   reg              HINT_PENDING;
   reg              HINT_PENDING_SET;
   reg              HINT_FF;
   
   reg              VINT_TG68_PENDING;
   reg              VINT_TG68_PENDING_SET;
   reg              VINT_TG68_FF;
   
   reg              VINT_T80_SET;
   reg              VINT_T80_CLR;
   reg              VINT_T80_FF;
   reg [11:0]       VINT_T80_WAIT;
   
   reg              INTACK_D;
   //--------------------------------------------------------------
   // REGISTERS
   //--------------------------------------------------------------
   wire             RS0;            // 1: 320 pixel wide, 0: 256 pixel wide
   wire             H40;            // 1: 320 pixel wide, 0: 256 pixel wide
   wire             V30;            // 1: 240 pixel height, 0: 224 pixel height
   wire             SHI;            // 1: enable shadow/highlight mode.
   
   wire [7:0]       ADDR_STEP;      // Value to be added to the VDP address register after each read/write to the data port
   
   wire [1:0]       HSCR;           // Horizontal scrolling mode: 00 = full screen; 01 = invalid; 10 = 8 pixel rows; 11 = single pixel rows.
   wire [1:0]       HSIZE;          // Background width, 00=256, 01=512, 11=1024, 10=invalid
   wire [1:0]       VSIZE;          // Background height
   wire             VSCR;           // Vertical scrolling mode: 1 = 16 pixel columns, 0 = full screen
   
   wire [4:0]       WVP;            // Vertical position on screen to start drawing the window plane (in units of 8 pixels).
   wire             WDOWN;          // 1 = draw window from VP to bottom edge of screen; 0 = draw window from VP to top edge of screen.
   wire [4:0]       WHP;            // Horizontal position on screen to start drawing the window plane (in units of 8 pixels).
   reg [4:0]        WHP_LATCH;      
   wire             WRIGT;          // 1 = draw window from HP to right edge of screen; 0 = draw window from HP to left edge of screen.
   reg              WRIGT_LATCH;
   
   wire [5:0]       BGCOL;          // Background color
   
   wire [7:0]       HIT;            // Horizontal Interrupt Counter
   wire             IE2;            // 1 = enable external interrupts,
   wire             IE1;            // 1 = enable horizontal interrupts.
   wire             IE0;            // 1 = enable vertical interrupts.
   
   reg              OLD_HL;         
   wire             M3;             // 1 = freeze H/V counter on level 2 interrupt; 0 = enable H/V counter.
   wire             DE /* xsynthesis syn_keep=1 */;             // 1 = disable display.
   wire             M5;             // 1 = normal operation; 0 = masks high bits of color entries (this bit controls Mode 4 in SMS mode).
   
   wire             M128;           // 128KB VRAM mode
   wire             DMA;            // DMA enable
   
   wire [1:0]       LSM;            // Interlace mode: 00 = no interlace
   wire             ODD;            // 1 = odd frame in interlaced mode
   
   reg [15:0]       HV;             
   wire [15:0]      STATUS;         // Status register
   reg [15:0]       DBG;
   
   // Base addresses
   wire [5:0]       HSCB;           // Bits 15-10 of horizontal scroll data address in VRAM.
   wire [2:0]       NTBB;           // Bits 15-13 of foreground (plane B) nametable address in VRAM.
   wire [4:0]       NTWB;           // Bits 15-11 of window nametable address in VRAM. 
   wire [2:0]       NTAB;           // Bits 15-13 of foreground (plane A) nametable address in VRAM.
   wire [7:0]       SATB;           // Bits 15-9 of sprite table address in VRAM.
   
   //--------------------------------------------------------------
   // DATA TRANSFER CONTROLLER
   //--------------------------------------------------------------
   localparam [3:0] DTC_IDLE = 0,
                    DTC_FIFO_RD = 1,
                    DTC_VRAM_WR1 = 2,
                    DTC_VRAM_WR2 = 3,
                    DTC_CRAM_WR = 4,
                    DTC_VSRAM_WR = 5,
                    DTC_WR_END = 6,
                    DTC_VRAM_RD1 = 7,
                    DTC_VRAM_RD2 = 8,
                    DTC_CRAM_RD = 9,
                    DTC_CRAM_RD1 = 10,
                    DTC_CRAM_RD2 = 11,
                    DTC_VSRAM_RD = 12,
                    DTC_VSRAM_RD2 = 13,
                    DTC_VSRAM_RD3 = 14;
   reg [3:0]        DTC;
   
   localparam [4:0] DMA_IDLE = 0,
                    DMA_FILL_INIT = 1,
                    DMA_FILL_START = 2,
                    DMA_FILL_CRAM = 3,
                    DMA_FILL_VSRAM = 4,
                    DMA_FILL_WR = 5,
                    DMA_FILL_WR2 = 6,
                    DMA_FILL_NEXT = 7,
                    DMA_FILL_LOOP = 8,
                    DMA_COPY_INIT = 9,
                    DMA_COPY_RD = 10,
                    DMA_COPY_RD2 = 11,
                    DMA_COPY_WR = 12,
                    DMA_COPY_WR2 = 13,
                    DMA_COPY_LOOP = 14,
                    DMA_VBUS_INIT = 15,
                    DMA_VBUS_WAIT = 16,
                    DMA_VBUS_RD = 17,
                    DMA_VBUS_LOOP = 18,
                    DMA_VBUS_END = 19;
   reg [4:0]        DMAC;
   
   reg              DT_VRAM_SEL;
   reg              DT_VRAM_SEL_D;
   reg [16:1]       DT_VRAM_ADDR;
   reg [15:0]       DT_VRAM_DI;
   wire [15:0]      DT_VRAM_DO;
   reg              DT_VRAM_RNW;
   reg              DT_VRAM_UDS_N;
   reg              DT_VRAM_LDS_N;
   
   reg [16:0]       DT_WR_ADDR;
   reg [15:0]       DT_WR_DATA;
   
   reg [15:0]       DT_RD_DATA;
   reg [3:0]        DT_RD_CODE;
   reg              DT_RD_SEL;
   reg              DT_RD_DTACK_N;
   
   reg [16:0]       ADDR;
   
   reg [15:0]       DT_DMAF_DATA;
   reg [15:0]       DT_DMAV_DATA;
   reg              DMAF_SET_REQ;
   
   reg [23:1]       FF_VBUS_ADDR;
   reg              FF_VBUS_SEL;
   
   reg              DMA_VBUS;
   reg              DMA_FILL;
   reg              DMA_COPY;
   
   reg [15:0]       DMA_LENGTH;
   reg [15:0]       DMA_SOURCE;
   
   reg [1:0]        DMA_VBUS_TIMER;
   reg              BGACK_N_REG;
   
   //--------------------------------------------------------------
   // VIDEO COUNTING
   //--------------------------------------------------------------
   reg              V_ACTIVE;		   // V_ACTIVE right after line change
   reg              V_ACTIVE_DISP;	// V_ACTIVE after HBLANK_START
   wire [7:0]       Y;
   wire [8:0]       BG_Y;
   
   reg              PRE_V_ACTIVE;
   wire [8:0]       PRE_Y;
   
   reg              FIELD;
   reg              FIELD_LATCH;
   
   // HV COUNTERS
   reg [3:0]        HV_PIXDIV;
   reg [8:0]        HV_HCNT;
   reg [8:0]        HV_VCNT;
   wire [8:0]       HV_VCNT_EXT;
   wire             HV8;
   
   // TIMING VALUES
   wire [8:0]       H_DISP_START;
   wire [8:0]       H_DISP_WIDTH;
   wire [8:0]       H_TOTAL_WIDTH;
   wire [8:0]       H_SPENGINE_ON;
   wire [8:0]       H_INT_POS;
   wire [8:0]       HSYNC_START;
   wire [8:0]       HSYNC_END;
   wire [8:0]       HBLANK_START;
   wire [8:0]       HBLANK_END;
   wire [8:0]       HSCROLL_READ;
   wire [8:0]       V_DISP_START;
   wire [8:0]       V_DISP_HEIGHT;
   wire [8:0]       VSYNC_HSTART;
   wire [8:0]       VSYNC_START;
   wire [8:0]       VBORDER_START;
   wire [8:0]       VBORDER_END;
   wire [8:0]       V_TOTAL_HEIGHT;
   wire [8:0]       V_INT_POS;
   
   wire [8:0]       V_DISP_HEIGHT_R;
   reg              V30_R;
   
   //--------------------------------------------------------------
   // VRAM CONTROLLER
   //--------------------------------------------------------------
   
   wire             early_ack_dt;
   
   localparam [2:0] VMC32_IDLE = 0,
                    VMC32_HSC = 1,
                    VMC32_BGB = 2,
                    VMC32_BGA = 3,
                    VMC32_SP2 = 4,
                    VMC32_SP3 = 5;
   reg [2:0]        VMC32;
   wire [2:0]       VMC32_NEXT;
   reg              RAM_REQ_PROGRESS;
   
   //--------------------------------------------------------------
   // HSCROLL READING
   //--------------------------------------------------------------
   
   reg [15:1]       HSC_VRAM_ADDR;
   wire [31:0]      HSC_VRAM32_DO;
   reg [31:0]       HSC_VRAM32_DO_REG;
   wire             HSC_VRAM32_ACK;
   reg              HSC_SEL;
   
   //--------------------------------------------------------------
   // BACKGROUND RENDERING
   //--------------------------------------------------------------
   
   wire             BGEN_ACTIVATE;
   
   // BACKGROUND B
   localparam [3:0] BGBC_INIT = 0,
                    BGBC_GET_VSCROLL = 1,
                    BGBC_GET_VSCROLL2 = 2,
                    BGBC_GET_VSCROLL3 = 3,
                    BGBC_CALC_Y = 4,
                    BGBC_CALC_BASE = 5,
                    BGBC_BASE_RD = 6,
                    BGBC_TILE_RD = 7,
                    BGBC_LOOP = 8,
                    BGBC_DONE = 9;
   reg [3:0]        BGBC;
   
   // signal BGB_COLINFO		: colinfo_t;
   reg [8:0]        BGB_COLINFO_ADDR_A;
   reg [8:0]        BGB_COLINFO_ADDR_B;
   reg [7:0]        BGB_COLINFO_D_A;
   reg              BGB_COLINFO_WE_A;
   wire             BGB_COLINFO_WE_B;
   wire [7:0]       BGB_COLINFO_Q_B;
   
   reg [9:0]        BGB_X;
   reg [9:0]        BGB_POS;
   reg [6:0]        BGB_COL;
   reg [10:0]       BGB_Y;
   reg              T_BGB_PRI;
   reg [1:0]        T_BGB_PAL;
   wire [3:0]       T_BGB_COLNO;
   wire [15:0]      BGB_BASE;
   reg              BGB_HF;
   wire             BGB_TRANSP0;
   wire             BGB_TRANSP1;
   wire             BGB_TRANSP2;
   wire             BGB_TRANSP3;
   
   reg [31:0]       BGB_NAMETABLE_ITEMS;
   reg [15:1]       BGB_VRAM_ADDR;
   wire [31:0]      BGB_VRAM32_DO;
   reg [31:0]       BGB_VRAM32_DO_REG;
   wire             BGB_VRAM32_ACK;
   reg              BGB_VRAM32_ACK_REG;
   reg              BGB_SEL;
   reg [10:0]       BGB_VSRAM1_LATCH;
   reg [10:0]       BGB_VSRAM1_LAST_READ;
   
   reg              BGB_MAPPING_EN;
   wire             BGB_PATTERN_EN;
   reg              BGB_ENABLE;
   
   // BACKGROUND A
   localparam [3:0] BGAC_INIT = 0,
                    BGAC_GET_VSCROLL = 1,
                    BGAC_GET_VSCROLL2 = 2,
                    BGAC_GET_VSCROLL3 = 3,
                    BGAC_CALC_Y = 4,
                    BGAC_CALC_BASE = 5,
                    BGAC_BASE_RD = 6,
                    BGAC_TILE_RD = 7,
                    BGAC_LOOP = 8,
                    BGAC_DONE = 9;
   reg [3:0]        BGAC;
   
   // signal BGA_COLINFO		: colinfo_t;
   reg [8:0]        BGA_COLINFO_ADDR_A;
   reg [8:0]        BGA_COLINFO_ADDR_B;
   reg [7:0]        BGA_COLINFO_D_A;
   reg              BGA_COLINFO_WE_A;
   wire             BGA_COLINFO_WE_B;
   wire [7:0]       BGA_COLINFO_Q_B;
   
   reg [9:0]        BGA_X;
   reg [9:0]        BGA_POS;
   reg [6:0]        BGA_COL;
   reg [10:0]       BGA_Y;
   reg              T_BGA_PRI;
   reg [1:0]        T_BGA_PAL;
   wire [3:0]       T_BGA_COLNO;
   wire [15:0]      BGA_BASE;
   wire [15:0]      BGA_TILEBASE;
   reg              BGA_HF;
   wire             BGA_TRANSP0;
   wire             BGA_TRANSP1;
   wire             BGA_TRANSP2;
   wire             BGA_TRANSP3;
   
   reg [31:0]       BGA_NAMETABLE_ITEMS;
   reg [15:1]       BGA_VRAM_ADDR;
   wire [31:0]      BGA_VRAM32_DO;
   reg [31:0]       BGA_VRAM32_DO_REG;
   wire             BGA_VRAM32_ACK;
   reg              BGA_VRAM32_ACK_REG;
   reg              BGA_SEL;
   reg [10:0]       BGA_VSRAM0_LATCH;
   reg [10:0]       BGA_VSRAM0_LAST_READ;
   
   reg              WIN_V;
   reg              WIN_H;
   
   reg              BGA_MAPPING_EN;
   wire             BGA_PATTERN_EN;
   reg              BGA_ENABLE;
   //--------------------------------------------------------------
   // SPRITE ENGINE
   //--------------------------------------------------------------
   wire [6:0]       OBJ_MAX_FRAME;
   wire [5:0]       OBJ_MAX_LINE;
   
   wire [6:0]       OBJ_CACHE_ADDR_RD;
   reg [6:0]        OBJ_CACHE_ADDR_WR;
   reg [31:0]       OBJ_CACHE_D;
   wire [31:0]      OBJ_CACHE_Q;
   reg [3:0]        OBJ_CACHE_BE;
   reg [1:0]        OBJ_CACHE_WE;
   
   reg [5:0]        OBJ_VISINFO_ADDR_RD;
   reg [5:0]        OBJ_VISINFO_ADDR_WR;
   reg [6:0]        OBJ_VISINFO_D;
   reg              OBJ_VISINFO_WE;
   wire [6:0]       OBJ_VISINFO_Q;
   
   reg [5:0]        OBJ_SPINFO_ADDR_RD;
   reg [5:0]        OBJ_SPINFO_ADDR_WR;
   reg [34:0]       OBJ_SPINFO_D;
   reg              OBJ_SPINFO_WE;
   wire [34:0]      OBJ_SPINFO_Q;
   
   wire             OBJ_COLINFO_CLK;
   wire [8:0]       OBJ_COLINFO_ADDR_A;
   wire [8:0]       OBJ_COLINFO_ADDR_B;
   wire [6:0]       OBJ_COLINFO_D_B;
   wire             OBJ_COLINFO_WE_A;
   wire             OBJ_COLINFO_WE_B;
   wire [6:0]       OBJ_COLINFO_Q_A;
   reg [8:0]        OBJ_COLINFO_ADDR_RD_SP3;
   reg [8:0]        OBJ_COLINFO_ADDR_RD_REND;
   reg [8:0]        OBJ_COLINFO_ADDR_WR_SP3;
   reg [8:0]        OBJ_COLINFO_ADDR_WR_REND;
   reg              OBJ_COLINFO_WE_SP3;
   reg              OBJ_COLINFO_WE_REND;
   reg [6:0]        OBJ_COLINFO_D_SP3;
   reg [6:0]        OBJ_COLINFO_D_REND;
   
   reg [8:0]        OBJ_COLINFO2_ADDR_RD;
   reg [8:0]        OBJ_COLINFO2_ADDR_WR;
   reg [6:0]        OBJ_COLINFO2_D;
   reg              OBJ_COLINFO2_WE;
   wire [6:0]       OBJ_COLINFO2_Q;
   
   // PART 1
   wire             SP1E_ACTIVATE;
   
   localparam [2:0] SP1C_INIT = 0,
                    SP1C_Y_RD = 1,
                    SP1C_Y_RD2 = 2,
                    SP1C_Y_RD3 = 3,
                    SP1C_Y_TST = 4,
                    SP1C_SHOW = 5,
                    SP1C_NEXT = 6,
                    SP1C_DONE = 7;
   reg [2:0]        SP1C;
   reg [8:0]        SP1_Y;
   reg              SP1_EN;
   reg [6:0]        SP1_STEPS;
   
   reg [6:0]        OBJ_TOT;
   reg [6:0]        OBJ_NEXT;
   reg [5:0]        OBJ_NB;
   reg [8:0]        OBJ_Y_OFS;
   
   reg [1:0]        OBJ_VS1;
   
   reg [6:0]        OBJ_CACHE_ADDR_RD_SP1;
   
   // PART 2
   wire             SP2E_ACTIVATE;
   
   localparam [2:0] SP2C_INIT = 0,
                    SP2C_Y_RD = 1,
                    SP2C_Y_RD2 = 2,
                    SP2C_Y_RD3 = 3,
                    SP2C_Y_RD4 = 4,
                    SP2C_RD = 5,
                    SP2C_NEXT = 6,
                    SP2C_DONE = 7;
   reg [2:0]        SP2C;
   reg [8:0]        SP2_Y;
   reg              SP2_EN;
   reg [15:1]       SP2_VRAM_ADDR;
   wire [31:0]      SP2_VRAM32_DO;
   reg [31:0]       SP2_VRAM32_DO_REG;
   wire             SP2_VRAM32_ACK;
   reg              SP2_SEL;
   
   reg [5:0]        OBJ_IDX;
   
   reg [6:0]        OBJ_CACHE_ADDR_RD_SP2;
   
   // PART 3
   wire             SP3E_ACTIVATE;
   
   localparam [2:0] SP3C_INIT = 0,
                    SP3C_NEXT = 1,
                    SP3C_TILE_RD = 2,
                    SP3C_LOOP = 3,
                    SP3C_PLOT = 4,
                    SP3C_DONE = 5;
   reg [2:0]        SP3C;
   
   reg [15:1]       SP3_VRAM_ADDR;
   wire [31:0]      SP3_VRAM32_DO;
   reg [31:0]       SP3_VRAM32_DO_REG;
   wire             SP3_VRAM32_ACK;
   reg              SP3_VRAM32_ACK_REG;
   reg              SP3_SEL;
   
   reg [8:0]        OBJ_PIX;
   reg [5:0]        OBJ_NO;
   
   reg [6:0]        OBJ_LINK;
   
   reg [1:0]        OBJ_HS;
   reg [1:0]        OBJ_VS;
   reg              OBJ_MASKED;
   reg              OBJ_VALID_X;
   reg              OBJ_DOT_OVERFLOW;
   reg [4:0]        OBJ_X_OFS;
   reg              OBJ_PRI;
   reg [1:0]        OBJ_PAL;
   reg              OBJ_HF;
   reg [8:0]        OBJ_POS;
   reg [14:0]       OBJ_TILEBASE;
   
   //--------------------------------------------------------------
   // VIDEO OUTPUT
   //--------------------------------------------------------------
   localparam [1:0] PIX_SHADOW = 0,
                    PIX_NORMAL = 1,
                    PIX_HIGHLIGHT = 2;
   reg [1:0]        PIX_MODE;
   wire [15:0]      T_COLOR;
   
   reg [3:0]        FF_R;
   reg [3:0]        FF_G;
   reg [3:0]        FF_B;
   reg              FF_VS;
   reg              FF_HS;
   
   
   dpram_block #(9, 8) bgb_ci(
      .addr_a(BGB_COLINFO_ADDR_A), .addr_b(BGB_COLINFO_ADDR_B), 
      .clka(CLK), .clkb(CLK), .datain_a(BGB_COLINFO_D_A), .datain_b(1'b0), 
      .we_a(BGB_COLINFO_WE_A), .we_b(BGB_COLINFO_WE_B), 
      .dataout_a(), .dataout_b(BGB_COLINFO_Q_B)
   );
   assign BGB_COLINFO_WE_B = 1'b0;
   
   
   dpram_block #(9, 8) bga_ci(
      .addr_a(BGA_COLINFO_ADDR_A), .addr_b(BGA_COLINFO_ADDR_B), 
      .clka(CLK), .clkb(CLK), .datain_a(BGA_COLINFO_D_A), .datain_b(1'b0), 
      .we_a(BGA_COLINFO_WE_A), .we_b(BGA_COLINFO_WE_B), 
      .dataout_a(), .dataout_b(BGA_COLINFO_Q_B)
   );
   assign BGA_COLINFO_WE_B = 1'b0;
   
   
   dpram_block #(9, /*7*/8) obj_ci(
      .addr_a(OBJ_COLINFO_ADDR_A), .addr_b(OBJ_COLINFO_ADDR_B), 
      .clka(CLK), .clkb(CLK), .datain_a(1'b0), .datain_b(OBJ_COLINFO_D_B), 
      .we_a(OBJ_COLINFO_WE_A), .we_b(OBJ_COLINFO_WE_B), 
      .dataout_a(OBJ_COLINFO_Q_A), .dataout_b()
   );
   
   assign OBJ_COLINFO_CLK = (~CLK);
   assign OBJ_COLINFO_ADDR_A = (SP3C != SP3C_DONE) ? OBJ_COLINFO_ADDR_RD_SP3 : OBJ_COLINFO_ADDR_RD_REND;
   assign OBJ_COLINFO_ADDR_B = (SP3C != SP3C_DONE) ? OBJ_COLINFO_ADDR_WR_SP3 : OBJ_COLINFO_ADDR_WR_REND;
   assign OBJ_COLINFO_WE_A = 1'b0;
   assign OBJ_COLINFO_WE_B = (SP3C != SP3C_DONE) ? OBJ_COLINFO_WE_SP3 : OBJ_COLINFO_WE_REND;
   assign OBJ_COLINFO_D_B = (SP3C != SP3C_DONE) ? OBJ_COLINFO_D_SP3 : OBJ_COLINFO_D_REND;
   
   
   dpram_block #(9, /*7*/8) obj_ci2(
      .addr_a(OBJ_COLINFO2_ADDR_RD), .addr_b(OBJ_COLINFO2_ADDR_WR), 
      .clka(CLK), .clkb(CLK), .datain_a({7{1'b0}}), .datain_b(OBJ_COLINFO2_D), 
      .we_a(1'b0), .we_b(OBJ_COLINFO2_WE), 
      .dataout_a(OBJ_COLINFO2_Q), .dataout_b()
   );
   
   // byte-eanbled 128x32-bit RAM
   // obj_cache obj_cache(
   dpram32_block obj_cache (
      .clka(CLK), .clkb(CLK), 
      .addr_a(OBJ_CACHE_ADDR_RD), .we_a(1'b0), 
      .dataout_a(OBJ_CACHE_Q), .be_a(4'b1111),
      .addr_b(OBJ_CACHE_ADDR_WR), .we_b(OBJ_CACHE_WE[1]), 
      .datain_b(OBJ_CACHE_D), .be_b(OBJ_CACHE_BE)
   );
   
   assign OBJ_CACHE_ADDR_RD = (SP1C != SP1C_DONE) ? OBJ_CACHE_ADDR_RD_SP1 : 
                              OBJ_CACHE_ADDR_RD_SP2;
   
   dpram_block #(6, /*7*/8) obj_visinfo(
      .clka(CLK), .clkb(CLK), .datain_a({7{1'b0}}), .datain_b(OBJ_VISINFO_D), 
      .addr_a(OBJ_VISINFO_ADDR_RD), .addr_b(OBJ_VISINFO_ADDR_WR), 
      .we_a(1'b0), .we_b(OBJ_VISINFO_WE), 
      .dataout_a(OBJ_VISINFO_Q), .dataout_b()
   );
   
   
   dpram #(6, 35) obj_spinfo(
      .clock(CLK), .data_a(), .data_b(OBJ_SPINFO_D), 
      .address_a(OBJ_SPINFO_ADDR_RD), .address_b(OBJ_SPINFO_ADDR_WR), 
      .wren_a(1'b0), .wren_b(OBJ_SPINFO_WE), 
      .q_a(OBJ_SPINFO_Q), .q_b()
   );
      
   dpram_block #(6, /*9*/16) cram(
      .addr_a(CRAM_ADDR_A), .addr_b(CRAM_ADDR_B), 
      .clka(CLK), .clkb(CLK), .datain_a(CRAM_D_A), .datain_b({7{1'b0}}), 
      .we_a(CRAM_WE_A), .we_b(CRAM_WE_B), 
      .dataout_a(CRAM_Q_A), .dataout_b(CRAM_Q_B)
   );

   assign CRAM_WE_B = 1'b0;
   assign CRAM_DATA = (CRAM_WE_A & CRAM_DOTS) ? CRAM_D_A : 
                      CRAM_Q_B;
   
   
   dpram_block #(5, /*11*/16) vsram0(
      .addr_a(VSRAM0_ADDR_A), .addr_b(VSRAM0_ADDR_B), 
      .clka(CLK), .clkb(CLK), .datain_a(VSRAM0_D_A), .datain_b({9{1'b0}}), 
      .we_a(VSRAM0_WE_A), .we_b(VSRAM0_WE_B), 
      .dataout_a(VSRAM0_Q_A), .dataout_b(VSRAM0_Q_B)
   );
   assign VSRAM0_WE_B = 1'b0;
   
   
   dpram_block #(5, /*11*/16) vsram1(
      .addr_a(VSRAM1_ADDR_A), .addr_b(VSRAM1_ADDR_B), 
      .clka(CLK), .clkb(CLK), .datain_a(VSRAM1_D_A), .datain_b(1'b0), 
      .we_a(VSRAM1_WE_A), .we_b(VSRAM1_WE_B), 
      .dataout_a(VSRAM1_Q_A), .dataout_b(VSRAM1_Q_B)
   );
   assign VSRAM1_WE_B = 1'b0;
   
   //--------------------------------------------------------------
   // REGISTERS
   //--------------------------------------------------------------
   assign ADDR_STEP = REG[15];
   assign H40 = REG[12][0];
   assign RS0 = REG[12][7];
   
   assign SHI = REG[12][3];
   
   // H40 <= '0';
   assign V30 = REG[1][3];
   // V30 <= '0';
   assign HSCR = REG[11][1:0];
   assign HSIZE = REG[16][1:0];
   // VSIZE is limited to 64 if HSIZE is 64, to 32 if HSIZE is 128
   assign VSIZE = (REG[16][5:4] == 2'b11 & HSIZE == 2'b01) ? 2'b01 : 
                  (HSIZE == 2'b11) ? 2'b00 : 
                  REG[16][5:4];
   assign VSCR = REG[11][2];
   
   assign WVP = REG[18][4:0];
   assign WDOWN = REG[18][7];
   assign WHP = REG[17][4:0];
   assign WRIGT = REG[17][7];
   
   assign BGCOL = REG[7][5:0];
   
   assign HIT = REG[10];
   assign IE2 = REG[11][3];
   assign IE1 = REG[0][4];
   assign IE0 = REG[1][5];
   
   assign M3 = REG[0][1];
   
   assign DMA = REG[1][4];
   assign M128 = REG[1][7];
   
   assign LSM = REG[12][2:1];
   
   assign DE = REG[1][6];
   assign M5 = REG[1][2];
   
   // Base addresses
   assign HSCB = REG[13][5:0];
   assign NTBB = REG[4][2:0];
   assign NTWB = {REG[3][5:2], (REG[3][1] & (~H40))};
   assign NTAB = REG[2][5:3];
   assign SATB = {REG[5][7:1], (REG[5][0] & (~H40))};
   
   // Read-only registers
   assign ODD = (LSM[0]) ? FIELD : 1'b0;
   assign IN_DMA = DMA_FILL | DMA_COPY | DMA_VBUS;
   
   assign STATUS = {6'b111111, FIFO_EMPTY, FIFO_FULL, VINT_TG68_PENDING, SOVR, SCOL, ODD, (IN_VBL | ~DE), IN_HBL, IN_DMA, PAL};
   
   //--------------------------------------------------------------
   // CPU INTERFACE
   //--------------------------------------------------------------
   
   assign BGACK_N = BGACK_N_REG;
   
   //--------------------------------------------------------------
   // VRAM CONTROLLER
   //--------------------------------------------------------------
   assign vram32_req = (VMC32_NEXT != VMC32_IDLE & RAM_REQ_PROGRESS == 1'b0 & vram32_req_reg == vram32_ack) ? (~vram32_req_reg) : 
                       vram32_req_reg;
   assign vram32_a = (VMC32_NEXT != VMC32_IDLE & RAM_REQ_PROGRESS == 1'b0 & vram32_req_reg == vram32_ack) ? vram32_a_next : 
                     vram32_a_reg;
   
   // Get the ack and data one cycle earlier
   assign SP2_VRAM32_DO = (VMC32 == VMC32_SP2) ? vram32_q : SP2_VRAM32_DO_REG;
   assign SP3_VRAM32_DO = (VMC32 == VMC32_SP3) ? vram32_q : SP3_VRAM32_DO_REG;
   assign HSC_VRAM32_DO = (VMC32 == VMC32_HSC) ? vram32_q : HSC_VRAM32_DO_REG;
   assign BGB_VRAM32_DO = (VMC32 == VMC32_BGB) ? vram32_q : BGB_VRAM32_DO_REG;
   assign BGA_VRAM32_DO = (VMC32 == VMC32_BGA) ? vram32_q : BGA_VRAM32_DO_REG;
   
   assign SP2_VRAM32_ACK = (VMC32 == VMC32_SP2 & vram32_req_reg == vram32_ack & RAM_REQ_PROGRESS) ? 1'b1 : 1'b0;
   assign SP3_VRAM32_ACK = (VMC32 == VMC32_SP3 & vram32_req_reg == vram32_ack & RAM_REQ_PROGRESS) ? 1'b1 : SP3_VRAM32_ACK_REG;
   assign HSC_VRAM32_ACK = (VMC32 == VMC32_HSC & vram32_req_reg == vram32_ack & RAM_REQ_PROGRESS) ? 1'b1 : 1'b0;
   assign BGB_VRAM32_ACK = (VMC32 == VMC32_BGB & vram32_req_reg == vram32_ack & RAM_REQ_PROGRESS) ? 1'b1 : BGB_VRAM32_ACK_REG;
   assign BGA_VRAM32_ACK = (VMC32 == VMC32_BGA & vram32_req_reg == vram32_ack & RAM_REQ_PROGRESS) ? 1'b1 : BGA_VRAM32_ACK_REG;
   
   assign VMC32_NEXT = (SP3_SEL & SP3_VRAM32_ACK_REG == 1'b0) ? VMC32_SP3 : 
                       (SP2_SEL) ? VMC32_SP2 : 
                       (HSC_SEL) ? VMC32_HSC : 
                       (BGA_SEL & BGA_VRAM32_ACK_REG == 1'b0) ? VMC32_BGA : 
                       (BGB_SEL & BGB_VRAM32_ACK_REG == 1'b0) ? VMC32_BGB : 
                       VMC32_IDLE;
   
   
   always @* begin
      vram32_a_next = {15{1'b0}};
      if (vram32_req_reg == vram32_ack & RAM_REQ_PROGRESS == 1'b0)
         case (VMC32_NEXT)
            VMC32_IDLE : ;
            VMC32_SP2 : vram32_a_next = SP2_VRAM_ADDR;
            VMC32_SP3 : vram32_a_next = SP3_VRAM_ADDR;
            VMC32_HSC : vram32_a_next = HSC_VRAM_ADDR;
            VMC32_BGB : vram32_a_next = BGB_VRAM_ADDR;
            VMC32_BGA : vram32_a_next = BGA_VRAM_ADDR;
            default: ;
         endcase      
   end

   always @(posedge CLK)
   begin
      if (RST_N == 1'b0) begin
         
         vram32_req_reg <= 1'b0;
         
         VMC32 <= VMC32_IDLE;
         RAM_REQ_PROGRESS <= 1'b0;
         SP3_VRAM32_ACK_REG <= 1'b0;
         BGA_VRAM32_ACK_REG <= 1'b0;
         BGB_VRAM32_ACK_REG <= 1'b0;
      
      end else if (CE) begin  
         if (SP3_SEL == 1'b0)
            SP3_VRAM32_ACK_REG <= 1'b0;
         if (BGA_SEL == 1'b0)
            BGA_VRAM32_ACK_REG <= 1'b0;
         if (BGB_SEL == 1'b0)
            BGB_VRAM32_ACK_REG <= 1'b0;
         
         if (vram32_req_reg == vram32_ack) begin
            if (RAM_REQ_PROGRESS == 1'b0) begin
               VMC32 <= VMC32_NEXT;
               if (VMC32_NEXT != VMC32_IDLE) begin
                  vram32_a_reg <= vram32_a_next;
                  vram32_req_reg <= (~vram32_req_reg);
                  RAM_REQ_PROGRESS <= 1'b1;
               end 
            end else begin
               case (VMC32)
                  VMC32_IDLE :
                     ;
                  VMC32_SP2 :
                     SP2_VRAM32_DO_REG <= vram32_q;
                  VMC32_SP3 :
                     begin
                        SP3_VRAM32_DO_REG <= vram32_q;
                        SP3_VRAM32_ACK_REG <= 1'b1;
                     end
                  VMC32_HSC :
                     HSC_VRAM32_DO_REG <= vram32_q;
                  VMC32_BGB :
                     begin
                        BGB_VRAM32_DO_REG <= vram32_q;
                        BGB_VRAM32_ACK_REG <= 1'b1;
                     end
                  VMC32_BGA :
                     begin
                        BGA_VRAM32_DO_REG <= vram32_q;
                        BGA_VRAM32_ACK_REG <= 1'b1;
                     end
                  default: ;
               endcase
               RAM_REQ_PROGRESS <= 1'b0;
            end
         end 
      end 
   end
   
   // 16 bit interface for data transfer
   assign vram_req = DT_VRAM_SEL;
   assign vram_d = (M128 == 1'b0) ? DT_VRAM_DI : {DT_VRAM_DI[7:0], DT_VRAM_DI[7:0]};
   assign vram_we = (~DT_VRAM_RNW);
   assign vram_u_n = (DT_VRAM_UDS_N | M128) & ((~vram_a_reg[1]) | (~M128));
   assign vram_l_n = (DT_VRAM_LDS_N | M128) & (vram_a_reg[1] | (~M128));
   assign vram_a = (M128 == 1'b0) ? vram_a_reg[15:1] : {vram_a_reg[16:11], vram_a_reg[9:2], vram_a_reg[10]};
   assign vram_a_reg = DT_VRAM_ADDR;
   assign early_ack_dt = (DT_VRAM_SEL == vram_ack) ? 1'b0 : 1'b1;
   assign DT_VRAM_DO = vram_q;
   
   //--------------------------------------------------------------
   // HSCROLL READ
   //--------------------------------------------------------------
   
   always @(posedge CLK)
      if (RST_N == 1'b0)
         HSC_SEL <= 1'b0;
      else if (CE) begin
         if (V_ACTIVE & HV_HCNT == HSCROLL_READ & HV_PIXDIV == 0) begin
            
            case (HSCR)		// Horizontal scroll mode
               2'b00 :
                  HSC_VRAM_ADDR <= {HSCB, 9'b000000000};
               2'b01 :
                  HSC_VRAM_ADDR <= {HSCB, 5'b00000, Y[2:0], 1'b0};
               2'b10 :
                  HSC_VRAM_ADDR <= {HSCB, Y[7:3], 4'b0000};
               2'b11 :
                  HSC_VRAM_ADDR <= {HSCB, Y, 1'b0};
               default :
                  ;
            endcase
            HSC_SEL <= 1'b1;
         end else if (HSC_VRAM32_ACK)
            HSC_SEL <= 1'b0;
      end 
   
   //--------------------------------------------------------------
   // BACKGROUND B RENDERING
   //--------------------------------------------------------------
   assign BGB_TRANSP0 = ((BGB_VRAM32_DO[3:0] | BGB_VRAM32_DO[11:8]) == 4'b0000) ? 1'b1 : 1'b0;
   assign BGB_TRANSP1 = ((BGB_VRAM32_DO[7:4] | BGB_VRAM32_DO[15:12]) == 4'b0000) ? 1'b1 : 1'b0;
   assign BGB_TRANSP2 = ((BGB_VRAM32_DO[19:16] | BGB_VRAM32_DO[27:24]) == 4'b0000) ? 1'b1 : 1'b0;
   assign BGB_TRANSP3 = ((BGB_VRAM32_DO[23:20] | BGB_VRAM32_DO[31:28]) == 4'b0000) ? 1'b1 : 1'b0;
   
   always @(posedge CLK)
   begin
      reg [9:0]        V_BGB_XSTART;
      reg [15:0]       V_BGB_BASE;
      reg [15:0]       bgb_nametable_item;
      reg [10:0]       vscroll_mask;
      reg [9:0]        hscroll_mask;
      reg [10:0]       vscroll_val;
      reg [4:0]        vscroll_index;
      reg [6:0]        y_cells;
      
      if (RST_N == 1'b0) begin
         BGB_SEL <= 1'b0;
         BGB_ENABLE <= 1'b1;
         BGBC <= BGBC_DONE;
      end else if (CE) 
         case (BGBC)
            BGBC_DONE :
               begin
                  VSRAM1_ADDR_B <= {5{1'b0}};
                  if (HV_HCNT == H_INT_POS & HV_PIXDIV == 0 & VSCR == 1'b0) begin
                     BGB_VSRAM1_LATCH <= VSRAM1_Q_B;
                     BGB_VSRAM1_LAST_READ <= VSRAM1_Q_B;
                  end 
                  BGB_SEL <= 1'b0;
                  BGB_COLINFO_WE_A <= 1'b0;
                  BGB_COLINFO_ADDR_A <= {9{1'b0}};
                  if (BGEN_ACTIVATE)
                     BGBC <= BGBC_INIT;
               end
            
            BGBC_INIT :
               begin
                  if (HSIZE == 2'b10) begin
                     // illegal mode, 32x1
                     hscroll_mask = 10'b0011111111;
                     vscroll_mask = 11'b00000000111;
                  end else begin
                     hscroll_mask = ({HSIZE, 8'b11111111});
                     vscroll_mask = {1'b0, ({VSIZE, 8'b11111111})};
                  end
                  
                  if (LSM == 2'b11)
                     vscroll_mask = {vscroll_mask[9:0], 1'b1};
                  
                  V_BGB_XSTART = 10'b0000000000 - HSC_VRAM32_DO[25:16];
                  if (V_BGB_XSTART[3:0] == 4'b0000) begin
                     V_BGB_XSTART = V_BGB_XSTART - 16;
                     BGB_POS <= 10'b1111110000;
                  end else
                     BGB_POS <= 10'b0000000000 - ({6'b000000, V_BGB_XSTART[3:0]});
                  BGB_X <= ({V_BGB_XSTART[9:4], 4'b0000}) & hscroll_mask;
                  BGB_COL <= 7'b1111110;		// -2
                  BGBC <= BGBC_GET_VSCROLL;
               end
            
            BGBC_GET_VSCROLL :
               begin
                  BGB_COLINFO_WE_A <= 1'b0;
                  if (BGB_COL[5:1] <= 19)
                     VSRAM1_ADDR_B <= BGB_COL[5:1];
                  else
                     VSRAM1_ADDR_B <= {5{1'b0}};
                  BGBC <= BGBC_GET_VSCROLL2;
               end
            
            BGBC_GET_VSCROLL2 :
               BGBC <= BGBC_GET_VSCROLL3;
            
            BGBC_GET_VSCROLL3 :
               begin
                  if (VSCR) begin
                     if (BGB_COL[5:1] <= 19) begin
                        BGB_VSRAM1_LATCH <= VSRAM1_Q_B;
                        BGB_VSRAM1_LAST_READ <= VSRAM1_Q_B;
                     end else if (H40 == 1'b0)
                        BGB_VSRAM1_LATCH <= {11{1'b0}};
                     else if (VSCROLL_BUG)
                        // partial column gets the last read values AND'ed in H40 ("left column scroll bug")
                        BGB_VSRAM1_LATCH <= BGB_VSRAM1_LAST_READ & BGA_VSRAM0_LAST_READ;
                     else
                        // using VSRAM(1) sometimes looks better (Gynoug)
                        BGB_VSRAM1_LATCH <= VSRAM1_Q_B;
                  end 
                  BGBC <= BGBC_CALC_Y;
               end
            
            BGBC_CALC_Y :
               begin
                  if (LSM == 2'b11)
                     vscroll_val = BGB_VSRAM1_LATCH[10:0];
                  else
                     vscroll_val = {1'b0, BGB_VSRAM1_LATCH[9:0]};
                  BGB_Y <= (BG_Y + vscroll_val) & vscroll_mask;
                  BGBC <= BGBC_CALC_BASE;
               end
            
            BGBC_CALC_BASE :
               if (BGB_MAPPING_EN) begin
                  // BGB mapping slot
                  if (LSM == 2'b11)
                     y_cells = BGB_Y[10:4];
                  else
                     y_cells = BGB_Y[9:3];
                  case (HSIZE)
                     2'b00, 2'b10 :		// HS 32 cells
                        V_BGB_BASE = {NTBB, 13'b0000000000000} + {BGB_X[9:3], 1'b0} + {y_cells, 5'b00000, 1'b0};
                     2'b01 :		      // HS 64 cells
                        V_BGB_BASE = {NTBB, 13'b0000000000000} + {BGB_X[9:3], 1'b0} + {y_cells, 6'b000000, 1'b0};
                     2'b11 :		      // HS 128 cells
                        V_BGB_BASE = {NTBB, 13'b0000000000000} + {BGB_X[9:3], 1'b0} + {y_cells, 7'b0000000, 1'b0};
                     default :
                        ;
                  endcase
                  BGB_VRAM_ADDR <= V_BGB_BASE[15:1];
                  BGB_ENABLE <= DE;
                  if (DE) begin
                     BGB_SEL <= 1'b1;
                     BGBC <= BGBC_BASE_RD;
                  end else
                     BGBC <= BGBC_LOOP;
               end 
            
            BGBC_BASE_RD :
               if (BGB_VRAM32_ACK) begin
                  BGB_SEL <= 1'b0;
                  BGB_NAMETABLE_ITEMS <= BGB_VRAM32_DO;
                  BGBC <= BGBC_TILE_RD;
               end 
            
            BGBC_TILE_RD :
               begin
                  // BGB pattern slot
                  BGB_COLINFO_WE_A <= 1'b0;
                  
                  if (BGB_X[3] == 1'b0)
                     bgb_nametable_item = BGB_NAMETABLE_ITEMS[15:0];
                  else
                     bgb_nametable_item = BGB_NAMETABLE_ITEMS[31:16];
                  T_BGB_PRI <= bgb_nametable_item[15];
                  T_BGB_PAL <= bgb_nametable_item[14:13];
                  BGB_HF <= bgb_nametable_item[11];
                  if (LSM == 2'b11) begin
                     if (bgb_nametable_item[12])		// VF
                        BGB_VRAM_ADDR <= {bgb_nametable_item[9:0], (~(BGB_Y[3:0])), 1'b0};
                     else
                        BGB_VRAM_ADDR <= {bgb_nametable_item[9:0], BGB_Y[3:0], 1'b0};
                  end else
                     if (bgb_nametable_item[12])		// VF
                        BGB_VRAM_ADDR <= {bgb_nametable_item[10:0], (~(BGB_Y[2:0])), 1'b0};
                     else
                        BGB_VRAM_ADDR <= {bgb_nametable_item[10:0], BGB_Y[2:0], 1'b0};
                  
                  if (BGB_ENABLE)
                     BGB_SEL <= 1'b1;
                  BGBC <= BGBC_LOOP;
               end
            
            BGBC_LOOP :
               if (BGB_VRAM32_ACK | BGB_SEL == 1'b0 | BGB_ENABLE == 1'b0) begin
                  BGB_SEL <= 1'b0;
                  
                  BGB_COLINFO_ADDR_A <= BGB_POS[8:0];
                  BGB_COLINFO_WE_A <= 1'b1;
                  case (BGB_X[2:0])
                     3'b100 :
                        if (BGB_HF)
                           BGB_COLINFO_D_A <= {(BGB_TRANSP0 ^ BGB_TRANSP1), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[3:0]};
                        else
                           BGB_COLINFO_D_A <= {(BGB_TRANSP2 ^ BGB_TRANSP3), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[31:28]};
                     3'b101 :
                        if (BGB_HF)
                           BGB_COLINFO_D_A <= {(BGB_TRANSP0 ^ BGB_TRANSP1), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[7:4]};
                        else
                           BGB_COLINFO_D_A <= {(BGB_TRANSP2 ^ BGB_TRANSP3), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[27:24]};
                     3'b110 :
                        if (BGB_HF)
                           BGB_COLINFO_D_A <= {(BGB_TRANSP0 ^ BGB_TRANSP1), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[11:8]};
                        else
                           BGB_COLINFO_D_A <= {(BGB_TRANSP2 ^ BGB_TRANSP3), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[23:20]};
                     3'b111 :
                        if (BGB_HF)
                           BGB_COLINFO_D_A <= {(BGB_TRANSP0 ^ BGB_TRANSP1), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[15:12]};
                        else
                           BGB_COLINFO_D_A <= {(BGB_TRANSP2 ^ BGB_TRANSP3), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[19:16]};
                     3'b000 :
                        if (BGB_HF)
                           BGB_COLINFO_D_A <= {(BGB_TRANSP2 ^ BGB_TRANSP3), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[19:16]};
                        else
                           BGB_COLINFO_D_A <= {(BGB_TRANSP0 ^ BGB_TRANSP1), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[15:12]};
                     3'b001 :
                        if (BGB_HF)
                           BGB_COLINFO_D_A <= {(BGB_TRANSP2 ^ BGB_TRANSP3), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[23:20]};
                        else
                           BGB_COLINFO_D_A <= {(BGB_TRANSP0 ^ BGB_TRANSP1), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[11:8]};
                     3'b010 :
                        if (BGB_HF)
                           BGB_COLINFO_D_A <= {(BGB_TRANSP2 ^ BGB_TRANSP3), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[27:24]};
                        else
                           BGB_COLINFO_D_A <= {(BGB_TRANSP0 ^ BGB_TRANSP1), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[7:4]};
                     3'b011 :
                        if (BGB_HF)
                           BGB_COLINFO_D_A <= {(BGB_TRANSP2 ^ BGB_TRANSP3), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[31:28]};
                        else
                           BGB_COLINFO_D_A <= {(BGB_TRANSP0 ^ BGB_TRANSP1), T_BGB_PRI, T_BGB_PAL, BGB_VRAM32_DO[3:0]};
                     default :
                        ;
                  endcase
                  
                  if (BGB_ENABLE == 1'b0 | DE == 1'b0)
                     BGB_COLINFO_D_A <= {2'b00, BGCOL};
                  
                  BGB_X <= (BGB_X + 1) & hscroll_mask;
                  BGB_POS <= BGB_POS + 1;
                  if (BGB_X[2:0] == 3'b111) begin
                     BGB_COL <= BGB_COL + 1;
                     if ((H40 == 1'b0 & BGB_COL == 31) | (H40 & BGB_COL == 39))
                        BGBC <= BGBC_DONE;
                     else if (BGB_X[3] == 1'b0)
                        BGBC <= BGBC_TILE_RD;
                     else
                        BGBC <= BGBC_GET_VSCROLL;
                  end else
                     BGBC <= BGBC_LOOP;
               end 
            default :		// BGBC_DONE
               begin
                  BGB_SEL <= 1'b0;
                  BGB_COLINFO_WE_A <= 1'b0;
               end
         endcase
   end
   
   //--------------------------------------------------------------
   // BACKGROUND A RENDERING
   //--------------------------------------------------------------
   assign BGA_TRANSP0 = ((BGA_VRAM32_DO[3:0] | BGA_VRAM32_DO[11:8]) == 4'b0000) ? 1'b1 : 1'b0;
   assign BGA_TRANSP1 = ((BGA_VRAM32_DO[7:4] | BGA_VRAM32_DO[15:12]) == 4'b0000) ? 1'b1 : 1'b0;
   assign BGA_TRANSP2 = ((BGA_VRAM32_DO[19:16] | BGA_VRAM32_DO[27:24]) == 4'b0000) ? 1'b1 : 1'b0;
   assign BGA_TRANSP3 = ((BGA_VRAM32_DO[23:20] | BGA_VRAM32_DO[31:28]) == 4'b0000) ? 1'b1 : 1'b0;
   
   always @(posedge CLK)
   begin
      reg [9:0]        V_BGA_XSTART;
      reg [15:0]       V_BGA_XBASE;
      reg [15:0]       V_BGA_BASE;
      reg [9:0]        bga_pos_next;
      reg [15:0]       bga_nametable_item;
      reg [3:0]        tile_pos;
      reg [10:0]       vscroll_mask;
      reg [9:0]        hscroll_mask;
      reg [10:0]       vscroll_val;
      reg [4:0]        vscroll_index;
      reg [6:0]        y_cells;

      if (RST_N == 1'b0) begin
         BGA_SEL <= 1'b0;
         BGAC <= BGAC_DONE;
         BGA_ENABLE <= 1'b1;
      end else if (CE)
         case (BGAC)
            BGAC_DONE :    // 9
               begin
                  VSRAM0_ADDR_B <= {5{1'b0}};
                  if (HV_HCNT == H_INT_POS & HV_PIXDIV == 0) begin
                     if (VSCR == 1'b0) begin
                        BGA_VSRAM0_LATCH <= VSRAM0_Q_B;
                        BGA_VSRAM0_LAST_READ <= VSRAM0_Q_B;
                     end 
                     WRIGT_LATCH <= WRIGT;
                     WHP_LATCH <= WHP;
                  end 
                  BGA_SEL <= 1'b0;
                  BGA_COLINFO_ADDR_A <= {9{1'b0}};
                  BGA_COLINFO_WE_A <= 1'b0;
                  if (BGEN_ACTIVATE)
                     BGAC <= BGAC_INIT;
               end
            BGAC_INIT :    // 0
               begin
                  if (HSIZE == 2'b10) begin
                     // illegal mode, 32x1
                     hscroll_mask = 10'b0011111111;
                     vscroll_mask = 11'b00000000111;
                  end else begin
                     hscroll_mask = ({HSIZE, 8'b11111111});
                     vscroll_mask = {1'b0, ({VSIZE, 8'b11111111})};
                  end
                  
                  if (LSM == 2'b11)
                     vscroll_mask = {vscroll_mask[9:0], 1'b1};
                  
                  if (Y[7:3] < WVP)
                     WIN_V <= (~WDOWN);
                  else
                     WIN_V <= WDOWN;
                  
                  if (WHP_LATCH == 5'b00000)
                     WIN_H <= WRIGT_LATCH;
                  else
                     WIN_H <= (~WRIGT_LATCH);
                  
                  V_BGA_XSTART = 10'b0000000000 - HSC_VRAM32_DO[9:0];
                  if (V_BGA_XSTART[3:0] == 4'b0000) begin
                     V_BGA_XSTART = V_BGA_XSTART - 16;
                     BGA_POS <= 10'b1111110000;
                  end else
                     BGA_POS <= 10'b0000000000 - ({6'b000000, V_BGA_XSTART[3:0]});
                  
                  BGA_X <= ({V_BGA_XSTART[9:4], 4'b0000}) & hscroll_mask;
                  BGA_COL <= 7'b1111110;		// -2
                  BGAC <= BGAC_GET_VSCROLL;
               end
            
            BGAC_GET_VSCROLL :      // 1
               begin
                  BGA_COLINFO_WE_A <= 1'b0;
                  
                  if (BGA_COL[5:1] <= 19)
                     VSRAM0_ADDR_B <= BGA_COL[5:1];
                  else
                     VSRAM0_ADDR_B <= {5{1'b0}};
                  BGAC <= BGAC_GET_VSCROLL2;
               end
            
            BGAC_GET_VSCROLL2 :  // 2
               BGAC <= BGAC_GET_VSCROLL3;
            
            BGAC_GET_VSCROLL3 :  // 3
               begin
                  if (VSCR) begin
                     if (BGA_COL[5:1] <= 19) begin
                        BGA_VSRAM0_LATCH <= VSRAM0_Q_B;
                        BGA_VSRAM0_LAST_READ <= VSRAM0_Q_B;
                     end else if (H40 == 1'b0)
                        BGA_VSRAM0_LATCH <= {11{1'b0}};
                     else if (VSCROLL_BUG)
                        // partial column gets the last read values AND'ed in H40 ("left column scroll bug")
                        BGA_VSRAM0_LATCH <= BGA_VSRAM0_LAST_READ & BGB_VSRAM1_LAST_READ;
                     else
                        // using VSRAM(0) sometimes looks better (Gynoug)
                        BGA_VSRAM0_LATCH <= VSRAM0_Q_B;
                  end 
                  BGAC <= BGAC_CALC_Y;
               end
            
            BGAC_CALC_Y :  // 4
               begin
                  if (WIN_H | WIN_V)
                     BGA_Y <= {2'b00, BG_Y};
                  else begin
                     if (LSM == 2'b11)
                        vscroll_val = BGA_VSRAM0_LATCH[10:0];
                     else
                        vscroll_val = {1'b0, BGA_VSRAM0_LATCH[9:0]};
                     BGA_Y <= (BG_Y + vscroll_val) & vscroll_mask;
                  end
                  BGAC <= BGAC_CALC_BASE;
               end
            
            BGAC_CALC_BASE :  // 5
               if (BGA_MAPPING_EN) begin
                  // BGA mapping slot
                  if (LSM == 2'b11)
                     y_cells = BGA_Y[10:4];
                  else
                     y_cells = BGA_Y[9:3];
                  
                  if (WIN_H | WIN_V) begin
                     V_BGA_XBASE = ({NTWB, 11'b00000000000}) + ({BGA_POS[9:3], 1'b0});
                     if (H40 == 1'b0)		// WIN is 32 tiles wide in H32 mode
                        V_BGA_BASE = V_BGA_XBASE + ({y_cells, 5'b00000, 1'b0});
                     else
                        // WIN is 64 tiles wide in H40 mode
                        V_BGA_BASE = V_BGA_XBASE + ({y_cells, 6'b000000, 1'b0});
                  end else begin
                     V_BGA_XBASE = ({NTAB, 13'b0000000000000}) + ({BGA_X[9:3], 1'b0});
                     case (HSIZE)
                        2'b00, 2'b10 :		// HS 32 cells
                           V_BGA_BASE = V_BGA_XBASE + ({y_cells, 5'b00000, 1'b0});
                        2'b01 :		// HS 64 cells
                           V_BGA_BASE = V_BGA_XBASE + ({y_cells, 6'b000000, 1'b0});
                        2'b11 :		// HS 128 cells
                           V_BGA_BASE = V_BGA_XBASE + ({y_cells, 7'b0000000, 1'b0});
                        default :
                           ;
                     endcase
                  end
                  
                  BGA_VRAM_ADDR <= V_BGA_BASE[15:1];
                  BGA_ENABLE <= DE;
                  if (DE) begin
                     BGA_SEL <= 1'b1;
                     BGAC <= BGAC_BASE_RD;
                  end else
                     BGAC <= BGAC_LOOP;
               end 
            
            BGAC_BASE_RD :    // 6
               if (BGA_VRAM32_ACK) begin
                  BGA_SEL <= 1'b0;
                  BGA_NAMETABLE_ITEMS <= BGA_VRAM32_DO;
                  BGAC <= BGAC_TILE_RD;
               end 
            
            BGAC_TILE_RD :    // 7
               begin
                  // BGA pattern slot
                  BGA_COLINFO_WE_A <= 1'b0;
                  
                  if (((WIN_H | WIN_V) & BGA_POS[3] == 1'b0) | (WIN_H == 1'b0 & WIN_V == 1'b0 & BGA_X[3] == 1'b0))
                     bga_nametable_item = BGA_NAMETABLE_ITEMS[15:0];
                  else
                     bga_nametable_item = BGA_NAMETABLE_ITEMS[31:16];
                  
                  T_BGA_PRI <= bga_nametable_item[15];
                  T_BGA_PAL <= bga_nametable_item[14:13];
                  BGA_HF <= bga_nametable_item[11];
                  if (LSM == 2'b11) begin
                     if (bga_nametable_item[12])		// VF
                        BGA_VRAM_ADDR <= {bga_nametable_item[9:0], (~(BGA_Y[3:0])), 1'b0};
                     else
                        BGA_VRAM_ADDR <= {bga_nametable_item[9:0], BGA_Y[3:0], 1'b0};
                  end else
                     if (bga_nametable_item[12])		// VF
                        BGA_VRAM_ADDR <= {bga_nametable_item[10:0], (~(BGA_Y[2:0])), 1'b0};
                     else
                        BGA_VRAM_ADDR <= {bga_nametable_item[10:0], BGA_Y[2:0], 1'b0};
                  
                  if (BGA_ENABLE)
                     BGA_SEL <= 1'b1;
                  BGAC <= BGAC_LOOP;
               end
            
            BGAC_LOOP :    // 8
               if (BGA_VRAM32_ACK | BGA_SEL == 1'b0 | BGA_ENABLE == 1'b0) begin
                  BGA_SEL <= 1'b0;
                  
                  if (SVP_QUIRK == 1'b0 | BG_Y != 223)
                     BGA_COLINFO_WE_A <= 1'b1;
                  
                  BGA_COLINFO_ADDR_A <= BGA_POS[8:0];
                  if (WIN_H | WIN_V)
                     tile_pos = BGA_POS[3:0];
                  else
                     tile_pos = BGA_X[3:0];
                  case (tile_pos[2:0])
                     3'b100 :
                        if (BGA_HF)
                           BGA_COLINFO_D_A <= {(BGA_TRANSP0 ^ BGA_TRANSP1), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[3:0]};
                        else
                           BGA_COLINFO_D_A <= {(BGA_TRANSP2 ^ BGA_TRANSP3), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[31:28]};
                     3'b101 :
                        if (BGA_HF)
                           BGA_COLINFO_D_A <= {(BGA_TRANSP0 ^ BGA_TRANSP1), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[7:4]};
                        else
                           BGA_COLINFO_D_A <= {(BGA_TRANSP2 ^ BGA_TRANSP3), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[27:24]};
                     3'b110 :
                        if (BGA_HF)
                           BGA_COLINFO_D_A <= {(BGA_TRANSP0 ^ BGA_TRANSP1), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[11:8]};
                        else
                           BGA_COLINFO_D_A <= {(BGA_TRANSP2 ^ BGA_TRANSP3), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[23:20]};
                     3'b111 :
                        if (BGA_HF)
                           BGA_COLINFO_D_A <= {(BGA_TRANSP0 ^ BGA_TRANSP1), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[15:12]};
                        else
                           BGA_COLINFO_D_A <= {(BGA_TRANSP2 ^ BGA_TRANSP3), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[19:16]};
                     3'b000 :
                        if (BGA_HF)
                           BGA_COLINFO_D_A <= {(BGA_TRANSP2 ^ BGA_TRANSP3), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[19:16]};
                        else
                           BGA_COLINFO_D_A <= {(BGA_TRANSP0 ^ BGA_TRANSP1), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[15:12]};
                     3'b001 :
                        if (BGA_HF)
                           BGA_COLINFO_D_A <= {(BGA_TRANSP2 ^ BGA_TRANSP3), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[23:20]};
                        else
                           BGA_COLINFO_D_A <= {(BGA_TRANSP0 ^ BGA_TRANSP1), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[11:8]};
                     3'b010 :
                        if (BGA_HF)
                           BGA_COLINFO_D_A <= {(BGA_TRANSP2 ^ BGA_TRANSP3), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[27:24]};
                        else
                           BGA_COLINFO_D_A <= {(BGA_TRANSP0 ^ BGA_TRANSP1), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[7:4]};
                     3'b011 :
                        if (BGA_HF)
                           BGA_COLINFO_D_A <= {(BGA_TRANSP2 ^ BGA_TRANSP3), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[31:28]};
                        else
                           BGA_COLINFO_D_A <= {(BGA_TRANSP0 ^ BGA_TRANSP1), T_BGA_PRI, T_BGA_PAL, BGA_VRAM32_DO[3:0]};
                     default :
                        ;
                  endcase
                  
                  if (BGA_ENABLE == 1'b0 | DE == 1'b0)
                     BGA_COLINFO_D_A <= {2'b00, BGCOL};
                  
                  BGA_X <= (BGA_X + 1) & hscroll_mask;
                  bga_pos_next = BGA_POS + 1;
                  BGA_POS <= bga_pos_next;
                  if (tile_pos[2:0] == 3'b111) begin
                     if (tile_pos[3] == 1'b0)
                        BGAC <= BGAC_TILE_RD;
                     else
                        BGAC <= BGAC_GET_VSCROLL;
                  end else
                     BGAC <= BGAC_LOOP;
                  
                  if (WIN_H & WRIGT_LATCH == 1'b0 & BGA_POS[3:0] == 4'b1111 & bga_pos_next[8:4] == WHP_LATCH) begin
                     // window on the left side ends, but not neccessarily on a scroll boundary,
                     // when it continues to draw a wrong tile ("left window bug")
                     WIN_H <= 1'b0;
                     if (WIN_V == 1'b0 & BGA_X[3:0] != 4'b1111)
                        BGAC <= BGAC_LOOP;
                  end else if (WIN_H == 1'b0 & WRIGT_LATCH & BGA_POS[3:0] == 4'b1111 & bga_pos_next[8:4] == WHP_LATCH) begin
                     // window on the right side starts, cancel rendering the current tile
                     WIN_H <= 1'b1;
                     BGAC <= BGAC_GET_VSCROLL;
                  end 
                  
                  if (BGA_X[2:0] == 3'b111) begin
                     BGA_COL <= BGA_COL + 1;
                     if ((H40 == 1'b0 & BGA_COL == 31) | (H40 & BGA_COL == 39))
                        BGAC <= BGAC_DONE;
                  end 
               end 
            default :		// BGAC_DONE
               begin
                  BGA_SEL <= 1'b0;
                  BGA_COLINFO_WE_A <= 1'b0;
               end
         endcase
   end
   
   //--------------------------------------------------------------
   // SPRITE ENGINE
   //--------------------------------------------------------------
   assign OBJ_MAX_FRAME = (H40) ? OBJ_MAX_FRAME_H40 : OBJ_MAX_FRAME_H32;
   
   assign OBJ_MAX_LINE = (H40 & OBJ_LIMIT_HIGH_EN == 1'b0) ? OBJ_MAX_LINE_H40 : 
                         (H40 & OBJ_LIMIT_HIGH_EN) ? OBJ_MAX_LINE_H40_HIGH : 
                         (H40 == 1'b0 & OBJ_LIMIT_HIGH_EN == 1'b0) ? OBJ_MAX_LINE_H32 : 
                         /*(H40 == 1'b0 & OBJ_LIMIT_HIGH_EN) ?*/ OBJ_MAX_LINE_H32_HIGH ;
   
   // Write-through cache for Y, Link and size fields
   always @(posedge CLK)
   begin
      reg [13:0]       cache_addr;
      if (RST_N == 1'b0) begin
         
         OBJ_CACHE_ADDR_WR <= {7{1'b0}};
         OBJ_CACHE_WE <= 2'b00;
      
      end else if (CE) begin
         
         OBJ_CACHE_WE <= {OBJ_CACHE_WE[0], 1'b0};
         
         cache_addr = DT_VRAM_ADDR[16:3] - ({SATB, 6'b000000});
         DT_VRAM_SEL_D <= DT_VRAM_SEL;
         if (DT_VRAM_SEL_D != DT_VRAM_SEL & DT_VRAM_RNW == 1'b0 & DT_VRAM_ADDR[2] == 1'b0 & cache_addr < OBJ_MAX_FRAME) begin
            OBJ_CACHE_ADDR_WR <= cache_addr[6:0];
            OBJ_CACHE_D <= {DT_VRAM_DI, DT_VRAM_DI};
            OBJ_CACHE_BE[3] <= DT_VRAM_ADDR[1] & (~DT_VRAM_UDS_N);
            OBJ_CACHE_BE[2] <= DT_VRAM_ADDR[1] & (~DT_VRAM_LDS_N);
            OBJ_CACHE_BE[1] <= (~DT_VRAM_ADDR[1]) & (~DT_VRAM_UDS_N);
            OBJ_CACHE_BE[0] <= (~DT_VRAM_ADDR[1]) & (~DT_VRAM_LDS_N);
            OBJ_CACHE_WE <= 2'b01;
         end 
      end 
   end
   
   //--------------------------------------------------------------
   // SPRITE ENGINE - PART ONE
   //----------------------------------------------------------------
   // determine the first 16/20 visible sprites
   always @(posedge CLK)
   begin
      reg [9:0]        y_offset;

      if (RST_N == 1'b0) begin
         SP1C <= SP1C_DONE;
         OBJ_CACHE_ADDR_RD_SP1 <= {7{1'b0}};
         
         OBJ_VISINFO_ADDR_WR <= {6{1'b0}};
      
      end else if (CE) 
         
         case (SP1C)
            SP1C_INIT :
               begin
                  SP1_Y <= PRE_Y;		// Latch the current PRE_Y value
                  OBJ_TOT <= {7{1'b0}};
                  OBJ_NEXT <= {7{1'b0}};
                  OBJ_NB <= {6{1'b0}};
                  OBJ_VISINFO_WE <= 1'b0;
                  SP1_STEPS <= {7{1'b0}};
                  SP1C <= SP1C_Y_RD;
               end
            
            SP1C_Y_RD :
               begin
                  if (SP1_EN & DE) begin		//check one sprite/pixel, this matches the original HW behavior
                     OBJ_CACHE_ADDR_RD_SP1 <= OBJ_NEXT;
                     SP1C <= SP1C_Y_RD2;
                  end 
                  
                  if (SP1_EN)
                     SP1_STEPS <= SP1_STEPS + 1;
                  if (SP1_STEPS == OBJ_MAX_FRAME)
                     SP1C <= SP1C_DONE;
               end
            
            SP1C_Y_RD2 :
               SP1C <= SP1C_Y_RD3;
            
            SP1C_Y_RD3 :
               begin
                  if (LSM == 2'b11) begin
                     y_offset = 10'b0100000000 + SP1_Y - OBJ_CACHE_Q[9:0];
                     OBJ_Y_OFS <= y_offset[9:1];
                  end else begin
                     y_offset = 10'b0010000000 + SP1_Y - ({1'b0, OBJ_CACHE_Q[8:0]});
                     OBJ_Y_OFS <= y_offset[8:0];
                  end
                  OBJ_VS1 <= OBJ_CACHE_Q[25:24];
                  OBJ_LINK <= OBJ_CACHE_Q[22:16];
                  SP1C <= SP1C_Y_TST;
               end
            
            SP1C_Y_TST :
               begin
                  SP1C <= SP1C_NEXT;
                  if ((OBJ_VS1 == 2'b00 & OBJ_Y_OFS[8:3] == 6'b000000) |   // 8 pix
                      (OBJ_VS1 == 2'b01 & OBJ_Y_OFS[8:4] == 5'b00000) |    // 16 pix
                      (OBJ_VS1 == 2'b11 & OBJ_Y_OFS[8:5] == 4'b0000) |     // 32 pix
                      (OBJ_VS1 == 2'b10 & OBJ_Y_OFS[8:5] == 4'b0000 & OBJ_Y_OFS[4:3] != 2'b11))		//24 pix
                     SP1C <= SP1C_SHOW;
               end
            
            SP1C_SHOW :
               begin
                  OBJ_NB <= OBJ_NB + 1;
                  OBJ_VISINFO_WE <= 1'b1;
                  OBJ_VISINFO_ADDR_WR <= OBJ_NB;
                  OBJ_VISINFO_D <= OBJ_NEXT;
                  SP1C <= SP1C_NEXT;
               end
            
            SP1C_NEXT :
               begin
                  OBJ_VISINFO_WE <= 1'b0;
                  OBJ_TOT <= OBJ_TOT + 1;
                  OBJ_NEXT <= OBJ_LINK;
                  
                  // limit number of sprites per line to 20 / 16
                  if (OBJ_NB == OBJ_MAX_LINE)
                     SP1C <= SP1C_DONE;
                  // check a total of 80 sprites in H40 mode and 64 sprites in H32 mode
                  // the following checks are inspired by the gens-ii emulator
                  else if (OBJ_TOT == OBJ_MAX_FRAME - 1 | OBJ_LINK >= OBJ_MAX_FRAME | OBJ_LINK == 7'b0000000)
                     SP1C <= SP1C_DONE;
                  else
                     SP1C <= SP1C_Y_RD;
               end
            
            default :		// SP1C_DONE
               begin
                  OBJ_VISINFO_WE <= 1'b0;
                  OBJ_VISINFO_ADDR_WR <= {6{1'b0}};
                  
                  if (SP1E_ACTIVATE)
                     SP1C <= SP1C_INIT;
               end
         endcase
   end
   
   //--------------------------------------------------------------
   // SPRITE ENGINE - PART TWO
   //--------------------------------------------------------------
   //fetch X and size info for visible sprites
   always @(posedge CLK)
   begin
      reg [9:0]        y_offset;

      if (RST_N == 1'b0) begin
         SP2_SEL <= 1'b0;
         SP2C <= SP2C_DONE;
         OBJ_CACHE_ADDR_RD_SP2 <= {7{1'b0}};
         OBJ_SPINFO_ADDR_WR <= {6{1'b0}};
         OBJ_SPINFO_WE <= 1'b0;
      
      end else if (CE) 
         
         case (SP2C)
            SP2C_INIT :
               begin
                  SP2_Y <= PRE_Y;		// Latch the current PRE_Y value
                  
                  // Treat VISINFO as a shift register, so start reading
                  // from the first unused location.
                  // This way visible sprites processed late.
                  if (OBJ_NB == OBJ_MAX_LINE) begin
                     OBJ_IDX <= {6{1'b0}};
                     OBJ_VISINFO_ADDR_RD <= {6{1'b0}};
                  end else begin
                     OBJ_IDX <= OBJ_NB;
                     OBJ_VISINFO_ADDR_RD <= OBJ_NB;
                  end
                  
                  SP2C <= SP2C_Y_RD;
               end
            
            SP2C_Y_RD :
               if (SP2_EN) begin
                  if (OBJ_IDX < OBJ_NB)
                     SP2C <= SP2C_Y_RD2;
                  else
                     SP2C <= SP2C_NEXT;
               end 
            
            SP2C_Y_RD2 :
               begin
                  OBJ_CACHE_ADDR_RD_SP2 <= OBJ_VISINFO_Q[6:0];
                  SP2C <= SP2C_Y_RD3;
               end
            SP2C_Y_RD3 :
               SP2C <= SP2C_Y_RD4;
            SP2C_Y_RD4 :
               begin
                  if (LSM == 2'b11)
                     y_offset = 10'b0100000000 + SP2_Y - OBJ_CACHE_Q[9:0];
                  else
                     y_offset = 10'b0010000000 + SP2_Y - ({1'b0, OBJ_CACHE_Q[8:0]});
                  //save only the last 5(6 in doubleres) bits of the offset for part 3
                  //Titan 2 textured cube (ab)uses this
                  OBJ_SPINFO_D[5:0] <= y_offset[5:0];		//Y offset
                  OBJ_SPINFO_D[7:6] <= OBJ_CACHE_Q[25:24];		//VS
                  OBJ_SPINFO_D[9:8] <= OBJ_CACHE_Q[27:26];		//HS
                  
                  SP2_VRAM_ADDR <= ({SATB[6:0], 8'b00000000}) + ({OBJ_VISINFO_Q[6:0], 2'b10});
                  SP2_SEL <= 1'b1;
                  
                  SP2C <= SP2C_RD;
               end
            
            SP2C_RD :
               if (SP2_VRAM32_ACK) begin
                  SP2_SEL <= 1'b0;
                  OBJ_SPINFO_D[34] <= SP2_VRAM32_DO[15];		//PRI
                  OBJ_SPINFO_D[33:32] <= SP2_VRAM32_DO[14:13];		//PAL
                  OBJ_SPINFO_D[31] <= SP2_VRAM32_DO[12];		//VF
                  OBJ_SPINFO_D[30] <= SP2_VRAM32_DO[11];		//HF
                  OBJ_SPINFO_D[29:19] <= SP2_VRAM32_DO[10:0];		//PAT
                  OBJ_SPINFO_D[18:10] <= SP2_VRAM32_DO[24:16];		//X
                  OBJ_SPINFO_ADDR_WR <= OBJ_IDX;
                  OBJ_SPINFO_WE <= 1'b1;
                  SP2C <= SP2C_NEXT;
               end 
            
            SP2C_NEXT :
               begin
                  OBJ_SPINFO_WE <= 1'b0;
                  SP2C <= SP2C_Y_RD;
                  if (OBJ_IDX == OBJ_MAX_LINE - 1) begin
                     if (OBJ_NB == 0 | OBJ_NB == OBJ_MAX_LINE) begin
                        OBJ_IDX <= OBJ_NB;
                        SP2C <= SP2C_DONE;
                     end else begin
                        OBJ_IDX <= {6{1'b0}};
                        OBJ_VISINFO_ADDR_RD <= {6{1'b0}};
                     end
                  end else
                     if (OBJ_NB == OBJ_IDX + 1) begin
                        OBJ_IDX <= OBJ_NB;
                        SP2C <= SP2C_DONE;
                     end else begin
                        OBJ_IDX <= OBJ_IDX + 1;
                        OBJ_VISINFO_ADDR_RD <= OBJ_IDX + 1;
                     end
               end
            
            default :		// SP2C_DONE
               begin
                  SP2_SEL <= 1'b0;
                  
                  if (SP2E_ACTIVATE)
                     SP2C <= SP2C_INIT;
               end
         endcase
   end
   
   //--------------------------------------------------------------
   // SPRITE ENGINE - PART THREE
   //--------------------------------------------------------------
   always @(posedge CLK)
   begin: xhdl5
      reg [1:0]        obj_vs_var;
      reg [1:0]        obj_hs_var;
      reg              obj_hf_var;
      reg              obj_vf_var;
      reg [8:0]        obj_x_var;
      reg [5:0]        obj_y_ofs_var;
      reg [10:0]       obj_pat_var;
      reg [3:0]        obj_color;
      
      if (RST_N == 1'b0) begin
         SP3_SEL <= 1'b0;
         SP3C <= SP3C_DONE;
         
         OBJ_DOT_OVERFLOW <= 1'b0;
         
         SCOL_SET <= 1'b0;
         SOVR_SET <= 1'b0;
      
      end else if (CE) begin
         
         SCOL_SET <= 1'b0;
         SOVR_SET <= 1'b0;
         
         case (SP3C)
            SP3C_INIT :
               begin
                  OBJ_NO <= {6{1'b0}};
                  OBJ_SPINFO_ADDR_RD <= {6{1'b0}};
                  OBJ_PIX <= {9{1'b0}};
                  OBJ_MASKED <= 1'b0;
                  OBJ_VALID_X <= OBJ_DOT_OVERFLOW;
                  OBJ_DOT_OVERFLOW <= 1'b0;
                  SP3C <= SP3C_NEXT;
               end
            
            SP3C_NEXT :
               begin
                  
                  OBJ_COLINFO_WE_SP3 <= 1'b0;
                  
                  SP3C <= SP3C_LOOP;
                  if (OBJ_NO == OBJ_IDX)
                     SP3C <= SP3C_DONE;
                  
                  obj_vs_var = OBJ_SPINFO_Q[7:6];
                  OBJ_VS <= obj_vs_var;
                  obj_hs_var = OBJ_SPINFO_Q[9:8];
                  OBJ_HS <= obj_hs_var;
                  obj_x_var = OBJ_SPINFO_Q[18:10];
                  if (LSM == 2'b11) begin
                     obj_pat_var = {OBJ_SPINFO_Q[28:19], 1'b0};
                     obj_y_ofs_var = OBJ_SPINFO_Q[5:0];
                  end else begin
                     obj_pat_var = OBJ_SPINFO_Q[29:19];
                     obj_y_ofs_var = {1'b0, OBJ_SPINFO_Q[4:0]};
                  end
                  obj_hf_var = OBJ_SPINFO_Q[30];
                  OBJ_HF <= obj_hf_var;
                  obj_vf_var = OBJ_SPINFO_Q[31];
                  OBJ_PAL <= OBJ_SPINFO_Q[33:32];
                  OBJ_PRI <= OBJ_SPINFO_Q[34];
                  
                  OBJ_SPINFO_ADDR_RD <= OBJ_NO + 1;
                  OBJ_NO <= OBJ_NO + 1;
                  
                  // sprite masking algorithm as implemented by gens-ii
                  if (obj_x_var == 9'b000000000 & OBJ_VALID_X)
                     OBJ_MASKED <= 1'b1;
                  
                  if (obj_x_var != 9'b000000000)
                     OBJ_VALID_X <= 1'b1;
                  
                  OBJ_X_OFS <= 5'b00000;
                  if (obj_hf_var)
                     case (obj_hs_var)
                        2'b00 :		// 8 pixels
                           OBJ_X_OFS <= 5'b00111;
                        2'b01 :		// 16 pixels
                           OBJ_X_OFS <= 5'b01111;
                        2'b11 :		// 32 pixels
                           OBJ_X_OFS <= 5'b11111;
                        default :		// 24 pixels
                           OBJ_X_OFS <= 5'b10111;
                     endcase
                  
                  if (LSM == 2'b11 & obj_vf_var)
                     case (obj_vs_var)
                        2'b00 :		// 2*8 pixels
                           obj_y_ofs_var = {2'b00, (~(obj_y_ofs_var[3:0]))};
                        2'b01 :		// 2*16 pixels
                           obj_y_ofs_var = {1'b0, (~(obj_y_ofs_var[4:0]))};
                        2'b11 :		// 2*32 pixels
                           obj_y_ofs_var = (~(obj_y_ofs_var[5:0]));
                        default :		// 2*24 pixels
                           obj_y_ofs_var = 6'b101111 - obj_y_ofs_var;		// 47-obj_y_ofs
                     endcase
                  
                  if (LSM != 2'b11 & obj_vf_var)
                     case (obj_vs_var)
                        2'b00 :		// 8 pixels
                           obj_y_ofs_var = {3'b000, (~(obj_y_ofs_var[2:0]))};
                        2'b01 :		// 16 pixels
                           obj_y_ofs_var = {2'b00, (~(obj_y_ofs_var[3:0]))};
                        2'b11 :		// 32 pixels
                           obj_y_ofs_var = {1'b0, (~(obj_y_ofs_var[4:0]))};
                        default :		// 24 pixels
                           obj_y_ofs_var = 6'b010111 - obj_y_ofs_var[4:0];
                     endcase
                  
                  OBJ_POS <= obj_x_var - 9'b010000000;
                  OBJ_TILEBASE <= ({obj_pat_var, 4'b0000}) + ({3'b000, obj_y_ofs_var, 1'b0});
               end
            
            // loop over all tiles of the sprite
            SP3C_LOOP :
               begin
                  OBJ_COLINFO_WE_SP3 <= 1'b0;
                  OBJ_COLINFO_ADDR_RD_SP3 <= OBJ_POS;
                  
                  if (LSM == 2'b11)
                     case (OBJ_VS)
                        2'b00 :		// 2*8 pixels
                           SP3_VRAM_ADDR <= OBJ_TILEBASE + ({OBJ_X_OFS[4:3], 5'b00000});
                        2'b01 :		// 2*16 pixels
                           SP3_VRAM_ADDR <= OBJ_TILEBASE + ({OBJ_X_OFS[4:3], 6'b000000});
                        2'b11 :		// 2*32 pixels
                           SP3_VRAM_ADDR <= OBJ_TILEBASE + ({OBJ_X_OFS[4:3], 7'b0000000});
                        default :		// 2*24 pixels
                           case (OBJ_X_OFS[4:3])
                              2'b00 :
                                 SP3_VRAM_ADDR <= OBJ_TILEBASE;
                              2'b01 :
                                 SP3_VRAM_ADDR <= OBJ_TILEBASE + 9'b001100000;
                              2'b11 :
                                 SP3_VRAM_ADDR <= OBJ_TILEBASE + 9'b100100000;
                              default :
                                 SP3_VRAM_ADDR <= OBJ_TILEBASE + 9'b011000000;
                           endcase
                     endcase
                  else
                     case (OBJ_VS)
                        2'b00 :		// 8 pixels
                           SP3_VRAM_ADDR <= OBJ_TILEBASE + ({OBJ_X_OFS[4:3], 4'b0000});
                        2'b01 :		// 16 pixels
                           SP3_VRAM_ADDR <= OBJ_TILEBASE + ({OBJ_X_OFS[4:3], 5'b00000});
                        2'b11 :		// 32 pixels
                           SP3_VRAM_ADDR <= OBJ_TILEBASE + ({OBJ_X_OFS[4:3], 6'b000000});
                        default :		// 24 pixels
                           case (OBJ_X_OFS[4:3])
                              2'b00 :
                                 SP3_VRAM_ADDR <= OBJ_TILEBASE;
                              2'b01 :
                                 SP3_VRAM_ADDR <= OBJ_TILEBASE + 8'b00110000;
                              2'b11 :
                                 SP3_VRAM_ADDR <= OBJ_TILEBASE + 8'b10010000;
                              default :
                                 SP3_VRAM_ADDR <= OBJ_TILEBASE + 8'b01100000;
                           endcase
                     endcase
                  
                  SP3_SEL <= 1'b1;
                  SP3C <= SP3C_TILE_RD;
               end
            
            SP3C_TILE_RD :
               if (SP3_VRAM32_ACK) begin
                  SP3_SEL <= 1'b0;
                  SP3C <= SP3C_PLOT;
               end 
            
            // loop over all sprite pixels on the current line
            SP3C_PLOT :
               begin
                  case (OBJ_X_OFS[2:0])
                     3'b100 :
                        obj_color = SP3_VRAM32_DO[31:28];
                     3'b101 :
                        obj_color = SP3_VRAM32_DO[27:24];
                     3'b110 :
                        obj_color = SP3_VRAM32_DO[23:20];
                     3'b111 :
                        obj_color = SP3_VRAM32_DO[19:16];
                     3'b000 :
                        obj_color = SP3_VRAM32_DO[15:12];
                     3'b001 :
                        obj_color = SP3_VRAM32_DO[11:8];
                     3'b010 :
                        obj_color = SP3_VRAM32_DO[7:4];
                     3'b011 :
                        obj_color = SP3_VRAM32_DO[3:0];
                     default :
                        ;
                  endcase
                  
                  OBJ_COLINFO_WE_SP3 <= 1'b0;
                  if (OBJ_POS < 320) begin
                     if (OBJ_COLINFO_Q_A[3:0] == 4'b0000) begin
                        if (OBJ_MASKED == 1'b0) begin
                           OBJ_COLINFO_WE_SP3 <= 1'b1;
                           OBJ_COLINFO_ADDR_WR_SP3 <= OBJ_POS;
                           OBJ_COLINFO_D_SP3 <= {OBJ_PRI, OBJ_PAL, obj_color};
                        end 
                     end else
                        if (obj_color != 4'b0000)
                           SCOL_SET <= 1'b1;
                  end 
                  
                  OBJ_POS <= OBJ_POS + 1;
                  OBJ_PIX <= OBJ_PIX + 1;
                  OBJ_COLINFO_ADDR_RD_SP3 <= OBJ_POS + 1;
                  if (OBJ_HF) begin
                     if (OBJ_X_OFS == 5'b00000)
                        SP3C <= SP3C_NEXT;
                     else begin
                        OBJ_X_OFS <= OBJ_X_OFS - 1;
                        if (OBJ_X_OFS[2:0] == 3'b000)
                           SP3C <= SP3C_LOOP;		// fetch the next tile
                        else
                           SP3C <= SP3C_PLOT;
                     end
                  end else
                     if ((OBJ_X_OFS == 5'b00111 & OBJ_HS == 2'b00) | (OBJ_X_OFS == 5'b01111 & OBJ_HS == 2'b01) | (OBJ_X_OFS == 5'b11111 & OBJ_HS == 2'b11) | (OBJ_X_OFS == 5'b10111 & OBJ_HS == 2'b10))
                        SP3C <= SP3C_NEXT;
                     else begin
                        OBJ_X_OFS <= OBJ_X_OFS + 1;
                        if (OBJ_X_OFS[2:0] == 3'b111)
                           SP3C <= SP3C_LOOP;		// fetch the next tile
                        else
                           SP3C <= SP3C_PLOT;
                     end
                  
                  // limit total sprite pixels per line
                  if ((OBJ_PIX == H_DISP_WIDTH & OBJ_LIMIT_HIGH_EN == 1'b0) | (OBJ_PIX == H_TOTAL_WIDTH & OBJ_LIMIT_HIGH_EN)) begin
                     OBJ_DOT_OVERFLOW <= 1'b1;
                     SP3C <= SP3C_DONE;
                     SOVR_SET <= 1'b1;
                  end 
               end
            
            default :		// SP3C_DONE
               begin
                  SP3_SEL <= 1'b0;
                  
                  OBJ_COLINFO_WE_SP3 <= 1'b0;
                  OBJ_COLINFO_ADDR_WR_SP3 <= {9{1'b0}};
                  OBJ_COLINFO_ADDR_RD_SP3 <= {9{1'b0}};
                  
                  OBJ_SPINFO_ADDR_RD <= {6{1'b0}};
                  
                  if (SP3E_ACTIVATE)
                     SP3C <= SP3C_INIT;
               end
         endcase
      end 
   end
   
   //--------------------------------------------------------------
   // VIDEO COUNTING
   //--------------------------------------------------------------
   assign H_DISP_START  = (H40) ? H_DISP_START_H40  : H_DISP_START_H32;
   assign H_DISP_WIDTH  = (H40) ? H_DISP_WIDTH_H40  : H_DISP_WIDTH_H32;
   assign H_TOTAL_WIDTH = (H40) ? H_TOTAL_WIDTH_H40 : H_TOTAL_WIDTH_H32;
   assign H_INT_POS     = (H40) ? H_INT_H40         : H_INT_H32;
   assign HSYNC_START   = (H40) ? HSYNC_START_H40   : HSYNC_START_H32;
   assign HSYNC_END     = (H40) ? HSYNC_END_H40     : HSYNC_END_H32;
   assign HBLANK_START  = (H40) ? HBLANK_START_H40  : HBLANK_START_H32;
   assign HBLANK_END    = (H40) ? HBLANK_END_H40    : HBLANK_END_H32;
   assign HSCROLL_READ  = (H40) ? HSCROLL_READ_H40  : HSCROLL_READ_H32;
   assign VSYNC_HSTART  = (H40) ? VSYNC_HSTART_H40  : VSYNC_HSTART_H32;
   assign VSYNC_START   = (V30 & PAL) ? VSYNC_START_PAL_V30 : 
                          (V30 == 1'b0 & PAL) ? VSYNC_START_PAL_V28 : 
                          (V30 & PAL == 1'b0) ? VSYNC_START_NTSC_V30 : 
                          VSYNC_START_NTSC_V28;
   assign VBORDER_START = (V30 & PAL) ? VBORDER_START_PAL_V30 : 
                          (V30 == 1'b0 & PAL) ? VBORDER_START_PAL_V28 : 
                          (V30 & PAL == 1'b0) ? VBORDER_START_NTSC_V30 : 
                          VBORDER_START_NTSC_V28;
   assign VBORDER_END   = (V30 & PAL) ? VBORDER_END_PAL_V30 : 
                          (V30 == 1'b0 & PAL) ? VBORDER_END_PAL_V28 : 
                          (V30 & PAL == 1'b0) ? VBORDER_END_NTSC_V30 : 
                          VBORDER_END_NTSC_V28;
   assign V_DISP_START  = (V30) ? V_DISP_START_V30 : 
                          (PAL) ? V_DISP_START_PAL_V28 : 
                          V_DISP_START_NTSC_V28;
   assign V_DISP_HEIGHT = (V30) ? V_DISP_HEIGHT_V30 : V_DISP_HEIGHT_V28;
   assign V_TOTAL_HEIGHT = (PAL) ? PAL_LINES : NTSC_LINES;
   assign V_INT_POS     = (V30) ? V_INT_V30 : V_INT_V28;
   
   // COUNTERS AND INTERRUPTS
   assign Y = HV_VCNT[7:0];
   assign BG_Y = (LSM == 2'b11) ? {Y, FIELD} : HV_VCNT;
   assign PRE_Y = (LSM == 2'b11) ? {(Y + 8'd1), FIELD} : HV_VCNT + 1;
   
   assign HV_VCNT_EXT = (LSM == 2'b11) ? {Y, FIELD_LATCH} : HV_VCNT;
   assign HV8 = (LSM == 2'b11) ? HV_VCNT_EXT[8] : HV_VCNT_EXT[0];
   
   // refresh slots during disabled display - H40 - 6 slots, H32 - 5 slots
   // still not sure: usable slots at line -1, border and blanking area
   assign REFRESH_SLOT = ((H40 & HV_HCNT != 500 & HV_HCNT != 52 & HV_HCNT != 118 & HV_HCNT != 180 & HV_HCNT != 244 & HV_HCNT != 308) 
                        | (H40 == 1'b0 & HV_HCNT != 486 & HV_HCNT != 38 & HV_HCNT != 102 & HV_HCNT != 166 & HV_HCNT != 230)) ? 1'b0 : 
                         1'b1;
   
   always @(posedge CLK)
      if (RST_N == 1'b0) begin
         FIELD <= 1'b0;
         
         HV_PIXDIV <= {4{1'b0}};
         HV_HCNT <= {9{1'b0}};
         // Start the VCounter after VSYNC,
         // thus various latches can be activated in VDPsim for the 1st frame
         HV_VCNT <= 9'b111100101;		// 485
         
         PRE_V_ACTIVE <= 1'b0;
         V_ACTIVE <= 1'b0;
         V_ACTIVE_DISP <= 1'b0;
         
         EXINT_PENDING_SET <= 1'b0;
         HINT_EN <= 1'b0;
         HINT_PENDING_SET <= 1'b0;
         VINT_TG68_PENDING_SET <= 1'b0;
         VINT_T80_SET <= 1'b0;
         VINT_T80_CLR <= 1'b0;
         
         M_HBL <= 1'b0;
         IN_HBL <= 1'b0;
         IN_VBL <= 1'b1;
         VBL_AREA <= 1'b1;
         
         FIFO_EN <= 1'b0;
         SLOT_EN <= 1'b0;
         REFRESH_EN <= 1'b0;
         
         SP1_EN <= 1'b0;
         SP2_EN <= 1'b0;
      
      end else if (CE) begin
         
         EXINT_PENDING_SET <= 1'b0;
         HINT_PENDING_SET <= 1'b0;
         VINT_TG68_PENDING_SET <= 1'b0;
         VINT_T80_SET <= 1'b0;
         VINT_T80_CLR <= 1'b0;
         FIFO_EN <= 1'b0;
         SLOT_EN <= 1'b0;
         REFRESH_EN <= 1'b0;
         
         SP1_EN <= 1'b0;
         SP2_EN <= 1'b0;
         BGA_MAPPING_EN <= 1'b0;
         //BGA_PATTERN_EN <= '0';
         BGB_MAPPING_EN <= 1'b0;
         //BGB_PATTERN_EN <= '0';
         
         OLD_HL <= HL;
         if (OLD_HL & HL == 1'b0) begin
            HV <= {HV_VCNT_EXT[7:1], HV8, HV_HCNT[8:1]};
            EXINT_PENDING_SET <= 1'b1;
         end 
         
         if (M3 == 1'b0)
            HV <= {HV_VCNT_EXT[7:1], HV8, HV_HCNT[8:1]};
         
         // H40 slow slots: 8aaaaaaa99aaaaaaa8aaaaaaa99aaaaaaa
         // 8, 10, 10, 10, 10, 10, 10, 10, 9, 9, 10, 10, 10, 10, 10, 10, 10, 8, 10, 10, 10, 10, 10, 10, 10, 9, 9, 10, 10, 10, 10, 10, 10, 10
         // 460                           468                               477                            485                            493
         
         HV_PIXDIV <= HV_PIXDIV + 1;
         //normal H40 - 28*10+4*9+388*8=3420 cycles
         //fast H40
         //normal H32
         if ((RS0 & H40 & ((HV_PIXDIV == 8 - 1 & (HV_HCNT <= 460 | HV_HCNT > 493 | HV_HCNT == 477)) | ((HV_PIXDIV == 9 - 1 & (HV_HCNT == 468 | HV_HCNT == 469 | HV_HCNT == 485 | HV_HCNT == 486))) | (HV_PIXDIV == 10 - 1))) | (RS0 == 1'b0 & H40 & HV_PIXDIV == 8 - 1) | (RS0 == 1'b0 & H40 == 1'b0 & HV_PIXDIV == 10 - 1) | (RS0 & H40 == 1'b0 & HV_PIXDIV == 8 - 1)) begin		//fast H32
            reg [8:0] tmph;      // only compare 9 digits
            tmph = H_DISP_START + H_TOTAL_WIDTH - 1;
            HV_PIXDIV <= {4{1'b0}};
            if (HV_HCNT == tmph)
               // counter reset, originally HSYNC begins here
               HV_HCNT <= H_DISP_START;
            else
               HV_HCNT <= HV_HCNT + 1;
            
            if (HV_HCNT == H_INT_POS) begin
               reg [8:0] tmpv;                // nand2mario: wraps around
               tmpv = V_DISP_START + V_TOTAL_HEIGHT - 1;  
               
               if ((HV_VCNT == tmpv) &        // VDISP_START is negative
                   (V30 == 1'b0 | PAL))		// NTSC with V30 will not reload the VCounter
                  // just after VSYNC
                  HV_VCNT <= V_DISP_START;
               else
                  HV_VCNT <= HV_VCNT + 1;
               
               if (HV_VCNT == {1'b1, 8'hFF})
                  // FIELD changes at VINT, but the HV_COUNTER reflects the current field from line 0-0
                  FIELD_LATCH <= FIELD;
               
               // HINT_EN effect is delayed by one line
               if (HV_VCNT == {1'b1, 8'hFE})
                  HINT_EN <= 1'b1;
               else if (HV_VCNT == V_DISP_HEIGHT - 1)
                  HINT_EN <= 1'b0;
               
               if (HINT_EN == 1'b0)
                  HINT_COUNT <= HIT;
               else
                  if (HINT_COUNT == 0) begin
                     HINT_PENDING_SET <= 1'b1;
                     HINT_COUNT <= HIT;
                  end else
                     HINT_COUNT <= HINT_COUNT - 1;
               
               if (HV_VCNT == {1'b1, 8'hFE})
                  PRE_V_ACTIVE <= 1'b1;
               else if (HV_VCNT == {1'b1, 8'hFF})
                  V_ACTIVE <= 1'b1;
               else if (HV_VCNT == V_DISP_HEIGHT - 2)
                  PRE_V_ACTIVE <= 1'b0;
               else if (HV_VCNT == V_DISP_HEIGHT - 1)
                  V_ACTIVE <= 1'b0;
            end 
            
            if (HV_HCNT == HBLANK_START) begin
               if (HV_VCNT == 0)
                  V_ACTIVE_DISP <= 1'b1;
               else if (HV_VCNT == V_DISP_HEIGHT)
                  V_ACTIVE_DISP <= 1'b0;
               
               if (HV_VCNT == VBORDER_START)
                  VBL_AREA <= 1'b0;
               if (HV_VCNT == VBORDER_END)
                  VBL_AREA <= 1'b1;
            end 
            
            if (HV_HCNT == H_INT_POS + 4) begin
               if (HV_VCNT == {1'b1, 8'hFF})
                  IN_VBL <= 1'b0;
               else if (HV_VCNT == V_DISP_HEIGHT)
                  IN_VBL <= 1'b1;
            end 
            
            if (HV_HCNT == HBLANK_END) begin		//active display
               IN_HBL <= 1'b0;
               M_HBL <= 1'b0;
            end 
            
            if (HV_HCNT == HBLANK_START)		// blanking
               IN_HBL <= 1'b1;
            
            if (HV_HCNT == HBLANK_START - 3)
               M_HBL <= 1'b1;
            
            if (HV_HCNT == 0) begin
               if (HV_VCNT == V_INT_POS) begin
                  FIELD <= (~FIELD);
                  VINT_TG68_PENDING_SET <= 1'b1;
                  VINT_T80_SET <= 1'b1;
                  VINT_T80_WAIT <= 12'h975;		//2422 MCLK
               end 
            end 
            
            // VRAM Access slot enables
            if (IN_VBL | DE == 1'b0) begin
               if (REFRESH_SLOT == 1'b0)		// skip refresh slots
                  FIFO_EN <= (~HV_HCNT[0]);
            end else
               if ((HV_HCNT[3:0] == 4'b0100 & HV_HCNT[5:4] != 2'b11 & HV_HCNT < H_DISP_WIDTH) | 
                   (H40 & (HV_HCNT == 322 | HV_HCNT == 324 | HV_HCNT == 464)) | 
                   (H40 == 1'b0 & (HV_HCNT == 290 | HV_HCNT == 486 | HV_HCNT == 258 | HV_HCNT == 260)))
                  FIFO_EN <= 1'b1;
            
            SP1_EN <= 1'b1;		//SP1 Engine checks one sprite/pixel
            
            case (HV_HCNT[3:0])
               4'b0010 :
                  BGA_MAPPING_EN <= 1'b1;
               4'b0100 :		// external or refresh
                  ;
               //when "0110" => BGA_PATTERN_EN <= '1';
               //when "1000" => BGA_PATTERN_EN <= '1';
               4'b1010 :
                  BGB_MAPPING_EN <= 1'b1;
               4'b1100 :
                  SP2_EN <= 1'b1;
               //when "1110" => BGB_PATTERN_EN <= '1';
               4'b0000 :
                  //BGB_PATTERN_EN <= '1';
                  if (OBJ_LIMIT_HIGH_EN)
                     SP2_EN <= 1'b1;		// Update SP2 twice as often when sprite limit is increased
               default :
                  ;
            endcase
            
            SLOT_EN <= (~HV_HCNT[0]);
            if ((IN_VBL | DE == 1'b0) & REFRESH_SLOT)
               REFRESH_EN <= 1'b1;
         end 
         
         if (VINT_T80_WAIT == 0) begin
            if (VINT_T80_FF)
               VINT_T80_CLR <= 1'b1;
         end else
            VINT_T80_WAIT <= VINT_T80_WAIT - 1;
      end 
   
   // TIMING MANAGEMENT
   // Background generation runs during active display.
   // It starts with reading the horizontal scroll values from the VRAM
   assign BGEN_ACTIVATE = (V_ACTIVE & HV_HCNT == HSCROLL_READ + 8) ? 1'b1 : 1'b0;
   
   // Stage 1 - runs after the vcounter incremented
   // Carefully choosing the starting position avoids the
   // "Your emulator suxx" in Titan I demo
   assign SP1E_ACTIVATE = (PRE_V_ACTIVE & HV_HCNT == H_INT_POS + 1) ? 1'b1 : 1'b0;
   // Stage 2 - runs in the active area
   assign SP2E_ACTIVATE = (PRE_V_ACTIVE & HV_HCNT == 0) ? 1'b1 : 1'b0;
   // Stage 3 runs 3 slots after the background rendering ends
   assign SP3E_ACTIVATE = (PRE_V_ACTIVE & HV_HCNT == H_DISP_WIDTH + 5) ? 1'b1 : 1'b0;
      
   assign OBJ_COLINFO_D_REND = {7{1'b0}};

   always @(posedge CLK)
   begin
      reg [8:0]        x;

      if (CE) 
      if (VBL_AREA == 1'b0)
         // As displaying and sprite rendering (part 3) overlap,
         // copy and clear the sprite buffer a bit sooner.
         // also apply DE for the sprite layer here and 
         // clear the colinfo buffer after rendering
         //
         // A smaller buffer would be enough for the second copy, but
         // it still uses only 1 BRAM block, and makes the logic simpler
         //
         case (HV_PIXDIV)
            4'b0000 :
               begin
                  x = HV_HCNT;
                  OBJ_COLINFO_ADDR_RD_REND <= x;
                  OBJ_COLINFO_ADDR_WR_REND <= x;
                  OBJ_COLINFO2_ADDR_WR <= x;
                  OBJ_COLINFO_WE_REND <= 1'b0;
               end
            4'b0010 :
               begin
                  OBJ_COLINFO2_WE <= 1'b1;
                  if (DE)
                     OBJ_COLINFO2_D <= OBJ_COLINFO_Q_A;
                  else
                     OBJ_COLINFO2_D <= {1'b0, BGCOL};
                  OBJ_COLINFO_WE_REND <= 1'b1;
               end
            
            4'b0011 :
               begin
                  OBJ_COLINFO2_WE <= 1'b0;
                  OBJ_COLINFO_WE_REND <= 1'b0;
               end
            default :
               ;
         endcase
   end
   
   // PIXEL COUNTER AND OUTPUT
   always @(posedge CLK)
   begin
      reg [5:0]        col;
      reg [5:0]        cold;
      reg [8:0]        x;
         
   if (CE) begin
      if (IN_HBL | VBL_AREA) begin
         BGB_COLINFO_ADDR_B <= {9{1'b0}};
         BGA_COLINFO_ADDR_B <= {9{1'b0}};
         if (HV_PIXDIV == 4'b0101) begin
            FF_R <= {4{1'b0}};
            FF_G <= {4{1'b0}};
            FF_B <= {4{1'b0}};
         end 
      end else
         case (HV_PIXDIV)
            4'b0000 :
               begin
                  x = HV_HCNT - HBLANK_END - HBORDER_LEFT;
                  BGB_COLINFO_ADDR_B <= x;
                  BGA_COLINFO_ADDR_B <= x;
                  OBJ_COLINFO2_ADDR_RD <= x;
               end
            
            4'b0010 :
               if (SHI & BGA_COLINFO_Q_B[6] == 1'b0 & BGB_COLINFO_Q_B[6] == 1'b0)
                  //if all layers are normal priority, then shadowed
                  PIX_MODE <= PIX_SHADOW;
               else
                  PIX_MODE <= PIX_NORMAL;
            
            4'b0011 :
               begin
                  if (SHI & (OBJ_COLINFO2_Q[6] | ((BGA_COLINFO_Q_B[6] == 1'b0 | BGA_COLINFO_Q_B[3:0] == 4'b0000) & (BGB_COLINFO_Q_B[6] == 1'b0 | BGB_COLINFO_Q_B[3:0] == 4'b0000)))) begin
                     //sprite is visible
                     if (OBJ_COLINFO2_Q[5:0] == 6'b111110) begin
                        //if sprite is palette 3/color 14 increase intensity
                        if (PIX_MODE == PIX_SHADOW)
                           PIX_MODE <= PIX_NORMAL;
                        else
                           PIX_MODE <= PIX_HIGHLIGHT;
                     end else if (OBJ_COLINFO2_Q[5:0] == 6'b111111)
                        // if sprite is visible and palette 3/color 15, decrease intensity
                        PIX_MODE <= PIX_SHADOW;
                     else if ((OBJ_COLINFO2_Q[6] & OBJ_COLINFO2_Q[3:0] != 4'b0000) | OBJ_COLINFO2_Q[3:0] == 4'b1110)
                        //sprite color 14 or high prio always shows up normal
                        PIX_MODE <= PIX_NORMAL;
                  end 
                  
                  if (OBJ_COLINFO2_Q[3:0] != 4'b0000 & OBJ_COLINFO2_Q[6] & (SHI == 1'b0 | OBJ_COLINFO2_Q[5:1] != 5'b11111) & SPR_EN)
                     col = OBJ_COLINFO2_Q[5:0];
                  else if (BGA_COLINFO_Q_B[3:0] != 4'b0000 & BGA_COLINFO_Q_B[6] & BGA_EN)
                     col = BGA_COLINFO_Q_B[5:0];
                  else if (BGB_COLINFO_Q_B[3:0] != 4'b0000 & BGB_COLINFO_Q_B[6] & BGB_EN)
                     col = BGB_COLINFO_Q_B[5:0];
                  else if (OBJ_COLINFO2_Q[3:0] != 4'b0000 & (SHI == 1'b0 | OBJ_COLINFO2_Q[5:1] != 5'b11111) & SPR_EN)
                     col = OBJ_COLINFO2_Q[5:0];
                  else if (BGA_COLINFO_Q_B[3:0] != 4'b0000 & BGA_EN)
                     col = BGA_COLINFO_Q_B[5:0];
                  else if (BGB_COLINFO_Q_B[3:0] != 4'b0000 & BGB_EN)
                     col = BGB_COLINFO_Q_B[5:0];
                  else
                     col = BGCOL;
                  
                  if (OBJ_COLINFO2_Q[3:0] != 4'b0000 & OBJ_COLINFO2_Q[6] & (SHI == 1'b0 | OBJ_COLINFO2_Q[5:1] != 5'b11111))
                     TRANSP_DETECT <= 1'b0;
                  else if (BGA_COLINFO_Q_B[6] & BGA_COLINFO_Q_B[7])
                     TRANSP_DETECT <= 1'b1;
                  else if (BGB_COLINFO_Q_B[6] & BGB_COLINFO_Q_B[7])
                     TRANSP_DETECT <= 1'b1;
                  else if (OBJ_COLINFO2_Q[3:0] != 4'b0000 & (SHI == 1'b0 | OBJ_COLINFO2_Q[5:1] != 5'b11111))
                     TRANSP_DETECT <= 1'b0;
                  else
                     TRANSP_DETECT <= BGA_COLINFO_Q_B[7];
                  
                  case (DBG[8:7])
                     2'b00 :
                        cold = BGCOL;
                     2'b01 :
                        cold = OBJ_COLINFO2_Q[5:0];
                     2'b10 :
                        cold = BGA_COLINFO_Q_B[5:0];
                     2'b11 :
                        cold = BGB_COLINFO_Q_B[5:0];
                     default :
                        ;
                  endcase
                  
                  if (DBG[6])
                     col = cold;
                  else if (DBG[8:7] != 2'b00)
                     col = col & cold;
                  
                  if (x >= H_DISP_WIDTH | V_ACTIVE_DISP == 1'b0) begin
                     // border area
                     col = BGCOL;
                     PIX_MODE <= PIX_NORMAL;
                  end 
                  
                  CRAM_ADDR_B <= col;
               end
            
            4'b0101 :
               if ((x >= H_DISP_WIDTH | V_ACTIVE_DISP == 1'b0) & (BORDER_EN == 1'b0 | DBG[8:7] != 2'b00)) begin
                  // disabled border
                  FF_B <= {4{1'b0}};
                  FF_G <= {4{1'b0}};
                  FF_R <= {4{1'b0}};
               end else
                  case (PIX_MODE)
                     PIX_SHADOW :
                        begin
                           // half brightness
                           FF_B <= {1'b0, CRAM_DATA[8:6]};
                           FF_G <= {1'b0, CRAM_DATA[5:3]};
                           FF_R <= {1'b0, CRAM_DATA[2:0]};
                        end
                     
                     PIX_NORMAL :
                        begin
                           // normal brightness
                           FF_B <= {CRAM_DATA[8:6], 1'b0};
                           FF_G <= {CRAM_DATA[5:3], 1'b0};
                           FF_R <= {CRAM_DATA[2:0], 1'b0};
                        end
                     
                     PIX_HIGHLIGHT :
                        begin
                           // increased brightness
                           FF_B <= {1'b0, CRAM_DATA[8:6]} + 7;
                           FF_G <= {1'b0, CRAM_DATA[5:3]} + 7;
                           FF_R <= {1'b0, CRAM_DATA[2:0]} + 7;
                        end
                     default: ;
                  endcase
            
            default :
               ;
         endcase
   end
   end
   
   //--------------------------------------------------------------
   // VIDEO OUTPUT
   //--------------------------------------------------------------
   // SYNC
   always @(posedge CLK)
      if (RST_N == 1'b0) begin
         FF_VS <= 1'b1;
         FF_HS <= 1'b1;
      end else if (CE) begin
         
         // horizontal sync
         if (HV_HCNT == HSYNC_START)
            FF_HS <= 1'b0;
         else if (HV_HCNT == HSYNC_END)
            FF_HS <= 1'b1;
         
         if (HV_HCNT == VSYNC_HSTART) begin
            if (HV_VCNT == VSYNC_START)
               FF_VS <= 1'b0;
            if (HV_VCNT == VSYNC_START + VS_LINES - 1)
               FF_VS <= 1'b1;
         end 
      end 
   
   // VSync extension by half a line for interlace
   always @(posedge CLK)
   begin
      // 1710 = 1/2 * 3420 clock per line
      reg [10:0]       VS_START_DELAY;
      reg [10:0]       VS_END_DELAY;
      reg              VS_DELAY_ACTIVE;

      if (CE) begin
         if (FF_VS) begin
            // LSM(0) = 1 and FIELD = 0 right before vsync start -> start the delay
            if (HV_HCNT == VSYNC_HSTART & HV_VCNT == VSYNC_START & LSM[0] & FIELD == 1'b0) begin
               VS_START_DELAY = 1710;
               VS_DELAY_ACTIVE = 1'b1;
            end 
            
            // FF_VS already inactive, but end delay still != 0
            if (VS_END_DELAY != 0)
               VS_END_DELAY = VS_END_DELAY - 1;
            else
               VS <= 1'b1;
         end else begin
            
            // FF_VS = '0'
            if (VS_DELAY_ACTIVE) begin
               VS_END_DELAY = 1710;
               VS_DELAY_ACTIVE = 1'b0;
            end 
            
            // FF_VS active, but start delay still != 0
            if (VS_START_DELAY != 0)
               VS_START_DELAY = VS_START_DELAY - 1;
            else
               VS <= 1'b0;
         end
         HS <= FF_HS;
      end
   end
   
   assign R = FF_R;
   assign G = FF_G;
   assign B = FF_B;
   
   assign INTERLACE = LSM[1] & LSM[0];
   assign RESOLUTION = {V30, H40};
   
   assign V_DISP_HEIGHT_R = (V30_R) ? V_DISP_HEIGHT_V30 : V_DISP_HEIGHT_V28;
   
   always @(posedge CLK)
   begin
      reg              V30prev;

      CE_PIX <= 1'b0;
      if (CE && HV_PIXDIV == 4'b0101) begin
         
         if (HV_HCNT == VSYNC_HSTART & HV_VCNT == VSYNC_START)
            FIELD_OUT <= LSM[1] & LSM[0] & (~FIELD_LATCH);
         
         V30prev = V30prev & V30;
         if (HV_HCNT == H_INT_POS & HV_VCNT == 0) begin
            V30_R <= V30prev;
            V30prev = 1'b1;
         end 
         
         CE_PIX <= 1'b1;
         if (BORDER_EN == 1'b0) begin
            if ((HV_HCNT - HBLANK_END - HBORDER_LEFT) >= H_DISP_WIDTH)
               HBL <= 1'b1;
            else
               HBL <= 1'b0;
            
            if (HV_VCNT < V_DISP_HEIGHT_R)
               VBL <= 1'b0;
            else
               VBL <= 1'b1;
         end else begin
            HBL <= M_HBL;
            VBL <= VBL_AREA;
         end
      end 
   end
   
   //--------------------------------------------------------------
   // VIDEO DEBUG
   //--------------------------------------------------------------
   
   //--------------------------------------------------------------
   // CPU INTERFACE & DATA TRANSFER CONTROLLER
   //--------------------------------------------------------------
   assign DTACK_N = FF_DTACK_N;
   assign DO = FF_DO;
   
   assign VBUS_ADDR = FF_VBUS_ADDR;
   assign VBUS_SEL = FF_VBUS_SEL;
   
   assign FIFO_EMPTY = (FIFO_QUEUE == 0 & FIFO_PARTIAL == 1'b0) ? 1'b1 : 1'b0;
   assign FIFO_FULL = ((FIFO_QUEUE[2]) | (FIFO_QUEUE == 3 & FIFO_PARTIAL)) ? 1'b1 : 1'b0;
   
   always @(posedge CLK)
      if (RST_N == 1'b0) begin
         
         FF_DTACK_N <= 1'b1;
         FF_DO <= {16{1'b1}};
         
         PENDING <= 1'b0;
         CODE <= {6{1'b0}};
         
         DT_RD_SEL <= 1'b0;
         DT_RD_DTACK_N <= 1'b1;
         
         SOVR_CLR <= 1'b0;
         SCOL_CLR <= 1'b0;
         
         DBG <= {16{1'b0}};
         
         REG <= '{default: 8'b0};
         
         ADDR <= {17{1'b0}};
         
         DT_VRAM_SEL <= 1'b0;
         
         FIFO_RD_POS <= 2'b00;
         FIFO_WR_POS <= 2'b00;
         FIFO_QUEUE <= 3'b000;
         FIFO_PARTIAL <= 1'b0;
         
         REFRESH_FLAG <= 1'b0;
         
         FF_VBUS_ADDR <= {23{1'b0}};
         FF_VBUS_SEL <= 1'b0;
         
         DMA_FILL <= 1'b0;
         DMAF_SET_REQ <= 1'b0;
         DMA_COPY <= 1'b0;
         DMA_VBUS <= 1'b0;
         DMA_SOURCE <= {16{1'b0}};
         DMA_LENGTH <= {16{1'b0}};
         
         DTC <= DTC_IDLE;
         DMAC <= DMA_IDLE;
         
         BR_N <= 1'b1;
         BGACK_N_REG <= 1'b1;
      
      end else if (CE) begin
         
         if (DT_RD_SEL == 1'b0)
            DT_RD_DTACK_N <= 1'b1;
         
         if (SLOT_EN) begin
            if (FIFO_DELAY[0] != 2'b00)
               FIFO_DELAY[0] <= FIFO_DELAY[0] - 1;
            if (FIFO_DELAY[1] != 2'b00)
               FIFO_DELAY[1] <= FIFO_DELAY[1] - 1;
            if (FIFO_DELAY[2] != 2'b00)
               FIFO_DELAY[2] <= FIFO_DELAY[2] - 1;
            if (FIFO_DELAY[3] != 2'b00)
               FIFO_DELAY[3] <= FIFO_DELAY[3] - 1;
         end 
         
         // Extend CRAM write enable for CRAM dots
         if (CE_PIX)
            CRAM_WE_A <= 1'b0;
         
         SOVR_CLR <= 1'b0;
         SCOL_CLR <= 1'b0;
         
         if (SEL == 1'b0)
            FF_DTACK_N <= 1'b1;
         else if (SEL & FF_DTACK_N) begin
            if (RNW == 1'b0) begin		// Write
               if (A[4:2] == 3'b000) begin
                  // Data Port
                  PENDING <= 1'b0;
                  
                  if (FIFO_FULL == 1'b0 & DTC != DTC_FIFO_RD & FF_DTACK_N) begin
                     FIFO_ADDR[FIFO_WR_POS] <= ADDR;
                     FIFO_DATA[FIFO_WR_POS] <= DI;
                     FIFO_CODE[FIFO_WR_POS] <= CODE[3:0];
                     FIFO_DELAY[FIFO_WR_POS] <= 2'b00;		// should be delayed, too? (no, according to Zsenilla by RSE demo)
                     FIFO_WR_POS <= FIFO_WR_POS + 1;
                     FIFO_QUEUE <= FIFO_QUEUE + 1;
                     ADDR <= ADDR + ADDR_STEP;
                     FF_DTACK_N <= 1'b0;
                  end 
               
               end else if (A[4:2] == 3'b001) begin
                  // Control Port
                  if (PENDING) begin
                     CODE[4:2] <= DI[6:4];
                     ADDR <= {DI[2:0], ADDR[13:0]};
                     
                     if (DMA) begin
                        CODE[5] <= DI[7];
                        if (DI[7]) begin
                           if (REG[23][7] == 1'b0) begin
                              DMA_VBUS <= 1'b1;
                              BR_N <= 1'b0;
                           end else
                              if (REG[23][6] == 1'b0)
                                 DMA_FILL <= 1'b1;
                              else
                                 DMA_COPY <= 1'b1;
                        end 
                     end 
                     FF_DTACK_N <= 1'b0;
                     PENDING <= 1'b0;
                  end else begin
                     CODE[1:0] <= DI[15:14];
                     if (DI[15:14] == 2'b10) begin
                        // Register Set
                        if (M5 | DI[12:8] <= 10)
                           // mask registers above 10 in Mode4
                           REG[(DI[12:8])] <= DI[7:0];
                        FF_DTACK_N <= 1'b0;
                     end else begin
                        // Address Set
                        ADDR[13:0] <= DI[13:0];
                        FF_DTACK_N <= 1'b0;
                        PENDING <= 1'b1;
                        CODE[5:4] <= 2'b00;		// attempt to fix lotus i
                     end
                  end
               // Note : Genesis Plus does address setting
               // even in Register Set mode. Normal ?
               end else if (A[4:2] == 3'b111) begin
                  DBG <= DI;
                  FF_DTACK_N <= 1'b0;
               end else if (A[4:3] == 2'b10)
                  // PSG
                  FF_DTACK_N <= 1'b0;
               else
                  // Unused (Lock-up)
                  FF_DTACK_N <= 1'b0;
            end else
               // Read
               if (A[4:2] == 3'b000) begin
                  PENDING <= 1'b0;
                  // Data Port
                  // CRAM Read
                  // VSRAM Read
                  // VRAM Read
                  if (CODE == 6'b001000 | CODE == 6'b000100 | CODE == 6'b000000 | CODE == 6'b001100) begin		// VRAM Read 8 bit
                     if (DT_RD_DTACK_N) begin
                        DT_RD_SEL <= 1'b1;
                        DT_RD_CODE <= CODE[3:0];
                     end else begin
                        DT_RD_SEL <= 1'b0;
                        FF_DO <= DT_RD_DATA;
                        FF_DTACK_N <= 1'b0;
                     end
                  end else
                     FF_DTACK_N <= 1'b0;
               end else if (A[4:2] == 3'b001) begin
                  // Control Port (Read Status Register)
                  PENDING <= 1'b0;
                  FF_DO <= STATUS;
                  SOVR_CLR <= 1'b1;
                  SCOL_CLR <= 1'b1;
                  FF_DTACK_N <= 1'b0;
               end else if (A[4:3] == 2'b01) begin
                  // HV Counter
                  FF_DO <= HV;
                  FF_DTACK_N <= 1'b0;
               end else if (A[4]) begin
                  // unused, PSG, DBG
                  FF_DO <= 16'hFFFF;
                  FF_DTACK_N <= 1'b0;
               end 
         end 
         
         if (SLOT_EN) begin
            if (REFRESH_EN & DMA_VBUS & CODE[3:0] != 4'b0001)
               // skip the slot after a refresh for DMA (except for VRAM write)
               REFRESH_FLAG <= 1'b1;
            else
               REFRESH_FLAG <= 1'b0;
         end 
         
         case (DTC)
            DTC_IDLE :
               begin
                  if (FIFO_EN)
                     FIFO_PARTIAL <= 1'b0;
                  
                  if (VRAM_SPEED == 1'b0 | (FIFO_EN & FIFO_PARTIAL == 1'b0 & REFRESH_FLAG == 1'b0)) begin
                     if (FIFO_EMPTY == 1'b0 & FIFO_DELAY[FIFO_RD_POS] == 0)
                        DTC <= DTC_FIFO_RD;
                     else if (DT_RD_SEL & DT_RD_DTACK_N)
                        case (DT_RD_CODE)
                           4'b1000 :		// CRAM Read
                              DTC <= DTC_CRAM_RD;
                           4'b0100 :		// VSRAM Read
                              DTC <= DTC_VSRAM_RD;
                           default :		// VRAM Read
                              DTC <= DTC_VRAM_RD1;
                        endcase
                  end 
               end
            
            DTC_FIFO_RD :
               begin
                  DT_WR_ADDR <= FIFO_ADDR[FIFO_RD_POS];
                  DT_WR_DATA <= FIFO_DATA[FIFO_RD_POS];
                  FIFO_RD_POS <= FIFO_RD_POS + 1;
                  FIFO_QUEUE <= FIFO_QUEUE - 1;
                  case (FIFO_CODE[FIFO_RD_POS])
                     4'b0011 :		// CRAM Write
                        DTC <= DTC_CRAM_WR;
                     4'b0101 :		// VSRAM Write
                        DTC <= DTC_VSRAM_WR;
                     4'b0001 :		// VRAM Write
                        begin
                           // nand2maro: this causes fifo to underflow
                           // if (M128 == 1'b0)
                           //    //skip next FIFO slot since we write 16 bit now instead of the original 8
                           //    FIFO_PARTIAL <= 1'b1;
                           DTC <= DTC_VRAM_WR1;
                        end
                     default :		//invalid target
                        DTC <= DTC_WR_END;
                  endcase
               end
            
            DTC_VRAM_WR1 :
               begin
                  DT_VRAM_SEL <= (~DT_VRAM_SEL);
                  DT_VRAM_RNW <= 1'b0;
                  DT_VRAM_ADDR <= DT_WR_ADDR[16:1];
                  DT_VRAM_UDS_N <= 1'b0;
                  DT_VRAM_LDS_N <= 1'b0;
                  if (DT_WR_ADDR[0] == 1'b0 | M128)
                     DT_VRAM_DI <= DT_WR_DATA;
                  else
                     DT_VRAM_DI <= {DT_WR_DATA[7:0], DT_WR_DATA[15:8]};
                  
                  DTC <= DTC_VRAM_WR2;
               end
                  
            DTC_VRAM_WR2 :
               if (early_ack_dt == 1'b0)
                  DTC <= DTC_WR_END;
            
            DTC_CRAM_WR :
               begin
                  CRAM_WE_A <= 1'b1;
                  CRAM_ADDR_A <= DT_WR_ADDR[6:1];
                  CRAM_D_A <= {DT_WR_DATA[11:9], DT_WR_DATA[7:5], DT_WR_DATA[3:1]};
                  DTC <= DTC_WR_END;
               end
            
            DTC_VSRAM_WR :
               begin
                  if (DT_WR_ADDR[6:1] < 40) begin
                     if (DT_WR_ADDR[1] == 1'b0) begin
                        VSRAM0_WE_A <= 1'b1;
                        VSRAM0_ADDR_A <= DT_WR_ADDR[6:2];
                        VSRAM0_D_A <= DT_WR_DATA[10:0];
                     end else begin
                        VSRAM1_WE_A <= 1'b1;
                        VSRAM1_ADDR_A <= DT_WR_ADDR[6:2];
                        VSRAM1_D_A <= DT_WR_DATA[10:0];
                     end
                  end 
                  DTC <= DTC_WR_END;
               end
            
            DTC_WR_END :
               begin
                  VSRAM0_WE_A <= 1'b0;
                  VSRAM1_WE_A <= 1'b0;
                  if (DMA_FILL)
                     DMAF_SET_REQ <= 1'b1;
                  DTC <= DTC_IDLE;
               end
            
            DTC_VRAM_RD1 :
               begin
                  DT_VRAM_SEL <= (~DT_VRAM_SEL);
                  DT_VRAM_ADDR <= {1'b0, ADDR[15:1]};
                  DT_VRAM_RNW <= 1'b1;
                  DT_VRAM_UDS_N <= 1'b0;
                  DT_VRAM_LDS_N <= 1'b0;
                  DTC <= DTC_VRAM_RD2;
               end
            
            DTC_VRAM_RD2 :
               if (early_ack_dt == 1'b0) begin
                  if (DT_RD_CODE == 4'b1100) begin
                     // VRAM 8 bit read - unused bits come from the next FIFO entry
                     if (ADDR[0] == 1'b0)
                        DT_RD_DATA <= {FIFO_DATA[FIFO_RD_POS][15:8], DT_VRAM_DO[7:0]};
                     else
                        DT_RD_DATA <= {FIFO_DATA[FIFO_RD_POS][15:8], DT_VRAM_DO[15:8]};
                  end else
                     DT_RD_DATA <= DT_VRAM_DO;
                  DT_RD_DTACK_N <= 1'b0;
                  ADDR <= ADDR + ADDR_STEP;
                  DTC <= DTC_IDLE;
               end 
            
            DTC_CRAM_RD :
               begin
                  CRAM_ADDR_A <= ADDR[6:1];
                  DTC <= DTC_CRAM_RD1;
               end
            
            DTC_CRAM_RD1 :
               // cram address is set up
               DTC <= DTC_CRAM_RD2;
            
            DTC_CRAM_RD2 :
               begin
                  DT_RD_DATA[11:9] <= CRAM_Q_A[8:6];
                  DT_RD_DATA[7:5] <= CRAM_Q_A[5:3];
                  DT_RD_DATA[3:1] <= CRAM_Q_A[2:0];
                  //unused bits come from the next FIFO entry
                  DT_RD_DATA[15:12] <= FIFO_DATA[FIFO_RD_POS][15:12];
                  DT_RD_DATA[8] <= FIFO_DATA[FIFO_RD_POS][8];
                  DT_RD_DATA[4] <= FIFO_DATA[FIFO_RD_POS][4];
                  DT_RD_DATA[0] <= FIFO_DATA[FIFO_RD_POS][0];
                  DT_RD_DTACK_N <= 1'b0;
                  ADDR <= ADDR + ADDR_STEP;
                  DTC <= DTC_IDLE;
               end
            
            DTC_VSRAM_RD :
               begin
                  VSRAM0_ADDR_A <= ADDR[6:2];
                  VSRAM1_ADDR_A <= ADDR[6:2];
                  DTC <= DTC_VSRAM_RD2;
               end
            
            DTC_VSRAM_RD2 :
               DTC <= DTC_VSRAM_RD3;
            
            DTC_VSRAM_RD3 :
               begin
                  if (ADDR[6:1] < 40) begin
                     if (ADDR[1] == 1'b0)
                        DT_RD_DATA <= {FIFO_DATA[FIFO_RD_POS][15:11], VSRAM0_Q_A};
                     else
                        DT_RD_DATA <= {FIFO_DATA[FIFO_RD_POS][15:11], VSRAM1_Q_A};
                  end else if (ADDR[1] == 1'b0)
                     DT_RD_DATA <= {FIFO_DATA[FIFO_RD_POS][15:11], BGA_VSRAM0_LATCH};
                  else
                     DT_RD_DATA <= {FIFO_DATA[FIFO_RD_POS][15:11], BGB_VSRAM1_LATCH};
                  DT_RD_DTACK_N <= 1'b0;
                  ADDR <= ADDR + ADDR_STEP;
                  DTC <= DTC_IDLE;
               end
            
            default :
               ;
         endcase
               
         //--------------------------------------------------------------
         // DMA ENGINE
         //--------------------------------------------------------------
         if (FIFO_EMPTY & DMA_FILL & DMAF_SET_REQ) begin
            if (CODE[3:0] == 4'b0011 | CODE[3:0] == 4'b0101)
               // CRAM, VSRAM fill gets its data from the next FIFO write position
               DT_DMAF_DATA <= FIFO_DATA[FIFO_WR_POS];
            else
               // VRAM Write
               DT_DMAF_DATA <= DT_WR_DATA;
            DMAF_SET_REQ <= 1'b0;
         end 
         
         case (DMAC)
            DMA_IDLE :
               if (DMA_VBUS)
                  DMAC <= DMA_VBUS_INIT;
               else if (DMA_FILL & DMAF_SET_REQ)
                  DMAC <= DMA_FILL_INIT;
               else if (DMA_COPY)
                  DMAC <= DMA_COPY_INIT;
            //--------------------------------------------------------------
            // DMA FILL
            //--------------------------------------------------------------
            
            DMA_FILL_INIT :
               begin
                  DMA_SOURCE <= {REG[22], REG[21]};
                  DMA_LENGTH <= {REG[20], REG[19]};
                  DMAC <= DMA_FILL_START;
               end
            
            DMA_FILL_START :
               if (FIFO_EMPTY & DTC == DTC_IDLE & DMAF_SET_REQ == 1'b0)
                  // suspend FILL if the FIFO is not empty
                  case (CODE[3:0])
                     4'b0011 :		// CRAM Write
                        DMAC <= DMA_FILL_CRAM;
                     4'b0101 :		// VSRAM Write
                        DMAC <= DMA_FILL_VSRAM;
                     4'b0001 :		// VRAM Write
                        DMAC <= DMA_FILL_WR;
                     default :		// invalid target
                        DMAC <= DMA_FILL_NEXT;
                  endcase
            
            DMA_FILL_CRAM :
               if (VRAM_SPEED == 1'b0 | FIFO_EN) begin
                  CRAM_WE_A <= 1'b1;
                  CRAM_ADDR_A <= ADDR[6:1];
                  CRAM_D_A <= {DT_DMAF_DATA[11:9], DT_DMAF_DATA[7:5], DT_DMAF_DATA[3:1]};
                  DMAC <= DMA_FILL_NEXT;
               end 
            
            DMA_FILL_VSRAM :
               if (VRAM_SPEED == 1'b0 | FIFO_EN) begin
                  if (ADDR[6:1] < 40) begin
                     if (ADDR[1] == 1'b0) begin
                        VSRAM0_WE_A <= 1'b1;
                        VSRAM0_ADDR_A <= ADDR[6:2];
                        VSRAM0_D_A <= DT_DMAF_DATA[10:0];
                     end else begin
                        VSRAM1_WE_A <= 1'b1;
                        VSRAM1_ADDR_A <= ADDR[6:2];
                        VSRAM1_D_A <= DT_DMAF_DATA[10:0];
                     end
                  end 
                  DMAC <= DMA_FILL_NEXT;
               end 
            
            DMA_FILL_WR :
               if (VRAM_SPEED == 1'b0 | FIFO_EN) begin
                  DT_VRAM_SEL <= (~DT_VRAM_SEL);
                  DT_VRAM_ADDR <= {1'b0, ADDR[15:1]};
                  DT_VRAM_RNW <= 1'b0;
                  DT_VRAM_DI <= {DT_DMAF_DATA[15:8], DT_DMAF_DATA[15:8]};
                  if (ADDR[0] == 1'b0) begin
                     DT_VRAM_UDS_N <= 1'b1;
                     DT_VRAM_LDS_N <= 1'b0;
                  end else begin
                     DT_VRAM_UDS_N <= 1'b0;
                     DT_VRAM_LDS_N <= 1'b1;
                  end
                  DMAC <= DMA_FILL_WR2;
               end 
                  
            DMA_FILL_WR2 :
               if (early_ack_dt == 1'b0)
                  DMAC <= DMA_FILL_NEXT;
            
            DMA_FILL_NEXT :
               begin
                  VSRAM0_WE_A <= 1'b0;
                  VSRAM1_WE_A <= 1'b0;
                  ADDR <= ADDR + ADDR_STEP;
                  DMA_SOURCE <= DMA_SOURCE + ADDR_STEP;
                  DMA_LENGTH <= DMA_LENGTH - 1;
                  DMAC <= DMA_FILL_LOOP;
               end
            
            DMA_FILL_LOOP :
               begin
                  REG[20] <= DMA_LENGTH[15:8];
                  REG[19] <= DMA_LENGTH[7:0];
                  REG[22] <= DMA_SOURCE[15:8];
                  REG[21] <= DMA_SOURCE[7:0];
                  if (DMA_LENGTH == 0) begin
                     DMA_FILL <= 1'b0;
                     DMAC <= DMA_IDLE;
                  end else
                     DMAC <= DMA_FILL_START;
               end
                     
            //--------------------------------------------------------------
            // DMA COPY
            //--------------------------------------------------------------
                     
            DMA_COPY_INIT :
               begin
                  DMA_LENGTH <= {REG[20], REG[19]};
                  DMA_SOURCE <= {REG[22], REG[21]};
                  DMAC <= DMA_COPY_RD;
               end
            
            DMA_COPY_RD :
               begin
                  DT_VRAM_SEL <= (~DT_VRAM_SEL);
                  DT_VRAM_ADDR <= {1'b0, DMA_SOURCE[15:1]};
                  DT_VRAM_RNW <= 1'b1;
                  DT_VRAM_UDS_N <= 1'b0;
                  DT_VRAM_LDS_N <= 1'b0;
                  DMAC <= DMA_COPY_RD2;
               end
            
            DMA_COPY_RD2 :
               if (early_ack_dt == 1'b0) begin
                  DMAC <= DMA_COPY_WR;
               end 
               
            DMA_COPY_WR :
               begin
                  DT_VRAM_SEL <= (~DT_VRAM_SEL);
                  DT_VRAM_ADDR <= {1'b0, ADDR[15:1]};
                  DT_VRAM_RNW <= 1'b0;
                  if (DMA_SOURCE[0] == 1'b0)
                     DT_VRAM_DI <= {DT_VRAM_DO[7:0], DT_VRAM_DO[7:0]};
                  else
                     DT_VRAM_DI <= {DT_VRAM_DO[15:8], DT_VRAM_DO[15:8]};
                  if (ADDR[0] == 1'b0) begin
                     DT_VRAM_UDS_N <= 1'b1;
                     DT_VRAM_LDS_N <= 1'b0;
                  end else begin
                     DT_VRAM_UDS_N <= 1'b0;
                     DT_VRAM_LDS_N <= 1'b1;
                  end
                  DMAC <= DMA_COPY_WR2;
               end
                     
            DMA_COPY_WR2 :
               if (early_ack_dt == 1'b0) begin
                  ADDR <= ADDR + ADDR_STEP;
                  DMA_LENGTH <= DMA_LENGTH - 1;
                  DMA_SOURCE <= DMA_SOURCE + 1;
                  DMAC <= DMA_COPY_LOOP;
               end 
            
            DMA_COPY_LOOP :
               begin
                  REG[20] <= DMA_LENGTH[15:8];
                  REG[19] <= DMA_LENGTH[7:0];
                  REG[22] <= DMA_SOURCE[15:8];
                  REG[21] <= DMA_SOURCE[7:0];
                  if (DMA_LENGTH == 0) begin
                     DMA_COPY <= 1'b0;
                     DMAC <= DMA_IDLE;
                  end else
                     DMAC <= DMA_COPY_RD;
               end
                                 
            //--------------------------------------------------------------
            // DMA VBUS
            //--------------------------------------------------------------
            
            DMA_VBUS_INIT :
               begin
                  DMA_LENGTH <= {REG[20], REG[19]};
                  DMA_SOURCE <= {REG[22], REG[21]};
                  DMA_VBUS_TIMER <= 2'b10;
                  DMAC <= DMA_VBUS_WAIT;
               end
            
            DMA_VBUS_WAIT :
               begin
                  if (BG_N == 1'b0) begin
                     BGACK_N_REG <= 1'b0;
                     BR_N <= 1'b1;
                  end 
                  if (SLOT_EN) begin
                     if (DMA_VBUS_TIMER == 0) begin
                        if (BGACK_N_REG == 1'b0) begin
                           DMAC <= DMA_VBUS_RD;
                           FF_VBUS_SEL <= 1'b1;
                           FF_VBUS_ADDR <= {REG[23][6:0], DMA_SOURCE};
                        end 
                     end else
                        DMA_VBUS_TIMER <= DMA_VBUS_TIMER - 1;
                  end 
               end
            
            DMA_VBUS_RD :
               if (VBUS_DTACK_N == 1'b0 | FF_VBUS_SEL == 1'b0) begin
                  FF_VBUS_SEL <= 1'b0;
                  if (FF_VBUS_SEL)
                     DT_DMAV_DATA <= VBUS_DATA;
                  if (FIFO_FULL == 1'b0 & DTC != DTC_FIFO_RD) begin
                     FIFO_ADDR[FIFO_WR_POS] <= ADDR;
                     if (FF_VBUS_SEL)
                        FIFO_DATA[FIFO_WR_POS] <= VBUS_DATA;
                     else
                        FIFO_DATA[FIFO_WR_POS] <= DT_DMAV_DATA;
                     FIFO_CODE[FIFO_WR_POS] <= CODE[3:0];
                     FIFO_DELAY[FIFO_WR_POS] <= 2'b10;
                     FIFO_WR_POS <= FIFO_WR_POS + 1;
                     FIFO_QUEUE <= FIFO_QUEUE + 1;
                     ADDR <= ADDR + ADDR_STEP;
                     
                     DMA_LENGTH <= DMA_LENGTH - 1;
                     DMA_SOURCE <= DMA_SOURCE + 1;
                     DMAC <= DMA_VBUS_LOOP;
                  end 
               end 
            
            DMA_VBUS_LOOP :
               begin
                  REG[20] <= DMA_LENGTH[15:8];
                  REG[19] <= DMA_LENGTH[7:0];
                  REG[22] <= DMA_SOURCE[15:8];
                  REG[21] <= DMA_SOURCE[7:0];
                  if (DMA_LENGTH == 0) begin
                     DMA_VBUS_TIMER <= 2'b01;
                     DMAC <= DMA_VBUS_END;
                  end else if (SLOT_EN) begin
                     FF_VBUS_SEL <= 1'b1;
                     FF_VBUS_ADDR <= {REG[23][6:0], DMA_SOURCE};
                     DMAC <= DMA_VBUS_RD;
                  end 
               end
               
            DMA_VBUS_END :
               if (SLOT_EN) begin
                  DMA_VBUS_TIMER <= DMA_VBUS_TIMER - 1;
                  if (DMA_VBUS_TIMER == 0) begin
                     DMA_VBUS <= 1'b0;
                     BGACK_N_REG <= 1'b1;
                     DMAC <= DMA_IDLE;
                  end 
               end 

            default :
               ;
         endcase
      end 
                           
   //--------------------------------------------------------------
   // INTERRUPTS AND VARIOUS LATCHES
   //--------------------------------------------------------------
   
   // HINT PENDING
   always @(posedge CLK)
      if (RST_N == 1'b0) begin
         EXINT_PENDING <= 1'b0;
         HINT_PENDING <= 1'b0;
         VINT_TG68_PENDING <= 1'b0;
      end else if (CE) begin
         INTACK_D <= INTACK;
         //acknowledge interrupts serially
         if (INTACK_D == 1'b0 & INTACK) begin
            if (VINT_TG68_FF)
               VINT_TG68_PENDING <= 1'b0;
            else if (HINT_FF)
               HINT_PENDING <= 1'b0;
            else if (EXINT_FF)
               EXINT_PENDING <= 1'b0;
         end 
         if (EXINT_PENDING_SET)
            EXINT_PENDING <= 1'b1;
         if (HINT_PENDING_SET)
            HINT_PENDING <= 1'b1;
         if (VINT_TG68_PENDING_SET)
            VINT_TG68_PENDING <= 1'b1;
      end 
   
   // EXINT
   assign EXINT = EXINT_FF;
   
   always @(posedge CLK)
      if (RST_N == 1'b0)
         EXINT_FF <= 1'b0;
      else if (CE) begin
         if (EXINT_PENDING & IE2)
            EXINT_FF <= 1'b1;
         else
            EXINT_FF <= 1'b0;
      end 
   
   // HINT
   assign HINT = HINT_FF;
   
   always @(posedge CLK)
      if (RST_N == 1'b0)
         HINT_FF <= 1'b0;
      else if (CE) begin
         if (HINT_PENDING & IE1)
            HINT_FF <= 1'b1;
         else
            HINT_FF <= 1'b0;
      end 
   
   // VINT - TG68
   assign VINT_TG68 = VINT_TG68_FF;
   
   always @(posedge CLK)
      if (RST_N == 1'b0)
         VINT_TG68_FF <= 1'b0;
      else if (CE) begin
         if (VINT_TG68_PENDING & IE0)
            VINT_TG68_FF <= 1'b1;
         else
            VINT_TG68_FF <= 1'b0;
      end 
   
   // VINT - T80
   assign VINT_T80 = VINT_T80_FF;
   
   always @(posedge CLK)
      if (RST_N == 1'b0)
         VINT_T80_FF <= 1'b0;
      else if (CE) begin
         if (VINT_T80_SET)
            VINT_T80_FF <= 1'b1;
         else if (VINT_T80_CLR)
            VINT_T80_FF <= 1'b0;
      end 
   
   // Sprite Collision
   always @(posedge CLK)
      if (RST_N == 1'b0)
         SCOL <= 1'b0;
      else if (CE) begin
         if (SCOL_SET)
            SCOL <= 1'b1;
         else if (SCOL_CLR)
            SCOL <= 1'b0;
      end 
   
   // Sprite Overflow
   always @(posedge CLK)
      if (RST_N == 1'b0)
         SOVR <= 1'b0;
      else if (CE) begin
         if (SOVR_SET)
            SOVR <= 1'b1;
         else if (SOVR_CLR)
            SOVR <= 1'b0;
      end 
                                    
endmodule

