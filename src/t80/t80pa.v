//
// Z80 compatible microprocessor core, preudo-asynchronous top level (by Sorgelig)
//
// Copyright (c) 2001-2002 Daniel Wallner (jesus@opencores.org)
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
//
// The latest version of this file can be found at:
//	http://www.opencores.org/cvsweb.shtml/t80/
//
// File history :
//
// v1.0: convert to preudo-asynchronous model with original Z80 timings.
//
// v2.0: rewritten for more precise timings.
//       support for both CEN_n and CEN_p set to 1. Effective clock will be CLK/2.
//
// v2.1: Output Address 0 during non-bus MCycle (fix ZX contention)
//
// v2.2: Interrupt acknowledge cycle has been corrected
//       WAIT_n is broken in T80.vhd. Simulate correct WAIT_n locally.
//
// v2.3: Output last used Address during non-bus MCycle seems more correct.
//

module T80pa(
   input          RESET_n,
   input          CLK,
   input          CEN_p,
   input          CEN_n,
   input          WAIT_n,
   input          INT_n,
   input          NMI_n,
   input          BUSRQ_n,
   output         M1_n,
   output reg     MREQ_n,
   output reg     IORQ_n,
   output reg     RD_n,
   output reg     WR_n,
   output         RFSH_n,
   output         HALT_n,
   output         BUSAK_n,
   input          OUT0,		// 0 => OUT(C),0, 1 => OUT(C),255
   output [15:0]  A,
   input [7:0]    DI,
   output [7:0]   DO,
   output [211:0] REG,		// IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
   input          DIRSet,
   input [211:0]  DIR 		// IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
);
   
   parameter      Mode = 0;		// 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB

   wire           IntCycle_n;
   reg [1:0]      IntCycleD_n;
   wire           IORQ;
   wire           NoRead;
   wire           Write;
   wire           BUSAK;
   reg [7:0]      DI_Reg;		// Input synchroniser
   wire [2:0]     MCycle;
   wire [2:0]     TState;
   reg            CEN_pol;
   wire [15:0]    A_int;
   reg [15:0]     A_last;
   
   assign A = (NoRead == 1'b0 | Write) ? A_int : A_last;
   
   assign BUSAK_n = BUSAK;
   
   // DInst: valid   at beginning of T3
   // DI:    latched at middle    of T3
   T80 #(.Mode(Mode), .IOWait(1)) u0(
      .CEN(CEN_p & (~CEN_pol)), .M1_n(M1_n), .IORQ(IORQ), .NoRead(NoRead), 
      .Write(Write), .RFSH_n(RFSH_n), .HALT_n(HALT_n), .WAIT_n(1'b1), 
      .INT_n(INT_n), .NMI_n(NMI_n), .RESET_n(RESET_n), .BUSRQ_n(BUSRQ_n), 
      .BUSAK_n(BUSAK), .CLK_n(CLK), .A(A_int), .DInst(DI), 
      .DI(DI_Reg), .DO(DO), .REG(REG), .MC(MCycle), .TS(TState), .out0(OUT0), 
      .IntCycle_n(IntCycle_n), .DIRSet(DIRSet), .DIR(DIR)
   );
      
   always @(posedge CLK)
       begin
         if (RESET_n == 1'b0) begin
            WR_n <= 1'b1;
            RD_n <= 1'b1;
            IORQ_n <= 1'b1;
            MREQ_n <= 1'b1;
            DI_Reg <= 8'b00000000;
            CEN_pol <= 1'b0;
         end else if (CEN_p & CEN_pol == 1'b0) begin
            CEN_pol <= 1'b1;
            if (MCycle == 3'b001) begin
               if (TState == 3'b010) begin
                  IORQ_n <= 1'b1;
                  MREQ_n <= 1'b1;
                  RD_n <= 1'b1;
               end 
            end else
               if (TState == 3'b001 & IORQ) begin
                  WR_n <= (~Write);
                  RD_n <= Write;
                  IORQ_n <= 1'b0;
               end 
         end else if (CEN_n & CEN_pol) begin
            if (TState == 3'b010)
               CEN_pol <= (~WAIT_n);
            else
               CEN_pol <= 1'b0;
            if (TState == 3'b011 & BUSAK)
               DI_Reg <= DI;
            if (MCycle == 3'b001) begin
               if (TState == 3'b001) begin
                  IntCycleD_n <= {IntCycleD_n[0], IntCycle_n};
                  RD_n <= (~IntCycle_n);
                  MREQ_n <= (~IntCycle_n);
                  IORQ_n <= IntCycleD_n[1];
                  A_last <= A_int;
               end 
               if (TState == 3'b011) begin
                  IntCycleD_n <= 2'b11;
                  RD_n <= 1'b1;
                  MREQ_n <= 1'b0;
               end 
               if (TState == 3'b100)
                  MREQ_n <= 1'b1;
            end else begin
               if (NoRead == 1'b0 & IORQ == 1'b0) begin
                  if (TState == 3'b001) begin
                     RD_n <= Write;
                     MREQ_n <= 1'b0;
                     A_last <= A_int;
                  end 
               end 
               if (TState == 3'b010)
                  WR_n <= (~Write);
               if (TState == 3'b011) begin
                  WR_n <= 1'b1;
                  RD_n <= 1'b1;
                  IORQ_n <= 1'b1;
                  MREQ_n <= 1'b1;
               end 
            end
         end 
      end 
   
endmodule
