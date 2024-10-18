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
// Ver 303 add undocumented DDCB and FDCB opcodes by TobiFlex 20.04.2010
// Ver 301 parity flag is just parity for 8080, also overflow for Z80, by Sean Riddle
// Ver 300 started tidyup.
//
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
//      0208 : First complete release
//      0210 : Fixed wait and halt
//      0211 : Fixed Refresh addition and IM 1
//      0214 : Fixed mostly flags, only the block instructions now fail the zex regression test
//      0232 : Removed refresh address output for Mode > 1 and added DJNZ M1_n fix by Mike Johnson
//      0235 : Added clock enable and IM 2 fix by Mike Johnson
//      0237 : Changed 8080 I/O address output, added IntE output
//      0238 : Fixed (IX/IY+d) timing and 16 bit ADC and SBC zero flag
//      0240 : Added interrupt ack fix by Mike Johnson, changed (IX/IY+d) timing and changed flags in GB mode
//      0242 : Added I/O wait, fixed refresh address, moved some registers to RAM
//      0247 : Fixed bus req/ack cycle
//

module T80(
   input             RESET_n,
   input             CLK_n,
   input             CEN,
   input             WAIT_n,
   input             INT_n,
   input             NMI_n,
   input             BUSRQ_n,
   output reg        M1_n,
   output            IORQ,
   output            NoRead,
   output            Write,
   output reg        RFSH_n,
   output            HALT_n,
   output            BUSAK_n,
   output reg [15:0] A,
   input [7:0]       DInst,
   input [7:0]       DI,
   output reg [7:0]  DO,
   output [2:0]      MC,
   output [2:0]      TS,
   output            IntCycle_n,
   output            IntE,
   output            Stop,
   input             out0,		// 0 => OUT(C),0, 1 => OUT(C),255
   output [211:0]    REG,		// IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
   
   input             DIRSet,
   input [211:0]     DIR 		// IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
);

   parameter       Mode = 0;		// 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
   parameter       IOWait = 0;	// 0 => Single cycle I/O, 1 => Std I/O cycle
   parameter       Flag_C = 0;
   parameter       Flag_N = 1;
   parameter       Flag_P = 2;
   parameter       Flag_X = 3;
   parameter       Flag_H = 4;
   parameter       Flag_Y = 5;
   parameter       Flag_Z = 6;
   parameter       Flag_S = 7;
   
   parameter [2:0] aNone = 3'b111;
   parameter [2:0] aBC = 3'b000;
   parameter [2:0] aDE = 3'b001;
   parameter [2:0] aXY = 3'b010;
   parameter [2:0] aIOA = 3'b100;
   parameter [2:0] aSP = 3'b101;
   parameter [2:0] aZI = 3'b110;
   
   // Registers
   reg [7:0]       ACC;
   reg [7:0]       F;
   reg [7:0]       Ap;
   reg [7:0]       Fp;
   reg [7:0]       I;
   reg [7:0]       R;
   reg [15:0]       SP;
   reg [15:0]       PC;
   
   reg [7:0]       RegDIH;
   reg [7:0]       RegDIL;
   wire [15:0]     RegBusA;
   wire [15:0]     RegBusB;
   wire [15:0]     RegBusC;
   reg [2:0]       RegAddrA_r;
   wire [2:0]      RegAddrA;
   reg [2:0]       RegAddrB_r;
   wire [2:0]      RegAddrB;
   reg [2:0]       RegAddrC;
   reg             RegWEH;
   reg             RegWEL;
   reg             Alternate;
   
   // Help Registers
   reg [15:0]      WZ;		// MEMPTR register
   reg [7:0]       IR;		// Instruction register
   reg [1:0]       ISet;		// Instruction set selector
   reg [15:0]      RegBusA_r;
   
   wire [15:0]     ID16;
   wire [7:0]      Save_Mux;
   
   reg [2:0]       TState;
   reg [2:0]       MCycle;
   reg             IntE_FF1;
   reg             IntE_FF2;
   reg             Halt_FF;
   reg             BusReq_s;
   reg             BusAck;
   wire            ClkEn;
   reg             NMI_s;
   reg [1:0]       IStatus;
   
   wire [7:0]      DI_Reg;
   wire            T_Res;
   reg [1:0]       XY_State;
   reg [2:0]       Pre_XY_F_M;
   wire            NextIs_XY_Fetch;
   reg             XY_Ind;
   reg             No_BTR;
   reg             BTR_r;
   wire            Auto_Wait;
   reg             Auto_Wait_t1;
   reg             Auto_Wait_t2;
   reg             IncDecZ;
   
   // ALU signals
   reg [7:0]       BusB;
   reg [7:0]       BusA;
   wire [7:0]      ALU_Q;
   wire [7:0]      F_Out;
   
   // Registered micro code outputs
   reg [4:0]       Read_To_Reg_r;
   reg             Arith16_r;
   reg             Z16_r;
   reg [3:0]       ALU_Op_r;
   reg             Save_ALU_r;
   reg             PreserveC_r;
   reg [2:0]       MCycles;
   
   // Micro code outputs
   wire [2:0]      MCycles_d;
   wire [2:0]      TStates;
   reg             IntCycle;
   reg             NMICycle;
   wire            Inc_PC;
   wire            Inc_WZ;
   wire [3:0]      IncDec_16;
   wire [1:0]      Prefix;
   wire            Read_To_Acc;
   wire            Read_To_Reg;
   wire [3:0]      Set_BusB_To;
   wire [3:0]      Set_BusA_To;
   wire [3:0]      ALU_Op;
   wire            Save_ALU;
   wire            PreserveC;
   wire            Arith16;
   wire [2:0]      Set_Addr_To;
   wire            Jump;
   wire            JumpE;
   wire            JumpXY;
   wire            Call;
   wire            RstP;
   wire            LDZ;
   wire            LDW;
   wire            LDSPHL;
   wire            IORQ_i;
   wire [2:0]      Special_LD;
   wire            ExchangeDH;
   wire            ExchangeRp;
   wire            ExchangeAF;
   wire            ExchangeRS;
   wire            I_DJNZ;
   wire            I_CPL;
   wire            I_CCF;
   wire            I_SCF;
   wire            I_RETN;
   wire            I_BT;
   wire            I_BC;
   wire            I_BTR;
   wire            I_RLD;
   wire            I_RRD;
   reg             I_RXDD;
   wire            I_INRC;
   wire [1:0]      SetWZ;
   wire            SetDI;
   wire            SetEI;
   wire [1:0]      IMode;
   wire            Halt;
   wire            XYbit_undoc;
   wire [127:0]    DOR;
   
   assign REG = (Alternate == 1'b0) ? {IntE_FF2, IntE_FF1, IStatus, DOR, PC, SP, R, I, Fp, Ap, F, ACC} : 
                {IntE_FF2, IntE_FF1, IStatus, DOR[127:112], DOR[47:0], DOR[63:48], DOR[111:64], 
                 PC, SP, R, I, Fp, Ap, F, ACC};
   
   T80_MCode #(
      .Mode(Mode), .Flag_C(Flag_C), .Flag_N(Flag_N), .Flag_P(Flag_P), 
      .Flag_X(Flag_X), .Flag_H(Flag_H), .Flag_Y(Flag_Y), 
      .Flag_Z(Flag_Z), .Flag_S(Flag_S)
   ) mcode (
      .IR(IR), .ISet(ISet), .MCycle(MCycle), .F(F), 
      .NMICycle(NMICycle), .IntCycle(IntCycle), .XY_State(XY_State), 
      .MCycles(MCycles_d), .TStates(TStates), .Prefix(Prefix), 
      .Inc_PC(Inc_PC), .Inc_WZ(Inc_WZ), .IncDec_16(IncDec_16), 
      .Read_To_Acc(Read_To_Acc), .Read_To_Reg(Read_To_Reg), 
      .Set_BusB_To(Set_BusB_To), .Set_BusA_To(Set_BusA_To), .ALU_Op(ALU_Op), 
      .Save_ALU(Save_ALU), .PreserveC(PreserveC), .Arith16(Arith16), 
      .Set_Addr_To(Set_Addr_To), .IORQ(IORQ_i), .Jump(Jump), 
      .JumpE(JumpE), .JumpXY(JumpXY), .Call(Call), .RstP(RstP), .LDZ(LDZ), 
      .LDW(LDW), .LDSPHL(LDSPHL), .Special_LD(Special_LD), 
      .ExchangeDH(ExchangeDH), .ExchangeRp(ExchangeRp), .ExchangeAF(ExchangeAF), 
      .ExchangeRS(ExchangeRS), .I_DJNZ(I_DJNZ), .I_CPL(I_CPL), .I_CCF(I_CCF), 
      .I_SCF(I_SCF), .I_RETN(I_RETN), .I_BT(I_BT), .I_BC(I_BC), .I_BTR(I_BTR), 
      .I_RLD(I_RLD), .I_RRD(I_RRD), .I_INRC(I_INRC), .SetWZ(SetWZ), .SetDI(SetDI), 
      .SetEI(SetEI), .IMode(IMode), .Halt(Halt), .NoRead(NoRead), 
      .Write(Write), .XYbit_undoc(XYbit_undoc)
   );
   
   T80_ALU #(
      .Mode(Mode), .Flag_C(Flag_C), .Flag_N(Flag_N), .Flag_P(Flag_P), 
      .Flag_X(Flag_X), .Flag_H(Flag_H), .Flag_Y(Flag_Y), 
      .Flag_Z(Flag_Z), .Flag_S(Flag_S)
   ) alu (
      .Arith16(Arith16_r), .Z16(Z16_r), .WZ(WZ), .XY_State(XY_State), .ALU_Op(ALU_Op_r), 
      .IR(IR[5:0]), .ISet(ISet), .BusA(BusA), .BusB(BusB), .F_In(F), .Q(ALU_Q), .F_Out(F_Out)
   );
   
   assign ClkEn = CEN & (~BusAck);
   
   assign T_Res = (TState == TStates) ? 1'b1 : 1'b0;
   
   assign NextIs_XY_Fetch = (XY_State != 2'b00 & XY_Ind == 1'b0 & ((Set_Addr_To == aXY) | (MCycle == 3'b001 & IR == 8'b11001011) | (MCycle == 3'b001 & IR == 8'b00110110))) ? 1'b1 : 1'b0;
   
   assign Save_Mux = (ExchangeRp) ? BusB : 
                     (Save_ALU_r == 1'b0) ? DI_Reg : 
                     ALU_Q;
   
   always @(negedge RESET_n or posedge CLK_n)
   begin
      reg [7:0]       n;
      reg [8:0]       ioq;

      if (RESET_n == 1'b0) begin
         PC <= {16{1'b0}};		// Program Counter
         A <= {16{1'b0}};
         WZ <= {16{1'b0}};
         IR <= 8'b00000000;
         ISet <= 2'b00;
         XY_State <= 2'b00;
         IStatus <= 2'b00;
         MCycles <= 3'b000;
         DO <= 8'b00000000;
         
         ACC <= {8{1'b1}};
         F <= {8{1'b1}};
         Ap <= {8{1'b1}};
         Fp <= {8{1'b1}};
         I <= {8{1'b0}};
         R <= {8{1'b0}};
         SP <= {16{1'b1}};
         Alternate <= 1'b0;
         
         Read_To_Reg_r <= 5'b00000;
         Arith16_r <= 1'b0;
         BTR_r <= 1'b0;
         Z16_r <= 1'b0;
         ALU_Op_r <= 4'b0000;
         Save_ALU_r <= 1'b0;
         PreserveC_r <= 1'b0;
         XY_Ind <= 1'b0;
         I_RXDD <= 1'b0;
      
      end else begin
         
         if (DIRSet) begin
            ACC<= DIR[7:0];
            F  <= DIR[15:8];
            Ap <= DIR[23:16];
            Fp <= DIR[31:24];
            I  <= DIR[39:32];
            R  <= DIR[47:40];
            SP <= DIR[63:48];
            PC <= DIR[79:64];
            A  <= DIR[79:64];
            IStatus <= DIR[209:208];
         
         end else if (ClkEn) begin
            ALU_Op_r <= 4'b0000;
            Save_ALU_r <= 1'b0;
            Read_To_Reg_r <= 5'b00000;
            
            MCycles <= MCycles_d;
            
            if (IMode != 2'b11)
               IStatus <= IMode;
            
            Arith16_r <= Arith16;
            PreserveC_r <= PreserveC;
            if (ISet == 2'b10 & ALU_Op[2] == 1'b0 & ALU_Op[0] & MCycle == 3'b011)
               Z16_r <= 1'b1;
            else
               Z16_r <= 1'b0;
            
            if (MCycle == 3'b001 & TState[2] == 1'b0) begin
               // MCycle = 1 and TState = 1, 2, or 3
               
               if (TState == 2 & WAIT_n) begin
                  if (Mode < 2) begin
                     A[7:0] <= R;
                     A[15:8] <= I;
                     R[6:0] <= R[6:0] + 1;
                  end 
                  
                  if (Jump == 1'b0 & Call == 1'b0 & NMICycle == 1'b0 & IntCycle == 1'b0 & (~(Halt_FF | Halt)))
                     PC <= PC + 1;
                  
                  if (IntCycle & IStatus == 2'b01)
                     IR <= 8'b11111111;
                  else if (Halt_FF | (IntCycle & IStatus == 2'b10) | NMICycle)
                     IR <= 8'b00000000;
                  else
                     IR <= DInst;
                  
                  ISet <= 2'b00;
                  if (Prefix != 2'b00) begin
                     if (Prefix == 2'b11) begin
                        if (IR[5])
                           XY_State <= 2'b10;
                        else
                           XY_State <= 2'b01;
                     end else begin
                        if (Prefix == 2'b10) begin
                           XY_State <= 2'b00;
                           XY_Ind <= 1'b0;
                        end 
                        ISet <= Prefix;
                     end
                  end else begin
                     XY_State <= 2'b00;
                     XY_Ind <= 1'b0;
                  end
               end 
            end else begin
               
               // either (MCycle > 1) OR (MCycle = 1 AND TState > 3)
               
               if (MCycle == 3'b110) begin
                  XY_Ind <= 1'b1;
                  if (Prefix == 2'b01)
                     ISet <= 2'b01;
               end 
               
               if (T_Res) begin
                  BTR_r <= (I_BT | I_BC | I_BTR) & (~No_BTR);
                  if (Jump) begin
                     A[15:8] <= DI_Reg;
                     A[7:0] <= WZ[7:0];
                     PC[15:8] <= DI_Reg;
                     PC[7:0] <= (WZ[7:0]);
                  end else if (JumpXY) begin
                     A <= RegBusC;
                     PC <= RegBusC;
                  end else if (Call | RstP) begin
                     A <= WZ;
                     PC <= WZ;
                  end else if (MCycle == MCycles & NMICycle) begin
                     A <= 16'b0000000001100110;
                     PC <= 16'b0000000001100110;
                  end else if (MCycle == 3'b011 & IntCycle & IStatus == 2'b10) begin
                     A[15:8] <= I;
                     A[7:0] <= WZ[7:0];
                     PC[15:8] <= I;
                     PC[7:0] <= (WZ[7:0]);
                  end 
                  else
                     case (Set_Addr_To)
                        aXY :
                           if (XY_State == 2'b00)
                              A <= RegBusC;
                           else
                              if (NextIs_XY_Fetch)
                                 A <= PC;
                              else
                                 A <= WZ;
                        aIOA :
                           begin
                              if (Mode == 3)
                                 // Memory map I/O on GBZ80
                                 A[15:8] <= {16{1'b1}};
                              else if (Mode == 2)
                                 // Duplicate I/O address on 8080
                                 A[15:8] <= DI_Reg;
                              else
                                 A[15:8] <= ACC;
                              A[7:0] <= DI_Reg;
                              WZ <= ({ACC, DI_Reg}) + 1'b1;
                           end
                        aSP :
                           A <= SP;
                        aBC :
                           if (Mode == 3 & IORQ_i) begin
                              // Memory map I/O on GBZ80
                              A[15:8] <= {16{1'b1}};
                              A[7:0] <= RegBusC[7:0];
                           end else begin
                              A <= RegBusC;
                              if (SetWZ == 2'b01)
                                 WZ <= RegBusC + 1'b1;
                              if (SetWZ == 2'b10) begin
                                 WZ[7:0] <= RegBusC[7:0] + 1'b1;
                                 WZ[15:8] <= ACC;
                              end 
                           end
                        aDE :
                           begin
                              A <= RegBusC;
                              if (SetWZ == 2'b10) begin
                                 WZ[7:0] <= RegBusC[7:0] + 1'b1;
                                 WZ[15:8] <= ACC;
                              end 
                           end
                        aZI :
                           if (Inc_WZ)
                              A <= (WZ + 1);
                           else begin
                              A[15:8] <= DI_Reg;
                              A[7:0] <= WZ[7:0];
                              if (SetWZ == 2'b10) begin
                                 WZ[7:0] <= WZ[7:0] + 1'b1;
                                 WZ[15:8] <= ACC;
                              end 
                           end
                        default :
                           A <= PC;
                     endcase
                  
                  if (SetWZ == 2'b11)
                     WZ <= ID16;
                  
                  Save_ALU_r <= Save_ALU;
                  ALU_Op_r <= ALU_Op;
                  
                  if (I_CPL) begin
                     // CPL
                     ACC <= (~ACC);
                     F[Flag_Y] <= (~ACC[5]);
                     F[Flag_H] <= 1'b1;
                     F[Flag_X] <= (~ACC[3]);
                     F[Flag_N] <= 1'b1;
                  end 
                  if (I_CCF) begin
                     // CCF
                     F[Flag_C] <= (~F[Flag_C]);
                     F[Flag_Y] <= ACC[5];
                     F[Flag_H] <= F[Flag_C];
                     F[Flag_X] <= ACC[3];
                     F[Flag_N] <= 1'b0;
                  end 
                  if (I_SCF) begin
                     // SCF
                     F[Flag_C] <= 1'b1;
                     F[Flag_Y] <= ACC[5];
                     F[Flag_H] <= 1'b0;
                     F[Flag_X] <= ACC[3];
                     F[Flag_N] <= 1'b0;
                  end 
               end 
               
               if ((TState == 2 & I_BTR & IR[0]) | (TState == 1 & I_BTR & IR[0] == 1'b0)) begin
                  ioq = ({1'b0, DI_Reg}) + ({1'b0, (ID16[7:0])});
                  F[Flag_N] <= DI_Reg[7];
                  F[Flag_C] <= ioq[8];
                  F[Flag_H] <= ioq[8];
                  ioq = (ioq & 4'h7) ^ {9{({1'b0, BusA})}};
                  F[Flag_P] <= (~(ioq[0] ^ ioq[1] ^ ioq[2] ^ ioq[3] ^ ioq[4] ^ ioq[5] ^ ioq[6] ^ ioq[7]));
               end 
               
               if (TState == 2 & WAIT_n) begin
                  if (ISet == 2'b01 & MCycle == 3'b111)
                     IR <= DInst;
                  if (JumpE) begin
                     PC <= PC + {{8{DI_Reg[7]}}, DI_Reg};   // nand2mario: sign-extend offset DI_Reg
                     WZ <= PC + {{8{DI_Reg[7]}}, DI_Reg};
                  end else if (Inc_PC)
                     PC <= PC + 1;
                  if (BTR_r)
                     PC <= PC - 2;
                  if (RstP) begin
                     WZ <= {16{1'b0}};
                     WZ[5:3] <= IR[5:3];
                  end 
               end 
               if (TState == 3 & MCycle == 3'b110)
                  WZ <= RegBusC + {{8{DI_Reg[7]}}, DI_Reg};
               
               if (MCycle == 3'b011 & TState == 4 & No_BTR == 1'b0) begin
                  if (I_BT | I_BC)
                     WZ <= PC - 1'b1;
               end 
               
               if ((TState == 2 & WAIT_n) | (TState == 4 & MCycle == 3'b001)) begin
                  if (IncDec_16[2:0] == 3'b111) begin
                     if (IncDec_16[3])
                        SP <= SP - 1;
                     else
                        SP <= SP + 1;
                  end 
               end 
               
               if (LDSPHL)
                  SP <= RegBusC;
               if (ExchangeAF) begin
                  Ap <= ACC;
                  ACC <= Ap;
                  Fp <= F;
                  F <= Fp;
               end 
               if (ExchangeRS)
                  Alternate <= (~Alternate);
            end
            
            if (TState == 3) begin
               if (LDZ)
                  WZ[7:0] <= DI_Reg;
               if (LDW)
                  WZ[15:8] <= DI_Reg;
               
               if (Special_LD[2])
                  case (Special_LD[1:0])
                     2'b00 :
                        begin
                           ACC <= I;
                           F[Flag_P] <= IntE_FF2;
                           F[Flag_S] <= I[7];
                           
                           if (I == 8'h00)
                              F[Flag_Z] <= 1'b1;
                           else
                              F[Flag_Z] <= 1'b0;
                           
                           F[Flag_Y] <= I[5];
                           F[Flag_H] <= 1'b0;
                           F[Flag_X] <= I[3];
                           F[Flag_N] <= 1'b0;
                        end
                     
                     2'b01 :
                        begin
                           ACC <= R;
                           F[Flag_P] <= IntE_FF2;
                           F[Flag_S] <= R[7];
                           
                           if (R == 8'h00)
                              F[Flag_Z] <= 1'b1;
                           else
                              F[Flag_Z] <= 1'b0;
                           
                           F[Flag_Y] <= R[5];
                           F[Flag_H] <= 1'b0;
                           F[Flag_X] <= R[3];
                           F[Flag_N] <= 1'b0;
                        end
                     
                     2'b10 :
                        I <= ACC;
                     default :
                        R <= ACC;
                  endcase
            end 
            
            if ((I_DJNZ == 1'b0 & Save_ALU_r) | ALU_Op_r == 4'b1001) begin
               if (Mode == 3) begin
                  F[6] <= F_Out[6];
                  F[5] <= F_Out[5];
                  F[7] <= F_Out[7];
                  if (PreserveC_r == 1'b0)
                     F[4] <= F_Out[4];
               end else begin
                  F[7:1] <= F_Out[7:1];
                  if (PreserveC_r == 1'b0)
                     F[Flag_C] <= F_Out[0];
               end
            end 
            if (T_Res & I_INRC) begin
               F[Flag_H] <= 1'b0;
               F[Flag_N] <= 1'b0;
               F[Flag_X] <= DI_Reg[3];
               F[Flag_Y] <= DI_Reg[5];
               if (DI_Reg[7:0] == 8'b00000000)
                  F[Flag_Z] <= 1'b1;
               else
                  F[Flag_Z] <= 1'b0;
               F[Flag_S] <= DI_Reg[7];
               F[Flag_P] <= (~(DI_Reg[0] ^ DI_Reg[1] ^ DI_Reg[2] ^ DI_Reg[3] ^ DI_Reg[4] ^ 
                               DI_Reg[5] ^ DI_Reg[6] ^ DI_Reg[7]));
            end 
            
            if (TState == 1 & Auto_Wait_t1 == 1'b0) begin
               // Keep D0 from M3 for RLD/RRD (Sorgelig)
               I_RXDD <= I_RLD | I_RRD;
               if (I_RXDD == 1'b0)
                  DO <= BusB;
               if (I_RLD) begin
                  DO[3:0] <= BusA[3:0];
                  DO[7:4] <= BusB[3:0];
               end 
               if (I_RRD) begin
                  DO[3:0] <= BusB[7:4];
                  DO[7:4] <= BusA[3:0];
               end 
            end 
            
            if (T_Res) begin
               Read_To_Reg_r[3:0] <= Set_BusA_To;
               Read_To_Reg_r[4] <= Read_To_Reg;
               if (Read_To_Acc) begin
                  Read_To_Reg_r[3:0] <= 4'b0111;
                  Read_To_Reg_r[4] <= 1'b1;
               end 
            end 
            
            if (TState == 1 & I_BT) begin
               F[Flag_X] <= ALU_Q[3];
               F[Flag_Y] <= ALU_Q[1];
               F[Flag_H] <= 1'b0;
               F[Flag_N] <= 1'b0;
            end 
            if (TState == 1 & I_BC) begin
               n = ALU_Q - ({7'b0000000, F_Out[Flag_H]});
               F[Flag_X] <= n[3];
               F[Flag_Y] <= n[1];
            end 
            if (I_BC | I_BT)
               F[Flag_P] <= IncDecZ;
            
            if ((TState == 1 & Save_ALU_r == 1'b0 & Auto_Wait_t1 == 1'b0) | (Save_ALU_r & ALU_Op_r != 4'b0111)) begin
               case (Read_To_Reg_r)
                  5'b10111 :
                     ACC <= Save_Mux;
                  5'b10110 :
                     DO <= Save_Mux;
                  5'b11000 :
                     SP[7:0] <= Save_Mux;
                  5'b11001 :
                     SP[15:8] <= Save_Mux;
                  5'b11011 :
                     F <= Save_Mux;
                  default :
                     ;
               endcase
               if (XYbit_undoc)
                  DO <= ALU_Q;
            end 
         end 
      end 
   end
   
   //-------------------------------------------------------------------------
   //
   // BC('), DE('), HL('), IX and IY
   //
   //-------------------------------------------------------------------------
   always @(posedge CLK_n)
       begin
         if (ClkEn) begin
            // Bus A / Write
            RegAddrA_r <= {Alternate, Set_BusA_To[2:1]};
            if (XY_Ind == 1'b0 & XY_State != 2'b00 & Set_BusA_To[2:1] == 2'b10)
               RegAddrA_r <= {XY_State[1], 2'b11};
            
            // Bus B
            RegAddrB_r <= {Alternate, Set_BusB_To[2:1]};
            if (XY_Ind == 1'b0 & XY_State != 2'b00 & Set_BusB_To[2:1] == 2'b10)
               RegAddrB_r <= {XY_State[1], 2'b11};
            
            // Address from register
            RegAddrC <= {Alternate, Set_Addr_To[1:0]};
            // Jump (HL), LD SP,HL
            if (JumpXY | LDSPHL)
               RegAddrC <= {Alternate, 2'b10};
            if (((JumpXY | LDSPHL) & XY_State != 2'b00) | (MCycle == 3'b110))
               RegAddrC <= {XY_State[1], 2'b11};
            
            if (I_DJNZ & Save_ALU_r & Mode < 2)
               IncDecZ <= F_Out[Flag_Z];
            if ((TState == 2 | (TState == 3 & MCycle == 3'b001)) & IncDec_16[2:0] == 3'b100) begin
               if (ID16 == 0)
                  IncDecZ <= 1'b0;
               else
                  IncDecZ <= 1'b1;
            end 
            
            RegBusA_r <= RegBusA;
         end 
      end 
   
   // 16 bit increment/decrement
   assign RegAddrA = ((TState == 2 | (TState == 3 & MCycle == 3'b001 & IncDec_16[2])) & XY_State == 2'b00) ? {Alternate, IncDec_16[1:0]} : 
                     ((TState == 2 | (TState == 3 & MCycle == 3'b001 & IncDec_16[2])) & IncDec_16[1:0] == 2'b10) ? {XY_State[1], 2'b11} : 
                     // EX HL,DL
                     (ExchangeDH & TState == 3) ? {Alternate, 2'b10} : 
                     (ExchangeDH & TState == 4) ? {Alternate, 2'b01} : 
                     // Bus A / Write
                     RegAddrA_r;
   
   assign RegAddrB = (ExchangeDH & TState == 3) ? {Alternate, 2'b01} :  // EX HL,DL
                     // Bus B
                     RegAddrB_r;
   
   assign ID16 = (IncDec_16[3]) ? RegBusA - 1 : RegBusA + 1;
   
   always @(Save_ALU_r or Auto_Wait_t1 or ALU_Op_r or Read_To_Reg_r or ExchangeDH or IncDec_16 or MCycle or TState or WAIT_n)
   begin
      RegWEH <= 1'b0;
      RegWEL <= 1'b0;
      if ((TState == 1 & Save_ALU_r == 1'b0 & Auto_Wait_t1 == 1'b0) | (Save_ALU_r & ALU_Op_r != 4'b0111))
         case (Read_To_Reg_r)
            5'b10000, 5'b10001, 5'b10010, 5'b10011, 5'b10100, 5'b10101 :
               begin
                  RegWEH <= (~Read_To_Reg_r[0]);
                  RegWEL <= Read_To_Reg_r[0];
               end
            default :
               ;
         endcase
      
      if (ExchangeDH & (TState == 3 | TState == 4)) begin
         RegWEH <= 1'b1;
         RegWEL <= 1'b1;
      end 
      
      if (IncDec_16[2] & ((TState == 2 & WAIT_n & MCycle != 3'b001) | (TState == 3 & MCycle == 3'b001)))
         case (IncDec_16[1:0])
            2'b00, 2'b01, 2'b10 :
               begin
                  RegWEH <= 1'b1;
                  RegWEL <= 1'b1;
               end
            default :
               ;
         endcase
   end
   
   
   always @(Save_Mux or RegBusB or RegBusA_r or ID16 or ExchangeDH or IncDec_16 or MCycle or TState or WAIT_n)
   begin
      RegDIH <= Save_Mux;
      RegDIL <= Save_Mux;
      
      if (ExchangeDH & TState == 3) begin
         RegDIH <= RegBusB[15:8];
         RegDIL <= RegBusB[7:0];
      end 
      if (ExchangeDH & TState == 4) begin
         RegDIH <= RegBusA_r[15:8];
         RegDIL <= RegBusA_r[7:0];
      end 
      
      if (IncDec_16[2] & ((TState == 2 & MCycle != 3'b001) | (TState == 3 & MCycle == 3'b001))) begin
         RegDIH <= ID16[15:8];
         RegDIL <= ID16[7:0];
      end 
   end
   
   
   T80_Reg Regs(
      .Clk(CLK_n), .CEN(ClkEn), .WEH(RegWEH), .WEL(RegWEL), .AddrA(RegAddrA), .AddrB(RegAddrB), 
      .AddrC(RegAddrC), .DIH(RegDIH), .DIL(RegDIL), .DOAH(RegBusA[15:8]), .DOAL(RegBusA[7:0]), 
      .DOBH(RegBusB[15:8]), .DOBL(RegBusB[7:0]), .DOCH(RegBusC[15:8]), .DOCL(RegBusC[7:0]), 
      .DOR(DOR), .DIRSet(DIRSet), .DIR(DIR[207:80])
   );
   
   //-------------------------------------------------------------------------
   //
   // Buses
   //
   //-------------------------------------------------------------------------
   always @(posedge CLK_n)
       begin
         if (ClkEn) begin
            case (Set_BusB_To)
               4'b0111 :
                  BusB <= ACC;
               4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100, 4'b0101 :
                  if (Set_BusB_To[0])
                     BusB <= RegBusB[7:0];
                  else
                     BusB <= RegBusB[15:8];
               4'b0110 :
                  BusB <= DI_Reg;
               4'b1000 :
                  BusB <= (SP[7:0]);
               4'b1001 :
                  BusB <= (SP[15:8]);
               4'b1010 :
                  BusB <= 8'b00000001;
               4'b1011 :
                  BusB <= F;
               4'b1100 :
                  BusB <= (PC[7:0]);
               4'b1101 :
                  BusB <= (PC[15:8]);
               4'b1110 :
                  if (IR == 8'h71 & out0)
                     BusB <= 8'b11111111;
                  else
                     BusB <= 8'b00000000;
               default :
                  BusB <= 8'bxxxxxxxx;
            endcase
            
            case (Set_BusA_To)
               4'b0111 :
                  BusA <= ACC;
               4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100, 4'b0101 :
                  if (Set_BusA_To[0])
                     BusA <= RegBusA[7:0];
                  else
                     BusA <= RegBusA[15:8];
               4'b0110 :
                  BusA <= DI_Reg;
               4'b1000 :
                  BusA <= (SP[7:0]);
               4'b1001 :
                  BusA <= (SP[15:8]);
               4'b1010 :
                  BusA <= 8'b00000000;
               default :
                  BusA <= 8'bxxxxxxxx;
            endcase
            if (XYbit_undoc) begin
               BusA <= DI_Reg;
               BusB <= DI_Reg;
            end 
         end 
      end 
   
   //-------------------------------------------------------------------------
   //
   // Generate external control signals
   //
   //-------------------------------------------------------------------------
   always @(negedge RESET_n or posedge CLK_n)
      if (RESET_n == 1'b0)
         RFSH_n <= 1'b1;
      else  begin
         if (DIRSet == 1'b0 & CEN) begin
            if (MCycle == 3'b001 & ((TState == 2 & WAIT_n) | TState == 3))
               RFSH_n <= 1'b0;
            else
               RFSH_n <= 1'b1;
         end 
      end 
   
   assign MC = MCycle;
   assign TS = TState;
   assign DI_Reg = DI;
   assign HALT_n = (~Halt_FF);
   assign BUSAK_n = (~(BusAck & RESET_n));
   assign IntCycle_n = (~IntCycle);
   assign IntE = IntE_FF1;
   assign IORQ = IORQ_i;
   assign Stop = I_DJNZ;
   
   //-----------------------------------------------------------------------
   //
   // Main state machine
   //
   //-----------------------------------------------------------------------
   always @(negedge RESET_n or posedge CLK_n)
   begin
      reg OldNMI_n;
      if (RESET_n == 1'b0) begin
         MCycle <= 3'b001;
         TState <= 3'b000;
         Pre_XY_F_M <= 3'b000;
         Halt_FF <= 1'b0;
         //BusAck <= '0';
         NMICycle <= 1'b0;
         IntCycle <= 1'b0;
         IntE_FF1 <= 1'b0;
         IntE_FF2 <= 1'b0;
         No_BTR <= 1'b0;
         Auto_Wait_t1 <= 1'b0;
         Auto_Wait_t2 <= 1'b0;
         M1_n <= 1'b1;
         //BusReq_s <= '0';
         NMI_s <= 1'b0;
      end else begin
         
         if (DIRSet) begin
            IntE_FF2 <= DIR[211];
            IntE_FF1 <= DIR[210];
         end else begin
            if (NMI_n == 1'b0 & OldNMI_n)
               NMI_s <= 1'b1;
            OldNMI_n = NMI_n;
            
            if (CEN) begin
               BusReq_s <= (~BUSRQ_n);
               Auto_Wait_t2 <= Auto_Wait_t1;
               if (T_Res) begin
                  Auto_Wait_t1 <= 1'b0;
                  Auto_Wait_t2 <= 1'b0;
               end else
                  Auto_Wait_t1 <= Auto_Wait | IORQ_i;
               No_BTR <= (I_BT & ((~IR[4]) | (~F[Flag_P]))) | (I_BC & ((~IR[4]) | F[Flag_Z] | (~F[Flag_P]))) | (I_BTR & ((~IR[4]) | F[Flag_Z]));
               if (TState == 2) begin
                  if (SetEI) begin
                     IntE_FF1 <= 1'b1;
                     IntE_FF2 <= 1'b1;
                  end 
                  if (I_RETN)
                     IntE_FF1 <= IntE_FF2;
               end 
               if (TState == 3) begin
                  if (SetDI) begin
                     IntE_FF1 <= 1'b0;
                     IntE_FF2 <= 1'b0;
                  end 
               end 
               if (IntCycle | NMICycle)
                  Halt_FF <= 1'b0;
               if (MCycle == 3'b001 & TState == 2 & WAIT_n)
                  M1_n <= 1'b1;
               if (BusReq_s & BusAck)
                  ;
               else begin
                  BusAck <= 1'b0;
                  if (TState == 2 & WAIT_n == 1'b0)
                     ;
                  else if (T_Res) begin
                     if (Halt)
                        Halt_FF <= 1'b1;
                     if (BusReq_s)
                        BusAck <= 1'b1;
                     else begin
                        TState <= 3'b001;
                        if (NextIs_XY_Fetch) begin
                           MCycle <= 3'b110;
                           Pre_XY_F_M <= MCycle;
                           if (IR == 8'b00110110 & Mode == 0)
                              Pre_XY_F_M <= 3'b010;
                        end else if ((MCycle == 3'b111) | (MCycle == 3'b110 & Mode == 1 & ISet != 2'b01))
                           MCycle <= (Pre_XY_F_M + 1);
                        else if ((MCycle == MCycles) | No_BTR | (MCycle == 3'b010 & I_DJNZ & IncDecZ)) begin
                           M1_n <= 1'b0;
                           MCycle <= 3'b001;
                           IntCycle <= 1'b0;
                           NMICycle <= 1'b0;
                           if (NMI_s & Prefix == 2'b00) begin
                              NMI_s <= 1'b0;
                              NMICycle <= 1'b1;
                              IntE_FF1 <= 1'b0;
                           end else if (IntE_FF1 & INT_n == 1'b0 & Prefix == 2'b00 & SetEI == 1'b0) begin
                              IntCycle <= 1'b1;
                              IntE_FF1 <= 1'b0;
                              IntE_FF2 <= 1'b0;
                           end 
                        end 
                        else
                           MCycle <= (MCycle + 1);
                     end
                  end 
                  else
                     if (~((Auto_Wait & Auto_Wait_t2 == 1'b0) | (IOWait == 1 & IORQ_i & Auto_Wait_t1 == 1'b0)))
                        TState <= TState + 1;
               end
               if (TState == 0)
                  M1_n <= 1'b0;
            end 
         end
      end 
   end
   
   assign Auto_Wait = (IntCycle & MCycle == 3'b001) ? 1'b1 : 1'b0;
   
endmodule
