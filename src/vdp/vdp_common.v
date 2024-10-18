// Copyright (c) 2010 Gregory Estrade (greg@torlus.com)
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

`ifndef vdp_common
`define vdp_common

localparam  VS_LINES = 4;

// Timing values from the Exodus emulator in HV_HCNT and HV_VCNT values

localparam  H_DISP_START_H32 = 466;		// -46
localparam  H_DISP_START_H40 = 458;		// -56

localparam  HBORDER_LEFT = 13;
localparam  HBORDER_RIGHT = 14;

localparam  H_DISP_WIDTH_H32 = 256;
localparam  H_DISP_WIDTH_H40 = 320;

localparam  HBLANK_END_H32 = 4;
localparam  HBLANK_END_H40 = 11;

localparam  HBLANK_START_H32 = HBLANK_END_H32 + HBORDER_LEFT + H_DISP_WIDTH_H32 + HBORDER_RIGHT;
localparam  HBLANK_START_H40 = HBLANK_END_H40 + HBORDER_LEFT + H_DISP_WIDTH_H40 + HBORDER_RIGHT;

localparam  H_TOTAL_WIDTH_H32 = 342;
localparam  H_TOTAL_WIDTH_H40 = 420;

// HSYNC moved a bit before the active area from the reference
// to provide enough back porch
localparam  HSYNC_START_H32 = H_DISP_START_H32 + 0;
localparam  HSYNC_START_H40 = H_DISP_START_H40 + 7;

localparam  HSYNC_END_H32 = H_DISP_START_H32 + 23;
localparam  HSYNC_END_H40 = H_DISP_START_H40 + 28;

localparam  VSYNC_HSTART_H32 = HSYNC_START_H32;
localparam  VSYNC_HSTART_H40 = HSYNC_START_H40;

localparam  H_INT_H32 = 265;
localparam  H_INT_H40 = 329;

localparam  V_DISP_START_PAL_V28 = 458;
localparam  V_DISP_START_NTSC_V28 = 485;	// -27;
localparam  V_DISP_START_V30 = 466;		    // -46

localparam  V_DISP_HEIGHT_V28 = 224;
localparam  V_DISP_HEIGHT_V30 = 240;

localparam  V_INT_V28 = 224;
localparam  V_INT_V30 = 240;

localparam  VSYNC_START_PAL_V28 = 458;
localparam  VSYNC_START_PAL_V30 = 466;
localparam  VSYNC_START_NTSC_V28 = 485;
localparam  VSYNC_START_NTSC_V30 = 466;

localparam  VBORDER_END_PAL_V28 = V_DISP_HEIGHT_V28 + 32;
localparam  VBORDER_END_PAL_V30 = V_DISP_HEIGHT_V30 + 24;
localparam  VBORDER_END_NTSC_V28 = V_DISP_HEIGHT_V28 + 8;
localparam  VBORDER_END_NTSC_V30 = V_DISP_HEIGHT_V30;

localparam  VBORDER_START_PAL_V28 = 480;
localparam  VBORDER_START_PAL_V30 = 482;
localparam  VBORDER_START_NTSC_V28 = 501;
localparam  VBORDER_START_NTSC_V30 = 493;

localparam  NTSC_LINES = 262;
localparam  PAL_LINES = 313;

localparam  HSCROLL_READ_H32 = 488;
localparam  HSCROLL_READ_H40 = 488;

localparam  OBJ_MAX_FRAME_H32 = 64;
localparam  OBJ_MAX_FRAME_H40 = 80;

localparam  OBJ_MAX_LINE_H32 = 16;
localparam  OBJ_MAX_LINE_H40 = 20;

localparam  OBJ_MAX_LINE_H32_HIGH = 32;
localparam  OBJ_MAX_LINE_H40_HIGH = 40;

`endif
