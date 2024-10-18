// Simple SDRAM controller for Tang Mega 138K and Tang SDRAM module
// nand2mario
// 
// 2024.10: inital version.
//
// This is a 16-bit, low-latency and non-bursting controller for accessing the SDRAM module
// on Tang Mega 138K. The SDRAM is 4 banks x 8192 rows x 512 columns x 16 bits (32MB in total).
//
// Timing:
//     clk        /‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___/‾‾‾\___
//     host       |  req  |       |       |       |  ack  |
//     sdram              |  RAS  |  CAS  |       |  DAT  |
//     cycle          0       1       2       3       4   
//
// Under default settings (CL2, max 66.7Mhz):
// - Read/write latency is 4 cycles. 
// - All reads/writes are done with auto-precharge. So the user does not need to deal with
//   row activations and precharges.
// - Refresh is done automatically every 15us, when the controller is idle, and `refresh_allowed==1`.

module sdram
#(
    // Clock frequency, max 66.7Mhz with current set of T_xx/CAS parameters.
    parameter         FREQ = 64_800_000,  

    // Time delays for 66.7Mhz max clock (min clock cycle 15ns)
    // The SDRAM supports max 166.7Mhz (RP/RCD/RC need changes)
    parameter [3:0]   CAS  = 4'd2,     // 2/3 cycles, set in mode register
    parameter [3:0]   T_WR = 4'd2,     // 2 cycles, write recovery
    parameter [3:0]   T_MRD= 4'd2,     // 2 cycles, mode register set
    parameter [3:0]   T_RP = 4'd1,     // 15ns, precharge to active
    parameter [3:0]   T_RCD= 4'd1,     // 15ns, active to r/w
    parameter [3:0]   T_RC = 4'd4      // 60ns, ref/active to ref/active
)
(
    // SDRAM side interface
    inout      [15:0] SDRAM_DQ,
    output     [12:0] SDRAM_A,
    output reg [1:0]  SDRAM_DQM,
    output reg [1:0]  SDRAM_BA,
    output            SDRAM_nWE,
    output            SDRAM_nRAS,
    output            SDRAM_nCAS,
    output            SDRAM_nCS,    // always 0
    output            SDRAM_CKE,    // always 1
    
    // Logic side interface
    input             clk,
    input             resetn,
    input             refresh_allowed,      // Should be set to 1 to allow auto-refresh normally
    output            busy,

    // 3 sets of access interfaces, with 0 having the highest priority
    input             req0,         // request toggle
    output reg        ack0,         // acknowledge toggle
    input             wr0,          // 1: write, 0: read
    input      [24:1] addr0,        // word address
    input      [15:0] din0,         // data input
    output     [15:0] dout0,        // data output
    input       [1:0] be0,          // byte enable

    input             req1, 
    output reg        ack1, 
    input             wr1,
    input      [24:1] addr1,       
    input      [15:0] din1,        
    output     [15:0] dout1,       
    input       [1:0] be1,

    input             req2, 
    output reg        ack2, 
    input             wr2,
    input      [24:1] addr2,       
    input      [15:0] din2,        
    output     [15:0] dout2,       
    input       [1:0] be2
);

if (FREQ > 66_700_000 && CAS == 2)
    $error("ERROR: FREQ must be <= 66.7Mhz for CAS=2. Either lower FREQ or set CAS=3, and T_RCD accordingly.");

reg busy_buf = 1;
assign busy = busy_buf;

// Tri-state DQ input/output
reg dq_oen;                                     // 0: dq output valid
reg [15:0] dq_out;
assign SDRAM_DQ = dq_oen ? {16{1'bZ}} : dq_out;
wire [15:0] dq_in = SDRAM_DQ;         // dq input
reg [2:0] cmd;
reg [12:0] a;
assign {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} = cmd;
assign SDRAM_A = a;

wire [2:0]  req [0:2]   = '{req0, req1, req2};
wire [24:1] addr [0:2]  = '{addr0, addr1, addr2};
wire [15:0] din [0:2]   = '{din0, din1, din2};
wire        wr [0:2]    = '{wr0, wr1, wr2};
wire [1:0]  be [0:2]    = '{be0, be1, be2};

reg [15:0] dout_buf[0:2];
reg data_ready;
wire ready0 = req_id_buf == 0 ? data_ready : 1'b0;
wire ready1 = req_id_buf == 1 ? data_ready : 1'b0;
wire ready2 = req_id_buf == 2 ? data_ready : 1'b0;
assign dout0 = ready0 ? dq_in : dout_buf[0];
assign dout1 = ready1 ? dq_in : dout_buf[1];
assign dout2 = ready2 ? dq_in : dout_buf[2];

assign SDRAM_CKE = 1'b1;
assign SDRAM_nCS = 1'b0;

reg [2:0] state;
localparam INIT = 3'd0;
localparam CONFIG = 3'd1;
localparam IDLE = 3'd2;
localparam READ = 3'd3;
localparam WRITE = 3'd4;
localparam REFRESH = 3'd5;

// RAS# CAS# WE#
localparam CMD_SetModeReg=3'b000;
localparam CMD_AutoRefresh=3'b001;
localparam CMD_PreCharge=3'b010;
localparam CMD_BankActivate=3'b011;
localparam CMD_Write=3'b100;
localparam CMD_Read=3'b101;
localparam CMD_NOP=3'b111;

localparam [2:0] BURST_LEN = 3'b0;      // burst length 1
localparam BURST_MODE = 1'b0;           // sequential
localparam [10:0] MODE_REG = {4'b0, CAS[2:0], BURST_MODE, BURST_LEN};

localparam REFRESH_CYCLES = FREQ / 1000 * 64 / 8192; // 64ms/8192 rows = 7.8us -> 500 cycles@64.8MHz

reg cfg_now;           

reg [3:0] cycle; 
reg [15:0] din_buf; 
reg [24:1] addr_buf;
reg [1:0] req_id_buf;
reg [1:0] be_buf;

reg [9:0] refresh_cnt;
reg need_refresh;

always @(posedge clk) begin
	if (refresh_cnt == 0)
		need_refresh <= 0;
	else if (refresh_cnt == REFRESH_CYCLES)
		need_refresh <= 1;
end

//
// SDRAM state machine
//
always @(posedge clk) begin
    reg new_req;
    reg [1:0] req_id;
    new_req = (req2 ^ ack2) | (req1 ^ ack1) | (req0 ^ ack0);
    req_id = req0 ^ ack0 ? 0 : req1 ^ ack1 ? 1 : 2;         // priority: 0 > 1 > 2

    cycle <= cycle == 4'd15 ? 4'd15 : cycle + 4'd1;
    refresh_cnt <= refresh_cnt + 1;

    // defaults
    cmd <= CMD_NOP; 
    casex ({state, cycle})
        // wait 200 us on power-on
        {INIT, 4'bxxxx} : if (cfg_now) begin
            state <= CONFIG;
            cycle <= 0;
        end
        // Initialization sequence
        {CONFIG, 4'd0} : begin              // precharge all
            cmd <= CMD_PreCharge;
            a[10] <= 1'b1;
        end
        {CONFIG, T_RP} : begin              // 1st AutoRefresh
            cmd <= CMD_AutoRefresh;
        end
        {CONFIG, T_RP+T_RC} : begin         // 2nd AutoRefresh
            cmd <= CMD_AutoRefresh;
        end
        {CONFIG, T_RP+T_RC+T_RC} : begin    // set register
            cmd <= CMD_SetModeReg;
            a[10:0] <= MODE_REG;
        end
        {CONFIG, T_RP+T_RC+T_RC+T_MRD} : begin
            state <= IDLE;
            busy_buf <= 1'b0;                   // init&config is done
            refresh_cnt <= 0;
        end
        
        // read/write/refresh
        {IDLE, 4'bxxxx}: if (new_req) begin
            addr_buf <= addr[req_id];
            be_buf <= be[req_id];
            din_buf <= din[req_id];
            cycle <= 4'd1;
            busy_buf <= 1'b1;
            req_id_buf <= req_id;

            // bank activate
            cmd <= CMD_BankActivate;
            SDRAM_BA <= addr[req_id][24:23];
            a <= addr[req_id][22:10];     

            state <= wr[req_id] ? WRITE : READ;
        end else if (need_refresh & refresh_allowed) begin
            cycle <= 4'd1;
            busy_buf <= 1'b1;
            refresh_cnt <= 0;

            // auto-refresh
            cmd <= CMD_AutoRefresh;

            state <= REFRESH;
        end

        // read sequence
        {READ, T_RCD}: begin
            cmd <= CMD_Read;
            a[12:0] <= {4'b0010, addr_buf[9:1]};  // column address with auto precharge
            SDRAM_DQM <= 2'b0;
        end
        {READ, T_RCD+CAS}: begin
            case (req_id_buf)
                0: ack0 <= req0;
                1: ack1 <= req1;
                2: ack2 <= req2;
                default: ;
            endcase
            data_ready <= 1;
        end
        {READ, T_RCD+CAS+4'd1}: begin
            dout_buf[req_id_buf] <= dq_in;
            busy_buf <= 0;
            data_ready <= 0;
            state <= IDLE;
        end

        // write sequence
        {WRITE, T_RCD}: begin
            cmd <= CMD_Write;
            a[12:0] <= {4'b0010, addr_buf[9:1]};  // column address with auto precharge
            SDRAM_DQM <= ~be_buf;     
            dq_out <= din_buf;
            dq_oen <= 1'b0;                 
        end
        {WRITE, T_RCD+4'd1}: begin
            dq_oen <= 1'b1;
        end
        {WRITE, T_RCD+4'd2}: begin 
            case (req_id_buf)
                0: ack0 <= req0;
                1: ack1 <= req1;
                2: ack2 <= req2;
                default: ;
            endcase
            busy_buf <= 0;
            state <= IDLE;
        end

        {REFRESH, T_RC}: begin
            state <= IDLE;
            busy_buf <= 0;
        end
    endcase

    if (~resetn) begin
        busy_buf <= 1'b1;
        dq_oen <= 1'b1;         // turn off DQ output
        SDRAM_DQM <= 4'b0;
        state <= INIT;
    end
end


//
// Generate cfg_now pulse after initialization delay (normally 200us)
//
reg  [14:0]   rst_cnt;
reg rst_done, rst_done_p1, cfg_busy;
  
always @(posedge clk) begin
    rst_done_p1 <= rst_done;
    cfg_now     <= rst_done & ~rst_done_p1;// Rising Edge Detect

    if (rst_cnt != FREQ / 1000 * 200 / 1000) begin      // count to 200 us
        rst_cnt  <= rst_cnt[14:0] + 1;
        rst_done <= 1'b0;
        cfg_busy <= 1'b1;
    end else begin
        rst_done <= 1'b1;
        cfg_busy <= 1'b0;
    end

    if (~resetn) begin
        rst_cnt  <= 15'd0;
        rst_done <= 1'b0;
        cfg_busy <= 1'b1;
    end
end

endmodule