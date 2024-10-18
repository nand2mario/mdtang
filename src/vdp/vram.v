module vram (
    input        clk,

	input        loading,		// 1: clear VRAM (keep high for at least 16K cycles)

    input        vram_req,
    output reg   vram_ack,
    input        vram_we,
    input        vram_u_n,
    input        vram_l_n,
    input [15:1] vram_a,
    input [15:0] vram_d,
    output [15:0] vram_q,

    input        vram32_req,
    output reg   vram32_ack,
    input [15:1] vram32_a,
    output [31:0] vram32_q
);

wire        vram_we_u = vram_we & ~vram_u_n;
wire        vram_we_l = vram_we & ~vram_l_n;
wire [15:0] vram_q1;
wire [15:0] vram_q2;

reg vram_a1_r;
always @(posedge clk) vram_a1_r <= vram_a[1];

assign vram_q = vram_a1_r ? vram_q2 : vram_q1;

reg [14:1] ram_rst_a;
always @(posedge clk) ram_rst_a <= ram_rst_a + loading;

dpram #(14) vram_l1
(
	.clock(clk),
	.address_a(vram_a[15:2]),
	.data_a(vram_d[7:0]),
	.wren_a(vram_we_l & (vram_ack ^ vram_req) & ~vram_a[1]),
	.q_a(vram_q1[7:0]),

	.address_b(loading ? ram_rst_a : vram32_a[15:2]),
	.wren_b(loading),
	.q_b(vram32_q[7:0])
);

dpram #(14) vram_u1
(
	.clock(clk),
	.address_a(vram_a[15:2]),
	.data_a(vram_d[15:8]),
	.wren_a(vram_we_u & (vram_ack ^ vram_req) & ~vram_a[1]),
	.q_a(vram_q1[15:8]),

	.address_b(loading ? ram_rst_a : vram32_a[15:2]),
	.wren_b(loading),
	.q_b(vram32_q[15:8])
);

dpram #(14) vram_l2
(
	.clock(clk),
	.address_a(vram_a[15:2]),
	.data_a(vram_d[7:0]),
	.wren_a(vram_we_l & (vram_ack ^ vram_req) & vram_a[1]),
	.q_a(vram_q2[7:0]),

	.address_b(loading ? ram_rst_a : vram32_a[15:2]),
	.wren_b(loading),
	.q_b(vram32_q[23:16])
);

dpram #(14) vram_u2
(
	.clock(clk),
	.address_a(vram_a[15:2]),
	.data_a(vram_d[15:8]),
	.wren_a(vram_we_u & (vram_ack ^ vram_req) & vram_a[1]),
	.q_a(vram_q2[15:8]),

	.address_b(loading ? ram_rst_a : vram32_a[15:2]),
	.wren_b(loading),
	.q_b(vram32_q[31:24])
);

always @(posedge clk) vram_ack <= vram_req;

always @(posedge clk) vram32_ack <= vram32_req;

endmodule