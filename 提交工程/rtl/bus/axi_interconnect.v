//=============================================================================
// AXI4-Lite Interconnect
//
// Description:
//   Connects CPU master to multiple slave peripherals with address decoding
//   and round-robin arbitration for multiple masters (I-Cache, D-Cache).
//
// Features:
//   - Full AXI4-Lite protocol support
//   - Configurable number of slaves (up to 8)
//   - Address-based routing with configurable base addresses
//   - Round-robin arbitration for multiple masters
//   - Proper error response (DECERR) for unmapped addresses
//   - No starvation guarantee
//
// Memory Map (default):
//   Slave 0: 0x0000_0000 - 0x0000_3FFF (16KB Boot ROM)
//   Slave 1: 0x8000_0000 - 0x8003_FFFF (256KB Main Memory/SRAM)
//   Slave 2: 0x1000_0000 - 0x1000_00FF (256B UART)
//   Slave 3: 0x1000_0100 - 0x1000_01FF (256B GPIO)
//   Slave 4: 0x1000_0200 - 0x1000_02FF (256B Timer)
//
// Requirements: 2.5, 2.6
//=============================================================================

`timescale 1ns/1ps

module axi_interconnect #(
    parameter NUM_MASTERS = 2,          // I-Cache + D-Cache
    parameter NUM_SLAVES  = 5,          // Boot ROM, SRAM, UART, GPIO, Timer
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32,
    parameter TIMEOUT_CYCLES = 1000     // Bus timeout
)(
    input  wire                         clk,
    input  wire                         rst_n,
    
    //=========================================================================
    // Master Ports (from CPU I-Cache and D-Cache)
    //=========================================================================
    // Master 0: I-Cache (instruction fetch)
    // Master 1: D-Cache (data access)
    
    // Write Address Channel
    input  wire [NUM_MASTERS-1:0]                   m_awvalid,
    output wire [NUM_MASTERS-1:0]                   m_awready,
    input  wire [NUM_MASTERS*ADDR_WIDTH-1:0]        m_awaddr,
    input  wire [NUM_MASTERS*3-1:0]                 m_awprot,
    
    // Write Data Channel
    input  wire [NUM_MASTERS-1:0]                   m_wvalid,
    output wire [NUM_MASTERS-1:0]                   m_wready,
    input  wire [NUM_MASTERS*DATA_WIDTH-1:0]        m_wdata,
    input  wire [NUM_MASTERS*(DATA_WIDTH/8)-1:0]    m_wstrb,
    
    // Write Response Channel
    output wire [NUM_MASTERS-1:0]                   m_bvalid,
    input  wire [NUM_MASTERS-1:0]                   m_bready,
    output wire [NUM_MASTERS*2-1:0]                 m_bresp,
    
    // Read Address Channel
    input  wire [NUM_MASTERS-1:0]                   m_arvalid,
    output wire [NUM_MASTERS-1:0]                   m_arready,
    input  wire [NUM_MASTERS*ADDR_WIDTH-1:0]        m_araddr,
    input  wire [NUM_MASTERS*3-1:0]                 m_arprot,
    
    // Read Data Channel
    output wire [NUM_MASTERS-1:0]                   m_rvalid,
    input  wire [NUM_MASTERS-1:0]                   m_rready,
    output wire [NUM_MASTERS*DATA_WIDTH-1:0]        m_rdata,
    output wire [NUM_MASTERS*2-1:0]                 m_rresp,
    
    //=========================================================================
    // Slave Ports (to peripherals)
    //=========================================================================
    
    // Write Address Channel
    output wire [NUM_SLAVES-1:0]                    s_awvalid,
    input  wire [NUM_SLAVES-1:0]                    s_awready,
    output wire [NUM_SLAVES*ADDR_WIDTH-1:0]         s_awaddr,
    output wire [NUM_SLAVES*3-1:0]                  s_awprot,
    
    // Write Data Channel
    output wire [NUM_SLAVES-1:0]                    s_wvalid,
    input  wire [NUM_SLAVES-1:0]                    s_wready,
    output wire [NUM_SLAVES*DATA_WIDTH-1:0]         s_wdata,
    output wire [NUM_SLAVES*(DATA_WIDTH/8)-1:0]     s_wstrb,
    
    // Write Response Channel
    input  wire [NUM_SLAVES-1:0]                    s_bvalid,
    output wire [NUM_SLAVES-1:0]                    s_bready,
    input  wire [NUM_SLAVES*2-1:0]                  s_bresp,
    
    // Read Address Channel
    output wire [NUM_SLAVES-1:0]                    s_arvalid,
    input  wire [NUM_SLAVES-1:0]                    s_arready,
    output wire [NUM_SLAVES*ADDR_WIDTH-1:0]         s_araddr,
    output wire [NUM_SLAVES*3-1:0]                  s_arprot,
    
    // Read Data Channel
    input  wire [NUM_SLAVES-1:0]                    s_rvalid,
    output wire [NUM_SLAVES-1:0]                    s_rready,
    input  wire [NUM_SLAVES*DATA_WIDTH-1:0]         s_rdata,
    input  wire [NUM_SLAVES*2-1:0]                  s_rresp
);

    //=========================================================================
    // Local Parameters
    //=========================================================================
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_EXOKAY = 2'b01;
    localparam RESP_SLVERR = 2'b10;
    localparam RESP_DECERR = 2'b11;
    
    // Arbitration states
    localparam ARB_IDLE     = 3'd0;
    localparam ARB_WRITE    = 3'd1;
    localparam ARB_WRITE_RESP = 3'd2;
    localparam ARB_READ     = 3'd3;
    localparam ARB_READ_RESP = 3'd4;
    localparam ARB_ERROR    = 3'd5;
    
    //=========================================================================
    // Address Decode Configuration
    // Each slave has a base address and mask
    //=========================================================================
    // Slave 0: Boot ROM   0x0000_0000, mask 0xFFFF_C000 (16KB)
    // Slave 1: SRAM       0x8000_0000, mask 0xFFFC_0000 (256KB)
    // Slave 2: UART       0x1000_0000, mask 0xFFFF_FF00 (256B)
    // Slave 3: GPIO       0x1000_0100, mask 0xFFFF_FF00 (256B)
    // Slave 4: Timer      0x1000_0200, mask 0xFFFF_FF00 (256B)
    
    reg [31:0] slave_base [0:NUM_SLAVES-1];
    reg [31:0] slave_mask [0:NUM_SLAVES-1];
    
    initial begin
        slave_base[0] = 32'h0000_0000; slave_mask[0] = 32'hFFFF_C000;  // Boot ROM
        slave_base[1] = 32'h8000_0000; slave_mask[1] = 32'hFFFC_0000;  // SRAM
        slave_base[2] = 32'h1000_0000; slave_mask[2] = 32'hFFFF_FF00;  // UART
        slave_base[3] = 32'h1000_0100; slave_mask[3] = 32'hFFFF_FF00;  // GPIO
        slave_base[4] = 32'h1000_0200; slave_mask[4] = 32'hFFFF_FF00;  // Timer
    end

    //=========================================================================
    // Internal Signals
    //=========================================================================
    
    // Arbitration state machine
    reg [2:0]   arb_state;
    reg [2:0]   arb_state_next;
    
    // Current master being serviced (round-robin)
    reg [$clog2(NUM_MASTERS)-1:0] current_master;
    reg [$clog2(NUM_MASTERS)-1:0] last_granted;
    
    // Current slave being accessed
    reg [$clog2(NUM_SLAVES):0]    current_slave;  // Extra bit for invalid
    reg                           slave_valid;
    
    // Latched transaction info
    reg [ADDR_WIDTH-1:0]          latched_addr;
    reg [DATA_WIDTH-1:0]          latched_wdata;
    reg [(DATA_WIDTH/8)-1:0]      latched_wstrb;
    reg [2:0]                     latched_prot;
    reg                           latched_is_write;
    
    // Timeout counter
    reg [15:0]                    timeout_cnt;
    wire                          timeout;
    
    // Response handling
    reg [DATA_WIDTH-1:0]          resp_rdata;
    reg [1:0]                     resp_code;
    reg                           resp_valid;
    
    // Master request detection
    wire [NUM_MASTERS-1:0]        master_write_req;
    wire [NUM_MASTERS-1:0]        master_read_req;
    wire [NUM_MASTERS-1:0]        master_any_req;
    
    genvar m;
    generate
        for (m = 0; m < NUM_MASTERS; m = m + 1) begin : gen_master_req
            assign master_write_req[m] = m_awvalid[m] && m_wvalid[m];
            assign master_read_req[m]  = m_arvalid[m];
            assign master_any_req[m]   = master_write_req[m] || master_read_req[m];
        end
    endgenerate
    
    //=========================================================================
    // Address Decode Function
    //=========================================================================
    function [$clog2(NUM_SLAVES):0] decode_address;
        input [ADDR_WIDTH-1:0] addr;
        integer i;
        reg found;
    begin
        decode_address = NUM_SLAVES;  // Invalid by default
        found = 0;
        for (i = 0; i < NUM_SLAVES && !found; i = i + 1) begin
            if ((addr & slave_mask[i]) == slave_base[i]) begin
                decode_address = i;
                found = 1;
            end
        end
    end
    endfunction
    
    //=========================================================================
    // Round-Robin Arbitration
    //=========================================================================
    function [$clog2(NUM_MASTERS)-1:0] find_next_master;
        input [$clog2(NUM_MASTERS)-1:0] last;
        input [NUM_MASTERS-1:0] requests;
        integer i;
        reg found;
        reg [$clog2(NUM_MASTERS)-1:0] check;
    begin
        find_next_master = last;
        found = 0;
        
        // Start from last+1 and wrap around
        for (i = 0; i < NUM_MASTERS && !found; i = i + 1) begin
            check = (last + 1 + i) % NUM_MASTERS;
            if (requests[check]) begin
                find_next_master = check;
                found = 1;
            end
        end
    end
    endfunction
    
    //=========================================================================
    // Timeout Detection
    //=========================================================================
    assign timeout = (timeout_cnt >= TIMEOUT_CYCLES);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_cnt <= 16'd0;
        end else if (arb_state == ARB_IDLE) begin
            timeout_cnt <= 16'd0;
        end else begin
            if (timeout_cnt < TIMEOUT_CYCLES) begin
                timeout_cnt <= timeout_cnt + 1;
            end
        end
    end
    
    //=========================================================================
    // Arbitration State Machine
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arb_state <= ARB_IDLE;
        end else begin
            arb_state <= arb_state_next;
        end
    end
    
    // Next state logic
    always @(*) begin
        arb_state_next = arb_state;
        
        case (arb_state)
            ARB_IDLE: begin
                if (|master_any_req) begin
                    if (master_write_req[calc_next_master]) begin
                        arb_state_next = ARB_WRITE;
                    end else if (master_read_req[calc_next_master]) begin
                        arb_state_next = ARB_READ;
                    end
                end
            end
            
            ARB_WRITE: begin
                if (!slave_valid) begin
                    arb_state_next = ARB_ERROR;
                end else if (s_awready[current_slave] && s_wready[current_slave]) begin
                    arb_state_next = ARB_WRITE_RESP;
                end else if (timeout) begin
                    arb_state_next = ARB_ERROR;
                end
            end
            
            ARB_WRITE_RESP: begin
                if (s_bvalid[current_slave]) begin
                    arb_state_next = ARB_IDLE;
                end else if (timeout) begin
                    arb_state_next = ARB_ERROR;
                end
            end
            
            ARB_READ: begin
                if (!slave_valid) begin
                    arb_state_next = ARB_ERROR;
                end else if (s_arready[current_slave]) begin
                    arb_state_next = ARB_READ_RESP;
                end else if (timeout) begin
                    arb_state_next = ARB_ERROR;
                end
            end
            
            ARB_READ_RESP: begin
                if (s_rvalid[current_slave]) begin
                    arb_state_next = ARB_IDLE;
                end else if (timeout) begin
                    arb_state_next = ARB_ERROR;
                end
            end
            
            ARB_ERROR: begin
                // Return error response to master
                if (latched_is_write) begin
                    if (m_bready[current_master]) begin
                        arb_state_next = ARB_IDLE;
                    end
                end else begin
                    if (m_rready[current_master]) begin
                        arb_state_next = ARB_IDLE;
                    end
                end
            end
            
            default: arb_state_next = ARB_IDLE;
        endcase
    end

    //=========================================================================
    // Master Selection and Transaction Latching
    //=========================================================================
    
    // Combinational next master calculation
    wire [$clog2(NUM_MASTERS)-1:0] calc_next_master;
    assign calc_next_master = find_next_master(last_granted, master_any_req);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_master <= 0;
            last_granted <= 0;
            current_slave <= 0;
            slave_valid <= 1'b0;
            latched_addr <= {ADDR_WIDTH{1'b0}};
            latched_wdata <= {DATA_WIDTH{1'b0}};
            latched_wstrb <= {(DATA_WIDTH/8){1'b0}};
            latched_prot <= 3'b0;
            latched_is_write <= 1'b0;
        end else begin
            case (arb_state)
                ARB_IDLE: begin
                    if (|master_any_req) begin
                        // Select next master using round-robin
                        current_master <= calc_next_master;
                        last_granted <= calc_next_master;
                        
                        // Determine if write or read
                        if (master_write_req[calc_next_master]) begin
                            latched_is_write <= 1'b1;
                            latched_addr <= m_awaddr[calc_next_master*ADDR_WIDTH +: ADDR_WIDTH];
                            latched_wdata <= m_wdata[calc_next_master*DATA_WIDTH +: DATA_WIDTH];
                            latched_wstrb <= m_wstrb[calc_next_master*(DATA_WIDTH/8) +: (DATA_WIDTH/8)];
                            latched_prot <= m_awprot[calc_next_master*3 +: 3];
                        end else begin
                            latched_is_write <= 1'b0;
                            latched_addr <= m_araddr[calc_next_master*ADDR_WIDTH +: ADDR_WIDTH];
                            latched_prot <= m_arprot[calc_next_master*3 +: 3];
                        end
                        
                        // Decode address to select slave
                        if (master_write_req[calc_next_master]) begin
                            current_slave <= decode_address(m_awaddr[calc_next_master*ADDR_WIDTH +: ADDR_WIDTH]);
                            slave_valid <= (decode_address(m_awaddr[calc_next_master*ADDR_WIDTH +: ADDR_WIDTH]) < NUM_SLAVES);
                        end else begin
                            current_slave <= decode_address(m_araddr[calc_next_master*ADDR_WIDTH +: ADDR_WIDTH]);
                            slave_valid <= (decode_address(m_araddr[calc_next_master*ADDR_WIDTH +: ADDR_WIDTH]) < NUM_SLAVES);
                        end
                    end
                end
                
                ARB_WRITE_RESP: begin
                    if (s_bvalid[current_slave]) begin
                        resp_code <= s_bresp[current_slave*2 +: 2];
                    end
                end
                
                ARB_READ_RESP: begin
                    if (s_rvalid[current_slave]) begin
                        resp_rdata <= s_rdata[current_slave*DATA_WIDTH +: DATA_WIDTH];
                        resp_code <= s_rresp[current_slave*2 +: 2];
                    end
                end
                
                default: ;
            endcase
        end
    end
    
    //=========================================================================
    // Response Handling
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_valid <= 1'b0;
            resp_rdata <= {DATA_WIDTH{1'b0}};
            resp_code <= RESP_OKAY;
        end else begin
            case (arb_state)
                ARB_WRITE_RESP: begin
                    if (s_bvalid[current_slave]) begin
                        resp_valid <= 1'b1;
                        resp_code <= s_bresp[current_slave*2 +: 2];
                    end
                end
                
                ARB_READ_RESP: begin
                    if (s_rvalid[current_slave]) begin
                        resp_valid <= 1'b1;
                        resp_rdata <= s_rdata[current_slave*DATA_WIDTH +: DATA_WIDTH];
                        resp_code <= s_rresp[current_slave*2 +: 2];
                    end
                end
                
                ARB_ERROR: begin
                    resp_valid <= 1'b1;
                    resp_code <= RESP_DECERR;
                    resp_rdata <= {DATA_WIDTH{1'b0}};
                end
                
                ARB_IDLE: begin
                    resp_valid <= 1'b0;
                end
                
                default: ;
            endcase
        end
    end
    
    //=========================================================================
    // Master Port Output Generation
    //=========================================================================
    genvar mi;
    generate
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : gen_master_out
            // Write address ready - accept even for invalid addresses (will return error)
            assign m_awready[mi] = (arb_state == ARB_WRITE) && 
                                   (current_master == mi) && 
                                   (slave_valid ? s_awready[current_slave] : 1'b1);
            
            // Write data ready
            assign m_wready[mi] = (arb_state == ARB_WRITE) && 
                                  (current_master == mi) && 
                                  (slave_valid ? s_wready[current_slave] : 1'b1);
            
            // Write response valid
            assign m_bvalid[mi] = ((arb_state == ARB_WRITE_RESP && s_bvalid[current_slave]) ||
                                   (arb_state == ARB_ERROR && latched_is_write)) && 
                                  (current_master == mi);
            
            // Write response
            assign m_bresp[mi*2 +: 2] = (arb_state == ARB_ERROR) ? RESP_DECERR : 
                                        s_bresp[current_slave*2 +: 2];
            
            // Read address ready - accept even for invalid addresses (will return error)
            assign m_arready[mi] = (arb_state == ARB_READ) && 
                                   (current_master == mi) && 
                                   (slave_valid ? s_arready[current_slave] : 1'b1);
            
            // Read data valid
            assign m_rvalid[mi] = ((arb_state == ARB_READ_RESP && s_rvalid[current_slave]) ||
                                   (arb_state == ARB_ERROR && !latched_is_write)) && 
                                  (current_master == mi);
            
            // Read data
            assign m_rdata[mi*DATA_WIDTH +: DATA_WIDTH] = (arb_state == ARB_ERROR) ? 
                                                          {DATA_WIDTH{1'b0}} : 
                                                          s_rdata[current_slave*DATA_WIDTH +: DATA_WIDTH];
            
            // Read response
            assign m_rresp[mi*2 +: 2] = (arb_state == ARB_ERROR) ? RESP_DECERR : 
                                        s_rresp[current_slave*2 +: 2];
        end
    endgenerate
    
    //=========================================================================
    // Slave Port Output Generation
    //=========================================================================
    genvar si;
    generate
        for (si = 0; si < NUM_SLAVES; si = si + 1) begin : gen_slave_out
            // Write address valid
            assign s_awvalid[si] = (arb_state == ARB_WRITE) && 
                                   (current_slave == si) && 
                                   slave_valid;
            
            // Write address
            assign s_awaddr[si*ADDR_WIDTH +: ADDR_WIDTH] = latched_addr;
            
            // Write address protection
            assign s_awprot[si*3 +: 3] = latched_prot;
            
            // Write data valid
            assign s_wvalid[si] = (arb_state == ARB_WRITE) && 
                                  (current_slave == si) && 
                                  slave_valid;
            
            // Write data
            assign s_wdata[si*DATA_WIDTH +: DATA_WIDTH] = latched_wdata;
            
            // Write strobe
            assign s_wstrb[si*(DATA_WIDTH/8) +: (DATA_WIDTH/8)] = latched_wstrb;
            
            // Write response ready
            assign s_bready[si] = (arb_state == ARB_WRITE_RESP) && 
                                  (current_slave == si) && 
                                  m_bready[current_master];
            
            // Read address valid
            assign s_arvalid[si] = (arb_state == ARB_READ) && 
                                   (current_slave == si) && 
                                   slave_valid;
            
            // Read address
            assign s_araddr[si*ADDR_WIDTH +: ADDR_WIDTH] = latched_addr;
            
            // Read address protection
            assign s_arprot[si*3 +: 3] = latched_prot;
            
            // Read data ready
            assign s_rready[si] = (arb_state == ARB_READ_RESP) && 
                                  (current_slave == si) && 
                                  m_rready[current_master];
        end
    endgenerate

endmodule
