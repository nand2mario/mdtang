// Dual-port RAM of any size
module dpram
 #(  parameter ADRW = 8, // address width (therefore total size is 2**ADRW)
     parameter DATW = 8, // data width
     parameter FILE = "", // initialization hex file, optional
     parameter SSRAM = 0
  )( input                 clock    , // clock
     input                 wren_a , // write enable for port A
     input                 wren_b , // write enable for port B
     input      [ADRW-1:0] address_a , // address      for port A
     input      [ADRW-1:0] address_b , // address      for port B
     input      [DATW-1:0] data_a, // write data   for port A
     input      [DATW-1:0] data_b, // write data   for port B
     output reg [DATW-1:0] q_a, // read  data   for port A
     output reg [DATW-1:0] q_b  // read  data   for port B
  );

    localparam MEMD = 1 << ADRW;

    // initialize RAM, with zeros if ZERO or file if FILE.
    integer i;

    reg [DATW-1:0] mem [0:MEMD-1]; // memory array
    initial
        if (FILE != "") $readmemh(FILE, mem);

    // PORT A
    always @(posedge clock) 
        if (wren_a)
            mem[address_a] <= data_a;

    always @(posedge clock) 
        if (!wren_a)
            q_a <= mem[address_a]; 

    // PORT B
    always @(posedge clock) 
        if (wren_b) 
            mem[address_b] <= data_b;

    always @(posedge clock)
        if (!wren_b)
            q_b <= mem[address_b];

endmodule