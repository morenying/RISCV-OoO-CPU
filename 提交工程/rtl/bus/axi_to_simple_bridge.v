//=============================================================================
// Module: axi_to_simple_bridge
// Description: AXI4-Lite to Simple Memory Interface Bridge
//              Converts AXI4-Lite transactions to simple req/ack handshake
//
// Requirements: 2.1
//=============================================================================

`timescale 1ns/1ps

module axi_to_simple_bridge (
    input  wire        clk,
    input  wire        rst_n,
    
    //=========================================================================
    // AXI4-Lite Slave Interface
    //=========================================================================
    input  wire        axi_awvalid,
    output reg         axi_awready,
    input  wire [31:0] axi_awaddr,
    
    input  wire        axi_wvalid,
    output reg         axi_wready,
    input  wire [31:0] axi_wdata,
    input  wire [3:0]  axi_wstrb,
    
    output reg         axi_bvalid,
    input  wire        axi_bready,
    output reg  [1:0]  axi_bresp,
    
    input  wire        axi_arvalid,
    output reg         axi_arready,
    input  wire [31:0] axi_araddr,
    
    output reg         axi_rvalid,
    input  wire        axi_rready,
    output reg  [31:0] axi_rdata,
    output reg  [1:0]  axi_rresp,
    
    //=========================================================================
    // Simple Memory Interface
    //=========================================================================
    output reg         req,
    input  wire        ack,
    input  wire        done,
    output reg         wr,
    output reg  [31:0] addr,
    output reg  [31:0] wdata,
    output reg  [3:0]  be,
    input  wire [31:0] rdata,
    input  wire        error
);

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [2:0]
        ST_IDLE       = 3'd0,
        ST_WRITE_REQ  = 3'd1,
        ST_WRITE_WAIT = 3'd2,
        ST_WRITE_RESP = 3'd3,
        ST_READ_REQ   = 3'd4,
        ST_READ_WAIT  = 3'd5,
        ST_READ_RESP  = 3'd6;
    
    reg [2:0] state, next_state;
    
    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [31:0] addr_reg;
    reg [31:0] wdata_reg;
    reg [3:0]  be_reg;
    reg [31:0] rdata_reg;
    reg        error_reg;
    
    //=========================================================================
    // State Machine - Sequential
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    //=========================================================================
    // State Machine - Combinational
    //=========================================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            ST_IDLE: begin
                if (axi_awvalid && axi_wvalid) begin
                    next_state = ST_WRITE_REQ;
                end else if (axi_arvalid) begin
                    next_state = ST_READ_REQ;
                end
            end
            
            ST_WRITE_REQ: begin
                if (ack) begin
                    next_state = ST_WRITE_WAIT;
                end
            end
            
            ST_WRITE_WAIT: begin
                if (done) begin
                    next_state = ST_WRITE_RESP;
                end
            end
            
            ST_WRITE_RESP: begin
                if (axi_bready) begin
                    next_state = ST_IDLE;
                end
            end
            
            ST_READ_REQ: begin
                if (ack) begin
                    next_state = ST_READ_WAIT;
                end
            end
            
            ST_READ_WAIT: begin
                if (done) begin
                    next_state = ST_READ_RESP;
                end
            end
            
            ST_READ_RESP: begin
                if (axi_rready) begin
                    next_state = ST_IDLE;
                end
            end
            
            default: next_state = ST_IDLE;
        endcase
    end
    
    //=========================================================================
    // Data Path
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_reg  <= 32'h0;
            wdata_reg <= 32'h0;
            be_reg    <= 4'h0;
            rdata_reg <= 32'h0;
            error_reg <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (axi_awvalid && axi_wvalid) begin
                        addr_reg  <= axi_awaddr;
                        wdata_reg <= axi_wdata;
                        be_reg    <= axi_wstrb;
                    end else if (axi_arvalid) begin
                        addr_reg <= axi_araddr;
                        be_reg   <= 4'hF;  // Full word read
                    end
                end
                
                ST_WRITE_WAIT, ST_READ_WAIT: begin
                    if (done) begin
                        rdata_reg <= rdata;
                        error_reg <= error;
                    end
                end
                
                default: ;
            endcase
        end
    end
    
    //=========================================================================
    // Output Logic
    //=========================================================================
    always @(*) begin
        // Defaults
        axi_awready = 1'b0;
        axi_wready  = 1'b0;
        axi_bvalid  = 1'b0;
        axi_bresp   = 2'b00;
        axi_arready = 1'b0;
        axi_rvalid  = 1'b0;
        axi_rdata   = 32'h0;
        axi_rresp   = 2'b00;
        req         = 1'b0;
        wr          = 1'b0;
        addr        = addr_reg;
        wdata       = wdata_reg;
        be          = be_reg;
        
        case (state)
            ST_IDLE: begin
                axi_awready = 1'b1;
                axi_wready  = 1'b1;
                axi_arready = 1'b1;
            end
            
            ST_WRITE_REQ: begin
                req   = 1'b1;
                wr    = 1'b1;
                addr  = addr_reg;
                wdata = wdata_reg;
                be    = be_reg;
            end
            
            ST_WRITE_WAIT: begin
                // Wait for done
            end
            
            ST_WRITE_RESP: begin
                axi_bvalid = 1'b1;
                axi_bresp  = error_reg ? 2'b10 : 2'b00;  // SLVERR or OKAY
            end
            
            ST_READ_REQ: begin
                req  = 1'b1;
                wr   = 1'b0;
                addr = addr_reg;
                be   = 4'hF;
            end
            
            ST_READ_WAIT: begin
                // Wait for done
            end
            
            ST_READ_RESP: begin
                axi_rvalid = 1'b1;
                axi_rdata  = rdata_reg;
                axi_rresp  = error_reg ? 2'b10 : 2'b00;  // SLVERR or OKAY
            end
            
            default: ;
        endcase
    end

endmodule
