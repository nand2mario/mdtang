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
//
// Ver 300 started tidyup
// MikeJ March 2005
// Latest version from www.fpgaarcade.com (original www.opencores.org)
//
// ****
//
// T80 Registers, technology independent
//
// Version : 0244
//
// Copyright (c) 2002 Daniel Wallner (jesus@opencores.org)
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
//	http://www.opencores.org/cvsweb.shtml/t51/
//
// Limitations :
//
// File history :
//
//	0242 : Initial release
//
//	0244 : Changed to single register file
//

module T80_Reg(
   input          Clk,
   input          CEN,
   input          WEH,
   input          WEL,
   input [2:0]    AddrA,
   input [2:0]    AddrB,
   input [2:0]    AddrC,
   input [7:0]    DIH,
   input [7:0]    DIL,
   output [7:0]   DOAH,
   output [7:0]   DOAL,
   output [7:0]   DOBH,
   output [7:0]   DOBL,
   output [7:0]   DOCH,
   output [7:0]   DOCL,
   output [127:0] DOR,
   input          DIRSet,
   input [127:0]  DIR
);
   
   reg [7:0]      RegsH[0:7];
   reg [7:0]      RegsL[0:7];
   
   always @(posedge Clk)
       begin
         if (DIRSet) begin
            RegsL[0] <= DIR[7:0];
            RegsH[0] <= DIR[15:8];
            
            RegsL[1] <= DIR[23:16];
            RegsH[1] <= DIR[31:24];
            
            RegsL[2] <= DIR[39:32];
            RegsH[2] <= DIR[47:40];
            
            RegsL[3] <= DIR[55:48];
            RegsH[3] <= DIR[63:56];
            
            RegsL[4] <= DIR[71:64];
            RegsH[4] <= DIR[79:72];
            
            RegsL[5] <= DIR[87:80];
            RegsH[5] <= DIR[95:88];
            
            RegsL[6] <= DIR[103:96];
            RegsH[6] <= DIR[111:104];
            
            RegsL[7] <= DIR[119:112];
            RegsH[7] <= DIR[127:120];
         end else if (CEN) begin
            if (WEH)
               RegsH[AddrA] <= DIH;
            if (WEL)
               RegsL[AddrA] <= DIL;
         end 
      end 
   
   assign DOAH = RegsH[AddrA];
   assign DOAL = RegsL[AddrA];
   assign DOBH = RegsH[AddrB];
   assign DOBL = RegsL[AddrB];
   assign DOCH = RegsH[AddrC];
   assign DOCL = RegsL[AddrC];
   assign DOR = {RegsH[7], RegsL[7], RegsH[6], RegsL[6], RegsH[5], RegsL[5], RegsH[4], RegsL[4], 
                 RegsH[3], RegsL[3], RegsH[2], RegsL[2], RegsH[1], RegsL[1], RegsH[0], RegsL[0]};
   
endmodule
