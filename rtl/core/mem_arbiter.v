//=================================================================
// Module: mem_arbiter
// Description: Memory Arbiter for AXI Bus
//              Arbitrates between I-Cache, D-Cache, and PTW
//              Priority: PTW > D-Cache > I-Cache (for TLB miss handling)
//=================================================================

`timescale 1ns/1ps

module mem_arbiter #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter LINE_WIDTH = 128         // Cache line width
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // I-Cache Interface
    //=========================================================
    input  wire                     icache_req_valid_i,
    output wire                     icache_req_ready_o,
    input  wire [ADDR_WIDTH-1:0]    icache_req_addr_i,
    output wire                     icache_resp_valid_o,
    output wire [LINE_WIDTH-1:0]    icache_resp_data_o,
    
    //=========================================================
    // D-Cache Interface
    //=========================================================
    input  wire                     dcache_req_valid_i,
    output wire                     dcache_req_ready_o,
    input  wire [ADDR_WIDTH-1:0]    dcache_req_addr_i,
    input  wire                     dcache_req_write_i,
    input  wire [LINE_WIDTH-1:0]    dcache_req_wdata_i,
    output wire                     dcache_resp_valid_o,
    output wire [LINE_WIDTH-1:0]    dcache_resp_data_o,
    
    //=========================================================
    // PTW Interface
    //=========================================================
    input  wire                     ptw_req_valid_i,
    output wire                     ptw_req_ready_o,
    input  wire [ADDR_WIDTH-1:0]    ptw_req_addr_i,
    output wire                     ptw_resp_valid_o,
    output wire [DATA_WIDTH-1:0]    ptw_resp_data_o,
    
    //=========================================================
    // AXI4 Master Interface
    //=========================================================
    // AXI Write Address Channel
    output reg  [3:0]               m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output reg  [7:0]               m_axi_awlen,
    output reg  [2:0]               m_axi_awsize,
    output reg  [1:0]               m_axi_awburst,
    output reg                      m_axi_awvalid,
    input  wire                     m_axi_awready,
    
    // AXI Write Data Channel
    output reg  [DATA_WIDTH-1:0]    m_axi_wdata,
    output reg  [DATA_WIDTH/8-1:0]  m_axi_wstrb,
    output reg                      m_axi_wlast,
    output reg                      m_axi_wvalid,
    input  wire                     m_axi_wready,
    
    // AXI Write Response Channel
    input  wire [3:0]               m_axi_bid,
    input  wire [1:0]               m_axi_bresp,
    input  wire                     m_axi_bvalid,
    output reg                      m_axi_bready,
    
    // AXI Read Address Channel
    output reg  [3:0]               m_axi_arid,
    output reg  [ADDR_WIDTH-1:0]    m_axi_araddr,
    output reg  [7:0]               m_axi_arlen,
    output reg  [2:0]               m_axi_arsize,
    output reg  [1:0]               m_axi_arburst,
    output reg                      m_axi_arvalid,
    input  wire                     m_axi_arready,
    
    // AXI Read Data Channel
    input  wire [3:0]               m_axi_rid,
    input  wire [DATA_WIDTH-1:0]    m_axi_rdata,
    input  wire [1:0]               m_axi_rresp,
    input  wire                     m_axi_rlast,
    input  wire                     m_axi_rvalid,
    output reg                      m_axi_rready
);

    //=========================================================
    // Request IDs
    //=========================================================
    localparam ID_ICACHE = 4'd0;
    localparam ID_DCACHE = 4'd1;
    localparam ID_PTW    = 4'd2;
    
    //=========================================================
    // State Machine
    //=========================================================
    localparam S_IDLE       = 3'd0;
    localparam S_ADDR       = 3'd1;
    localparam S_READ       = 3'd2;
    localparam S_WRITE      = 3'd3;
    localparam S_WRESP      = 3'd4;
    
    reg [2:0] state;
    
    //=========================================================
    // Request Selection
    //=========================================================
    reg [1:0] selected_req;    // 0: I-Cache, 1: D-Cache, 2: PTW
    reg       selected_write;
    reg [ADDR_WIDTH-1:0] selected_addr;
    reg [LINE_WIDTH-1:0] selected_wdata;
    
    // Priority: PTW > D-Cache > I-Cache
    wire select_ptw    = ptw_req_valid_i;
    wire select_dcache = dcache_req_valid_i && !select_ptw;
    wire select_icache = icache_req_valid_i && !select_ptw && !select_dcache;
    
    //=========================================================
    // Response Data Accumulation
    //=========================================================
    reg [LINE_WIDTH-1:0] read_data_acc;
    reg [1:0] beat_count;
    localparam BEATS = LINE_WIDTH / DATA_WIDTH;  // 4 beats for 128-bit line
    
    //=========================================================
    // Ready Signals
    //=========================================================
    assign icache_req_ready_o = (state == S_IDLE) && select_icache;
    assign dcache_req_ready_o = (state == S_IDLE) && select_dcache;
    assign ptw_req_ready_o    = (state == S_IDLE) && select_ptw;
    
    //=========================================================
    // Response Valid Signals
    //=========================================================
    reg icache_resp_valid_r, dcache_resp_valid_r, ptw_resp_valid_r;
    reg [LINE_WIDTH-1:0] icache_resp_data_r, dcache_resp_data_r;
    reg [DATA_WIDTH-1:0] ptw_resp_data_r;
    
    assign icache_resp_valid_o = icache_resp_valid_r;
    assign dcache_resp_valid_o = dcache_resp_valid_r;
    assign ptw_resp_valid_o    = ptw_resp_valid_r;
    
    assign icache_resp_data_o = icache_resp_data_r;
    assign dcache_resp_data_o = dcache_resp_data_r;
    assign ptw_resp_data_o    = ptw_resp_data_r;
    
    //=========================================================
    // State Machine
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            selected_req <= 0;
            selected_write <= 0;
            selected_addr <= 0;
            selected_wdata <= 0;
            read_data_acc <= 0;
            beat_count <= 0;
            
            m_axi_awid <= 0;
            m_axi_awaddr <= 0;
            m_axi_awlen <= 0;
            m_axi_awsize <= 0;
            m_axi_awburst <= 0;
            m_axi_awvalid <= 0;
            
            m_axi_wdata <= 0;
            m_axi_wstrb <= 0;
            m_axi_wlast <= 0;
            m_axi_wvalid <= 0;
            
            m_axi_bready <= 1;
            
            m_axi_arid <= 0;
            m_axi_araddr <= 0;
            m_axi_arlen <= 0;
            m_axi_arsize <= 0;
            m_axi_arburst <= 0;
            m_axi_arvalid <= 0;
            
            m_axi_rready <= 1;
            
            icache_resp_valid_r <= 0;
            dcache_resp_valid_r <= 0;
            ptw_resp_valid_r <= 0;
        end else begin
            // Default: clear response valids
            icache_resp_valid_r <= 0;
            dcache_resp_valid_r <= 0;
            ptw_resp_valid_r <= 0;
            
            case (state)
                S_IDLE: begin
                    if (select_ptw) begin
                        selected_req <= 2'd2;
                        selected_write <= 1'b0;
                        selected_addr <= ptw_req_addr_i;
                        state <= S_ADDR;
                        
                        // PTW: single word read
                        m_axi_arid <= ID_PTW;
                        m_axi_araddr <= ptw_req_addr_i;
                        m_axi_arlen <= 8'd0;      // 1 beat
                        m_axi_arsize <= 3'b010;   // 4 bytes
                        m_axi_arburst <= 2'b00;   // FIXED
                        m_axi_arvalid <= 1;
                        beat_count <= 0;
                    end else if (select_dcache) begin
                        selected_req <= 2'd1;
                        selected_write <= dcache_req_write_i;
                        selected_addr <= dcache_req_addr_i;
                        selected_wdata <= dcache_req_wdata_i;
                        state <= S_ADDR;
                        beat_count <= 0;
                        
                        if (dcache_req_write_i) begin
                            // D-Cache write: cache line write
                            m_axi_awid <= ID_DCACHE;
                            m_axi_awaddr <= dcache_req_addr_i;
                            m_axi_awlen <= BEATS - 1;    // 4 beats
                            m_axi_awsize <= 3'b010;      // 4 bytes
                            m_axi_awburst <= 2'b01;      // INCR
                            m_axi_awvalid <= 1;
                        end else begin
                            // D-Cache read: cache line read
                            m_axi_arid <= ID_DCACHE;
                            m_axi_araddr <= dcache_req_addr_i;
                            m_axi_arlen <= BEATS - 1;
                            m_axi_arsize <= 3'b010;
                            m_axi_arburst <= 2'b01;
                            m_axi_arvalid <= 1;
                        end
                    end else if (select_icache) begin
                        selected_req <= 2'd0;
                        selected_write <= 1'b0;
                        selected_addr <= icache_req_addr_i;
                        state <= S_ADDR;
                        beat_count <= 0;
                        
                        // I-Cache read: cache line read
                        m_axi_arid <= ID_ICACHE;
                        m_axi_araddr <= icache_req_addr_i;
                        m_axi_arlen <= BEATS - 1;
                        m_axi_arsize <= 3'b010;
                        m_axi_arburst <= 2'b01;
                        m_axi_arvalid <= 1;
                    end
                end
                
                S_ADDR: begin
                    // Wait for address acceptance
                    if (selected_write) begin
                        if (m_axi_awready) begin
                            m_axi_awvalid <= 0;
                            state <= S_WRITE;
                            
                            // Start write data
                            m_axi_wdata <= selected_wdata[31:0];
                            m_axi_wstrb <= 4'hF;
                            m_axi_wlast <= (beat_count == BEATS - 1);
                            m_axi_wvalid <= 1;
                        end
                    end else begin
                        if (m_axi_arready) begin
                            m_axi_arvalid <= 0;
                            state <= S_READ;
                        end
                    end
                end
                
                S_READ: begin
                    if (m_axi_rvalid) begin
                        // Accumulate read data
                        case (beat_count)
                            2'd0: read_data_acc[31:0]   <= m_axi_rdata;
                            2'd1: read_data_acc[63:32]  <= m_axi_rdata;
                            2'd2: read_data_acc[95:64]  <= m_axi_rdata;
                            2'd3: read_data_acc[127:96] <= m_axi_rdata;
                        endcase
                        
                        if (m_axi_rlast || selected_req == 2'd2) begin
                            // Read complete
                            state <= S_IDLE;
                            
                            // Generate response
                            case (selected_req)
                                2'd0: begin  // I-Cache
                                    icache_resp_valid_r <= 1;
                                    icache_resp_data_r <= {m_axi_rdata, read_data_acc[95:0]};
                                end
                                2'd1: begin  // D-Cache
                                    dcache_resp_valid_r <= 1;
                                    dcache_resp_data_r <= {m_axi_rdata, read_data_acc[95:0]};
                                end
                                2'd2: begin  // PTW
                                    ptw_resp_valid_r <= 1;
                                    ptw_resp_data_r <= m_axi_rdata;
                                end
                            endcase
                        end else begin
                            beat_count <= beat_count + 1;
                        end
                    end
                end
                
                S_WRITE: begin
                    if (m_axi_wready) begin
                        if (m_axi_wlast) begin
                            m_axi_wvalid <= 0;
                            state <= S_WRESP;
                        end else begin
                            beat_count <= beat_count + 1;
                            
                            // Next write data
                            case (beat_count + 1)
                                2'd1: m_axi_wdata <= selected_wdata[63:32];
                                2'd2: m_axi_wdata <= selected_wdata[95:64];
                                2'd3: m_axi_wdata <= selected_wdata[127:96];
                            endcase
                            m_axi_wlast <= (beat_count + 1 == BEATS - 1);
                        end
                    end
                end
                
                S_WRESP: begin
                    if (m_axi_bvalid) begin
                        // Write response received
                        state <= S_IDLE;
                        dcache_resp_valid_r <= 1;
                        dcache_resp_data_r <= 0;  // No data for write response
                    end
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
