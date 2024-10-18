// simulation model for sdram.v, CL2
module sdram_sim (
    // Logic side interface
    input             clk,
    input             resetn,
    output            busy,

    // 3 sets of access interfaces, with 0 having the highest priority
    input             req0,         // request toggle
    output reg        ack0,         // acknowledge toggle
    input             wr0,          // 1: write, 0: read
    input      [24:1] addr0,        // word address
    input      [15:0] din0,         // data input
    output reg [15:0] dout0,        // data output
    input       [1:0] be0,          // byte enable

    input             req1, 
    output reg        ack1, 
    input             wr1,
    input      [24:1] addr1,       
    input      [15:0] din1,        
    output reg [15:0] dout1,       
    input       [1:0] be1,

    input             req2, 
    output reg        ack2, 
    input             wr2,
    input      [24:1] addr2,       
    input      [15:0] din2,        
    output reg [15:0] dout2,       
    input       [1:0] be2
);

reg [15:0] mem [0:16*1024*1024-1];  // 32MB of memory
reg [2:0] cycle;
reg busy_buf = 1;
assign busy = busy_buf;

reg [3:0] start_cnt = 15;

reg [2:0] state;
reg [1:0] port;
localparam IDLE = 0;
localparam RAS = 1;
localparam CAS0 = 2;
localparam CAS1 = 3;
// localparam READY = 4;

reg [24:1] addr;
reg [15:0] din;
reg wr;
reg [1:0] be;

always @(posedge clk) begin
    start_cnt <= start_cnt == 0 ? 0 : start_cnt - 1;
    if (start_cnt == 1)
        busy_buf <= 0;

    // ready0 <= 0; ready1 <= 0; ready2 <= 0;
    case (state)
    IDLE: begin
        if (req0 != ack0) begin
            addr <= addr0;
            din <= din0;
            wr <= wr0;
            be <= be0;
            port <= 0;
            busy_buf <= 1;
            state <= RAS;
        end else if (req1 != ack1) begin
            addr <= addr1;
            din <= din1;
            wr <= wr1;
            be <= be1;
            port <= 1;
            busy_buf <= 1;
            state <= RAS;
        end else if (req2 != ack2) begin
            addr <= addr2;
            din <= din2;
            wr <= wr2;
            be <= be2;
            port <= 2;
            busy_buf <= 1;
            state <= RAS;
        end
    end

    RAS: state <= CAS0;

    CAS0: state <= CAS1;

    CAS1: begin
        if (wr) begin
            if (be[0]) begin
                mem[addr][7:0] <= din[7:0];
            end
            if (be[1]) begin
                mem[addr][15:8] <= din[15:8];
            end
            // $display("sdram[%h]<=%h", addr, din);
        end else begin
            if (port == 0) begin
                dout0 <= mem[addr];
                // $display("sdram[%h] = %h", addr, mem[addr]);
            end else if (port == 1) 
                dout1 <= mem[addr];
            else 
                dout2 <= mem[addr];
        end
        if (port == 0) ack0 <= req0;
        else if (port == 1) ack1 <= req1;
        else ack2 <= req2;
        state <= IDLE;
    end

    // READY:
    //     state <= IDLE;

    default: ;

    endcase

end

endmodule