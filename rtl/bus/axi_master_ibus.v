//=================================================================
// Module: axi_master_ibus
// Description: AXI4-Lite Master Interface for Instruction Bus
//              Read channel only
//              Supports burst transfer for cache line fill
// Requirements: 13.1, 13.3, 13.4
//=================================================================

`timescale 1ns/1ps

module axi_master_ibus #(
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
    input  wire [ADDR_WIDTH-1:0]   cache_req_addr_i,
    input  wire                    cache_req_burst_i,  // 1 = cache line fill
    
    output wire                    cache_resp_valid_o,
    output wire [DATA_WIDTH-1:0]   cache_resp_data_o,
    output wire                    cache_resp_last_o,
    output wire                    cache_resp_error_o,
    
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

    // AXI protection: unprivileged, secure, instruction
    assign m_axi_arprot = 3'b100;
    
    // Number of words in cache line
    localparam BURST_LEN = CACHE_LINE_SIZE / (DATA_WIDTH / 8);  // 8 words
    localparam BURST_CNT_WIDTH = $clog2(BURST_LEN);
    
    //=========================================================
    // State Machine
    //=========================================================
    localparam IDLE     = 2'b00;
    localparam ADDR     = 2'b01;
    localparam DATA     = 2'b10;
    
    reg [1:0] state;
    reg [BURST_CNT_WIDTH:0] burst_cnt;
    reg burst_mode;
    reg [ADDR_WIDTH-1:0] base_addr;
    reg resp_error;
    
    //=========================================================
    // Output Signals
    //=========================================================
    assign cache_req_ready_o = (state == IDLE);
    assign cache_resp_valid_o = (state == DATA) && m_axi_rvalid;
    assign cache_resp_data_o = m_axi_rdata;
    assign cache_resp_last_o = (state == DATA) && m_axi_rvalid && 
                               (!burst_mode || (burst_cnt == BURST_LEN - 1));
    assign cache_resp_error_o = resp_error || (m_axi_rresp != 2'b00);
    
    //=========================================================
    // State Machine Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            m_axi_arvalid <= 1'b0;
            m_axi_araddr <= 0;
            m_axi_rready <= 1'b0;
            burst_cnt <= 0;
            burst_mode <= 0;
            base_addr <= 0;
            resp_error <= 0;
        end else begin
            case (state)
                IDLE: begin
                    resp_error <= 1'b0;
                    if (cache_req_valid_i) begin
                        state <= ADDR;
                        m_axi_arvalid <= 1'b1;
                        m_axi_araddr <= cache_req_addr_i;
                        burst_mode <= cache_req_burst_i;
                        base_addr <= cache_req_addr_i;
                        burst_cnt <= 0;
                    end
                end
                
                ADDR: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready <= 1'b1;
                        state <= DATA;
                    end
                end
                
                DATA: begin
                    if (m_axi_rvalid) begin
                        // Check for error
                        if (m_axi_rresp != 2'b00) begin
                            resp_error <= 1'b1;
                        end
                        
                        if (burst_mode && burst_cnt < BURST_LEN - 1) begin
                            // More words to fetch
                            burst_cnt <= burst_cnt + 1;
                            m_axi_rready <= 1'b0;
                            m_axi_arvalid <= 1'b1;
                            m_axi_araddr <= base_addr + ((burst_cnt + 1) << 2);
                            state <= ADDR;
                        end else begin
                            // Transfer complete
                            m_axi_rready <= 1'b0;
                            state <= IDLE;
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
