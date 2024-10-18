// Adapter the 32-bit iosys RV memory interface to 16-bit sdram controller
module rv_sdram_adapter (
    input clk,
    input resetn,

    input rv_valid        /* xsynthesis syn_keep=1 */,
    input [22:0]  rv_addr  /* xsynthesis syn_keep=1 */,
    input [31:0]  rv_wdata /* xsynthesis syn_keep=1 */,
    input [3:0]   rv_wstrb  /* xsynthesis syn_keep=1 */,
    output reg    rv_ready   /* xsynthesis syn_keep=1 */,            // 1: rv_rdata is available now
    output [31:0] rv_rdata/* xsynthesis syn_keep=1 */,

    output reg [22:1]   mem_addr,
    output reg          mem_req,
    output reg [1:0]    mem_ds,
    output reg [15:0]   mem_din,
    output reg          mem_we,
    input               mem_req_ack,        // CHANGED: mem_ready is removed. ack-change is used as ready.
    input [15:0]        mem_dout
);

localparam RV_IDLE_REQ0 = 0;
localparam RV_ACK0_REQ1 = 1;
localparam RV_ACK1 = 2;

// RV output
reg [1:0] rvst;
reg rv_valid_r, hi_reg;
reg [15:0] mem_dout0;
reg mem_req_r;
assign rv_rdata = {mem_dout, mem_dout0};

wire idle = mem_req == mem_req_ack;
reg idle_r;
always @(posedge clk) idle_r <= idle;
wire mem_ready = idle & ~idle_r;

always @* begin
    reg hi;
    if (rv_valid & rvst == RV_IDLE_REQ0) begin  // start of RV request
        hi = rv_wstrb[3:2] != 2'b0 & rv_wstrb[1:0] == 2'b0;
        mem_req = ~mem_req_r;
    end else begin                              // subsequent cycles
        hi = hi_reg;
        mem_req = mem_req_r;
    end
    mem_addr = {rv_addr[22:2], hi};
    mem_din = hi ? rv_wdata[31:16] : rv_wdata[15:0];
    mem_we = rv_wstrb != 0;
    mem_ds = hi ? rv_wstrb[3:2] : rv_wstrb[1:0];
    rv_ready = (rvst == RV_ACK1) & mem_ready;
end

always @(posedge clk) begin            // RV
    if (~resetn) begin
        rvst <= RV_IDLE_REQ0;
    end else begin
        reg write;
        write = rv_wstrb != 4'b0;
        mem_req_r <= mem_req;           // default

        case (rvst)
        RV_IDLE_REQ0: 
            if (rv_valid) begin
                hi_reg <= (rv_wstrb[3:2] != '0) & (rv_wstrb[1:0] == '0);    // accessing high 16-bit
                if ((rv_wstrb[3:2] == '0) ^ (rv_wstrb[1:0] == '0))          // 16-bit write
                    rvst <= RV_ACK1;
                else 
                    rvst <= RV_ACK0_REQ1;
            end

        RV_ACK0_REQ1:                           // wait for request 0 ack and issue request 1
            if (mem_req == mem_req_ack) begin
                if (!write) 
                    mem_dout0 <= mem_dout;      // save low 16-bit for reads
                mem_req_r <= ~mem_req_r;        // issue request 1
                hi_reg <= 1;
                rvst <= RV_ACK1;
            end

        RV_ACK1:                                // wait for request 1 ack and return to idle
            if (mem_req == mem_req_ack) begin   // rv_ready pulse here
                rvst <= RV_IDLE_REQ0;
            end

        default:;
        endcase

    end
end


endmodule