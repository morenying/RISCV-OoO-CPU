//=================================================================
// Module: axi_master_dbus
// Description: AXI4-Lite Master Interface for Data Bus
//              Read and Write channels
//              Supports burst transfer for cache line fill/writeback
// Requirements: 13.2, 13.3, 13.4, 13.5
//=================================================================

`timescale 1ns/1ps

module axi_master_dbus #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter CACHE_LINE_SIZE = 32  // 32 bytes = 8 words
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    //=========================================================
    // Cache Interface
    //=========================================================
    input  wire                    cache_req_valid_i,
    output wire                    cache_req_ready_o,
    input  wire                    cache_req_write_i,
    input  wire [ADDR_WIDTH-1:0]   cache_req_addr_i,
    input  wire [DATA_WIDTH-1:0]   cache_req_wdata_i,
    input  wire [3:0]              cache_req_wstrb_i,
    input  wire                    cache_req_burst_i,  // 1 = cache line transfer
    
    output wire                    cache_resp_valid_o,
    output wire [DATA_WIDTH-1:0]   cache_resp_data_o,
    output wire                    cache_resp_last_o,
    output wire                    cache_resp_error_o,
    
    // Burst write data interface
    input  wire                    cache_wdata_valid_i,
    output wire                    cache_wdata_ready_o,
    input  wire [DATA_WIDTH-1:0]   cache_wdata_i,
    input  wire                    cache_wdata_last_i,
    
    //=========================================================
    // AXI4-Lite Write Address Channel
    //=========================================================
    output reg                     m_axi_awvalid,
    input  wire                    m_axi_awready,
    output reg  [ADDR_WIDTH-1:0]   m_axi_awaddr,
    output wire [2:0]              m_axi_awprot,
    
    //=========================================================
    // AXI4-Lite Write Data Channel
    //=========================================================
    output reg                     m_axi_wvalid,
    input  wire                    m_axi_wready,
    output reg  [DATA_WIDTH-1:0]   m_axi_wdata,
    output reg  [3:0]              m_axi_wstrb,
    
    //=========================================================
    // AXI4-Lite Write Response Channel
    //=========================================================
    input  wire                    m_axi_bvalid,
    output reg                     m_axi_bready,
    input  wire [1:0]              m_axi_bresp,
    
    //=========================================================
    // AXI4-Lite Read Address Channel
    //=========================================================
    output reg                     m_axi_arvalid,
    input  wire                    m_axi_arready,
    output reg  [ADDR_WIDTH-1:0]   m_axi_araddr,
    output wire [2:0]              m_axi_arprot,
    
    //=========================================================
    // AXI4-Lite Read Data Channel
    //=========================================================
    input  wire                    m_axi_rvalid,
    output reg                     m_axi_rready,
    input  wire [DATA_WIDTH-1:0]   m_axi_rdata,
    input  wire [1:0]              m_axi_rresp
);

    // AXI protection: unprivileged, secure, data
    assign m_axi_awprot = 3'b000;
    assign m_axi_arprot = 3'b000;
    
    // Number of words in cache line
    localparam BURST_LEN = CACHE_LINE_SIZE / (DATA_WIDTH / 8);  // 8 words
    localparam BURST_CNT_WIDTH = $clog2(BURST_LEN);
    
    //=========================================================
    // State Machine
    //=========================================================
    localparam IDLE       = 3'b000;
    localparam RD_ADDR    = 3'b001;
    localparam RD_DATA    = 3'b010;
    localparam WR_ADDR    = 3'b011;
    localparam WR_DATA    = 3'b100;
    localparam WR_RESP    = 3'b101;
    
    reg [2:0] state;
    reg [BURST_CNT_WIDTH:0] burst_cnt;
    reg burst_mode;
    reg is_write;
    reg [ADDR_WIDTH-1:0] base_addr;
    reg [3:0] saved_wstrb;
    reg resp_error;
    
    //=========================================================
    // Output Signals
    //=========================================================
    assign cache_req_ready_o = (state == IDLE);
    assign cache_resp_valid_o = ((state == RD_DATA) && m_axi_rvalid) ||
                                ((state == WR_RESP) && m_axi_bvalid);
    assign cache_resp_data_o = m_axi_rdata;
    assign cache_resp_last_o = cache_resp_valid_o && 
                               (!burst_mode || (burst_cnt == BURST_LEN - 1));
    assign cache_resp_error_o = resp_error || 
                                ((state == RD_DATA) && m_axi_rvalid && (m_axi_rresp != 2'b00)) ||
                                ((state == WR_RESP) && m_axi_bvalid && (m_axi_bresp != 2'b00));
    
    assign cache_wdata_ready_o = (state == WR_DATA) && m_axi_wready;
    
    //=========================================================
    // State Machine Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            m_axi_arvalid <= 1'b0;
            m_axi_araddr <= 0;
            m_axi_rready <= 1'b0;
            m_axi_awvalid <= 1'b0;
            m_axi_awaddr <= 0;
            m_axi_wvalid <= 1'b0;
            m_axi_wdata <= 0;
            m_axi_wstrb <= 0;
            m_axi_bready <= 1'b0;
            burst_cnt <= 0;
            burst_mode <= 0;
            is_write <= 0;
            base_addr <= 0;
            saved_wstrb <= 0;
            resp_error <= 0;
        end else begin
            case (state)
                IDLE: begin
                    resp_error <= 1'b0;
                    if (cache_req_valid_i) begin
                        burst_mode <= cache_req_burst_i;
                        base_addr <= cache_req_addr_i;
                        burst_cnt <= 0;
                        is_write <= cache_req_write_i;
                        saved_wstrb <= cache_req_wstrb_i;
                        
                        if (cache_req_write_i) begin
                            state <= WR_ADDR;
                            m_axi_awvalid <= 1'b1;
                            m_axi_awaddr <= cache_req_addr_i;
                            m_axi_wdata <= cache_req_wdata_i;
                            m_axi_wstrb <= cache_req_wstrb_i;
                        end else begin
                            state <= RD_ADDR;
                            m_axi_arvalid <= 1'b1;
                            m_axi_araddr <= cache_req_addr_i;
                        end
                    end
                end
                
                //=================================================
                // Read Path
                //=================================================
                RD_ADDR: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready <= 1'b1;
                        state <= RD_DATA;
                    end
                end
                
                RD_DATA: begin
                    if (m_axi_rvalid) begin
                        if (m_axi_rresp != 2'b00) begin
                            resp_error <= 1'b1;
                        end
                        
                        if (burst_mode && burst_cnt < BURST_LEN - 1) begin
                            burst_cnt <= burst_cnt + 1;
                            m_axi_rready <= 1'b0;
                            m_axi_arvalid <= 1'b1;
                            m_axi_araddr <= base_addr + ((burst_cnt + 1) << 2);
                            state <= RD_ADDR;
                        end else begin
                            m_axi_rready <= 1'b0;
                            state <= IDLE;
                        end
                    end
                end
                
                //=================================================
                // Write Path
                //=================================================
                WR_ADDR: begin
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid <= 1'b1;
                        state <= WR_DATA;
                    end
                end
                
                WR_DATA: begin
                    if (m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_bready <= 1'b1;
                        state <= WR_RESP;
                    end
                end
                
                WR_RESP: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        
                        if (m_axi_bresp != 2'b00) begin
                            resp_error <= 1'b1;
                        end
                        
                        if (burst_mode && burst_cnt < BURST_LEN - 1) begin
                            burst_cnt <= burst_cnt + 1;
                            m_axi_awvalid <= 1'b1;
                            m_axi_awaddr <= base_addr + ((burst_cnt + 1) << 2);
                            // Get next write data from cache
                            if (cache_wdata_valid_i) begin
                                m_axi_wdata <= cache_wdata_i;
                            end
                            m_axi_wstrb <= 4'b1111;  // Full word for burst
                            state <= WR_ADDR;
                        end else begin
                            state <= IDLE;
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
