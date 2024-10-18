//------------------------------------------------------------------------------
// ****
// T80(c) core. Attempt to finish all undocumented features and provide
//              accurate timings.
// Version 350.
// Copyright (c) 2018 Sorgelig
//  Test passed: ZEXDOC, ZEXALL, Z80Full(*), Z80memptr
//  (*) Currently only SCF and CCF instructions aren't passed X/Y flags check as
//      correct implementation is still unclear.
//
// ****
// T80(b) core. In an effort to merge and maintain bug fixes ....
//
// Ver 301 parity flag is just parity for 8080, also overflow for Z80, by Sean Riddle
// Ver 300 started tidyup
// MikeJ March 2005
// Latest version from www.fpgaarcade.com (original www.opencores.org)
//
// ****
// Z80 compatible microprocessor core
//
// Version : 0247
// Copyright (c) 2001-2002 Daniel Wallner (jesus@opencores.org)
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
//      http://www.opencores.org/cvsweb.shtml/t80/
//
// Limitations :
//
// File history :
//
//      0214 : Fixed mostly flags, only the block instructions now fail the zex regression test
//      0238 : Fixed zero flag for 16 bit SBC and ADC
//      0240 : Added GB operations
//      0242 : Cleanup
//      0247 : Cleanup
//

module T80_ALU(
   input             Arith16,
   input             Z16,
   input      [15:0] WZ,
   input      [1:0]  XY_State,
   input      [3:0]  ALU_Op,
   input      [5:0]  IR,
   input      [1:0]  ISet,
   input      [7:0]  BusA,
   input      [7:0]  BusB,
   input      [7:0]  F_In,
   output reg [7:0]  Q,
   output reg [7:0]  F_Out
);

   parameter    Mode = 0;
   parameter    Flag_C = 0;
   parameter    Flag_N = 1;
   parameter    Flag_P = 2;
   parameter    Flag_X = 3;
   parameter    Flag_H = 4;
   parameter    Flag_Y = 5;
   parameter    Flag_Z = 6;
   parameter    Flag_S = 7;
   
  function [4:0] AddSub4;
    input [3:0] A;
    input [3:0] B;
    input Sub;
    input Carry_In;
    begin
      AddSub4 = { 1'b0, A } + { 1'b0, (Sub)?~B:B } + {4'h0,Carry_In};
    end
  endfunction // AddSub4
  
  function [3:0] AddSub3;
    input [2:0] A;
    input [2:0] B;
    input Sub;
    input Carry_In;
    begin
      AddSub3 = { 1'b0, A } + { 1'b0, (Sub)?~B:B } + {3'h0,Carry_In};
    end
  endfunction // AddSub4

  function [1:0] AddSub1;
    input A;
    input B;
    input Sub;
    input Carry_In;
    begin
      AddSub1 = { 1'b0, A } + { 1'b0, (Sub)?~B:B } + {1'h0,Carry_In};
    end
  endfunction // AddSub4
   
   // AddSub variables (temporary signals)
   wire         UseCarry;
   wire         Carry7_v;
   reg          Overflow_v;
   wire         HalfCarry_v;
   wire         Carry_v;
   wire [7:0]   Q_v;
   
   wire [7:0]   BitMask;
   
   assign BitMask = (IR[5:3] == 3'b000) ? 8'b00000001 : 
                    (IR[5:3] == 3'b001) ? 8'b00000010 : 
                    (IR[5:3] == 3'b010) ? 8'b00000100 : 
                    (IR[5:3] == 3'b011) ? 8'b00001000 : 
                    (IR[5:3] == 3'b100) ? 8'b00010000 : 
                    (IR[5:3] == 3'b101) ? 8'b00100000 : 
                    (IR[5:3] == 3'b110) ? 8'b01000000 : 
                    8'b10000000;
   
   assign UseCarry = (~ALU_Op[2]) & ALU_Op[0];
   assign { HalfCarry_v, Q_v[3:0] } = AddSub4(BusA[3:0], BusB[3:0], ALU_Op[1], ALU_Op[1] ^ (UseCarry && F_In[Flag_C]) );
   assign { Carry7_v, Q_v[6:4]  } = AddSub3(BusA[6:4], BusB[6:4], ALU_Op[1], HalfCarry_v);
   assign { Carry_v, Q_v[7] } = AddSub1(BusA[7], BusB[7], ALU_Op[1], Carry7_v);
   
   // bug fix - parity flag is just parity for 8080, also overflow for Z80
   always @(Carry_v or Carry7_v or Q_v)
      if (Mode == 2)
         Overflow_v <= (~(Q_v[0] ^ Q_v[1] ^ Q_v[2] ^ Q_v[3] ^ Q_v[4] ^ Q_v[5] ^ Q_v[6] ^ Q_v[7]));
      else
         Overflow_v <= Carry_v ^ Carry7_v;
   
   
   always @(Arith16 or ALU_Op or F_In or BusA or BusB or IR or Q_v or Carry_v or HalfCarry_v or Overflow_v or BitMask or ISet or Z16 or WZ or XY_State)
   begin
      reg [7:0]    Q_t;
      reg [8:0]    DAA_Q;

      Q_t = 8'bxxxxxxxx;
      F_Out <= F_In;
      DAA_Q = 9'bxxxxxxxxx;
      case (ALU_Op)
         4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100, 4'b0101, 4'b0110, 4'b0111 :
            begin
               F_Out[Flag_N] <= 1'b0;
               F_Out[Flag_C] <= 1'b0;
               case (ALU_Op[2:0])
                  3'b000, 3'b001 :		// ADD, ADC
                     begin
                        Q_t = Q_v;
                        F_Out[Flag_C] <= Carry_v;
                        F_Out[Flag_H] <= HalfCarry_v;
                        F_Out[Flag_P] <= Overflow_v;
                     end
                  3'b010, 3'b011, 3'b111 :		// SUB, SBC, CP
                     begin
                        Q_t = Q_v;
                        F_Out[Flag_N] <= 1'b1;
                        F_Out[Flag_C] <= (~Carry_v);
                        F_Out[Flag_H] <= (~HalfCarry_v);
                        F_Out[Flag_P] <= Overflow_v;
                     end
                  3'b100 :		// AND
                     begin
                        Q_t[7:0] = BusA & BusB;
                        F_Out[Flag_H] <= 1'b1;
                     end
                  3'b101 :		// XOR
                     begin
                        Q_t[7:0] = BusA ^ BusB;
                        F_Out[Flag_H] <= 1'b0;
                     end
                  default :		// OR "110"
                     begin
                        Q_t[7:0] = BusA | BusB;
                        F_Out[Flag_H] <= 1'b0;
                     end
               endcase
               if (ALU_Op[2:0] == 3'b111) begin		// CP
                  F_Out[Flag_X] <= BusB[3];
                  F_Out[Flag_Y] <= BusB[5];
               end else begin
                  F_Out[Flag_X] <= Q_t[3];
                  F_Out[Flag_Y] <= Q_t[5];
               end
               if (Q_t[7:0] == 8'b00000000) begin
                  F_Out[Flag_Z] <= 1'b1;
                  if (Z16)
                     F_Out[Flag_Z] <= F_In[Flag_Z];		// 16 bit ADC,SBC
               end else
                  F_Out[Flag_Z] <= 1'b0;
               F_Out[Flag_S] <= Q_t[7];
               case (ALU_Op[2:0])
                  3'b000, 3'b001, 3'b010, 3'b011, 3'b111 :		// ADD, ADC, SUB, SBC, CP
                     ;
                  default :
                     F_Out[Flag_P] <= ~(Q_t[0] ^ Q_t[1] ^ Q_t[2] ^ Q_t[3] ^ 
                                        Q_t[4] ^ Q_t[5] ^ Q_t[6] ^ Q_t[7]);
               endcase
               if (Arith16) begin
                  F_Out[Flag_S] <= F_In[Flag_S];
                  F_Out[Flag_Z] <= F_In[Flag_Z];
                  F_Out[Flag_P] <= F_In[Flag_P];
               end 
            end
         4'b1100 :
            begin
               // DAA
               F_Out[Flag_H] <= F_In[Flag_H];
               F_Out[Flag_C] <= F_In[Flag_C];
               DAA_Q[7:0] = BusA;
               DAA_Q[8] = 1'b0;
               if (F_In[Flag_N] == 1'b0) begin
                  // After addition
                  // Alow > 9 or H = 1
                  if (DAA_Q[3:0] > 9 | F_In[Flag_H]) begin
                     if (DAA_Q[3:0] > 9)
                        F_Out[Flag_H] <= 1'b1;
                     else
                        F_Out[Flag_H] <= 1'b0;
                     DAA_Q = DAA_Q + 6;
                  end 
                  // new Ahigh > 9 or C = 1
                  if (DAA_Q[8:4] > 9 | F_In[Flag_C])
                     DAA_Q = DAA_Q + 96;		// 0x60
               end else begin
                  // After subtraction
                  if (DAA_Q[3:0] > 9 | F_In[Flag_H]) begin
                     if (DAA_Q[3:0] > 5)
                        F_Out[Flag_H] <= 1'b0;
                     DAA_Q[7:0] = DAA_Q[7:0] - 6;
                  end 
                  if (BusA > 153 | F_In[Flag_C])
                     DAA_Q = DAA_Q - 352;		// 0x160
               end
               F_Out[Flag_X] <= DAA_Q[3];
               F_Out[Flag_Y] <= DAA_Q[5];
               F_Out[Flag_C] <= F_In[Flag_C] | DAA_Q[8];
               Q_t = (DAA_Q[7:0]);
               if (DAA_Q[7:0] == 8'b00000000)
                  F_Out[Flag_Z] <= 1'b1;
               else
                  F_Out[Flag_Z] <= 1'b0;
               F_Out[Flag_S] <= DAA_Q[7];
               F_Out[Flag_P] <= ~(DAA_Q[0] ^ DAA_Q[1] ^ DAA_Q[2] ^ DAA_Q[3] ^ 
                                  DAA_Q[4] ^ DAA_Q[5] ^ DAA_Q[6] ^ DAA_Q[7]);
            end

         4'b1101, 4'b1110 :
            begin
               // RLD, RRD
               Q_t[7:4] = BusA[7:4];
               if (ALU_Op[0])
                  Q_t[3:0] = BusB[7:4];
               else
                  Q_t[3:0] = BusB[3:0];
               F_Out[Flag_H] <= 1'b0;
               F_Out[Flag_N] <= 1'b0;
               F_Out[Flag_X] <= Q_t[3];
               F_Out[Flag_Y] <= Q_t[5];
               if (Q_t[7:0] == 8'b00000000)
                  F_Out[Flag_Z] <= 1'b1;
               else
                  F_Out[Flag_Z] <= 1'b0;
               F_Out[Flag_S] <= Q_t[7];
               F_Out[Flag_P] <= (~(Q_t[0] ^ Q_t[1] ^ Q_t[2] ^ Q_t[3] ^ Q_t[4] ^ Q_t[5] ^ Q_t[6] ^ Q_t[7]));
            end

         4'b1001 :
            begin
               // BIT
               Q_t[7:0] = BusB & BitMask;
               F_Out[Flag_S] <= Q_t[7];
               if (Q_t[7:0] == 8'b00000000) begin
                  F_Out[Flag_Z] <= 1'b1;
                  F_Out[Flag_P] <= 1'b1;
               end else begin
                  F_Out[Flag_Z] <= 1'b0;
                  F_Out[Flag_P] <= 1'b0;
               end
               F_Out[Flag_H] <= 1'b1;
               F_Out[Flag_N] <= 1'b0;
               if (IR[2:0] == 3'b110 | XY_State != 2'b00) begin
                  F_Out[Flag_X] <= WZ[11];
                  F_Out[Flag_Y] <= WZ[13];
               end else begin
                  F_Out[Flag_X] <= BusB[3];
                  F_Out[Flag_Y] <= BusB[5];
               end
            end

         4'b1010 :
            // SET
            Q_t[7:0] = BusB | BitMask;

         4'b1011 :
            // RES
            Q_t[7:0] = BusB & (~BitMask);

         4'b1000 :
            begin
               // ROT
               case (IR[5:3])
                  3'b000 :		// RLC
                     begin
                        Q_t[7:1] = BusA[6:0];
                        Q_t[0] = BusA[7];
                        F_Out[Flag_C] <= BusA[7];
                     end
                  3'b010 :		// RL
                     begin
                        Q_t[7:1] = BusA[6:0];
                        Q_t[0] = F_In[Flag_C];
                        F_Out[Flag_C] <= BusA[7];
                     end
                  3'b001 :		// RRC
                     begin
                        Q_t[6:0] = BusA[7:1];
                        Q_t[7] = BusA[0];
                        F_Out[Flag_C] <= BusA[0];
                     end
                  3'b011 :		// RR
                     begin
                        Q_t[6:0] = BusA[7:1];
                        Q_t[7] = F_In[Flag_C];
                        F_Out[Flag_C] <= BusA[0];
                     end
                  3'b100 :		// SLA
                     begin
                        Q_t[7:1] = BusA[6:0];
                        Q_t[0] = 1'b0;
                        F_Out[Flag_C] <= BusA[7];
                     end
                  3'b110 :		// SLL (Undocumented) / SWAP
                     if (Mode == 3) begin
                        Q_t[7:4] = BusA[3:0];
                        Q_t[3:0] = BusA[7:4];
                        F_Out[Flag_C] <= 1'b0;
                     end else begin
                        Q_t[7:1] = BusA[6:0];
                        Q_t[0] = 1'b1;
                        F_Out[Flag_C] <= BusA[7];
                     end
                  3'b101 :		// SRA
                     begin
                        Q_t[6:0] = BusA[7:1];
                        Q_t[7] = BusA[7];
                        F_Out[Flag_C] <= BusA[0];
                     end
                  default :		// SRL
                     begin
                        Q_t[6:0] = BusA[7:1];
                        Q_t[7] = 1'b0;
                        F_Out[Flag_C] <= BusA[0];
                     end
               endcase
               F_Out[Flag_H] <= 1'b0;
               F_Out[Flag_N] <= 1'b0;
               F_Out[Flag_X] <= Q_t[3];
               F_Out[Flag_Y] <= Q_t[5];
               F_Out[Flag_S] <= Q_t[7];
               if (Q_t[7:0] == 8'b00000000)
                  F_Out[Flag_Z] <= 1'b1;
               else
                  F_Out[Flag_Z] <= 1'b0;
               F_Out[Flag_P] <= ~(Q_t[0] ^ Q_t[1] ^ Q_t[2] ^ Q_t[3] ^ 
                                  Q_t[4] ^ Q_t[5] ^ Q_t[6] ^ Q_t[7]);
               if (ISet == 2'b00) begin
                  F_Out[Flag_P] <= F_In[Flag_P];
                  F_Out[Flag_S] <= F_In[Flag_S];
                  F_Out[Flag_Z] <= F_In[Flag_Z];
               end 
            end
         default :
            ;
      endcase
      Q <= Q_t;
   end
   
endmodule
