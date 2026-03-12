//=================================================================
// Module: plic
// Description: Platform-Level Interrupt Controller (PLIC)
//              Routes external device interrupts to harts
//              Supports priority, enable, claim/complete
// Requirements: Linux requires PLIC for device interrupts
//=================================================================

`timescale 1ns/1ps

module plic #(
    parameter ADDR_WIDTH     = 32,
    parameter DATA_WIDTH     = 32,
    parameter NUM_SOURCES    = 32,        // Number of interrupt sources
    parameter NUM_TARGETS    = 2,         // Number of targets (M + S per hart)
    parameter NUM_PRIORITIES = 8,         // Priority levels (3 bits)
    parameter BASE_ADDR      = 32'h0C00_0000  // PLIC base address
)(
    input  wire                         clk,
    input  wire                         rst_n,
    
    //=========================================================
    // Interrupt Sources (directly from devices)
    //=========================================================
    input  wire [NUM_SOURCES-1:0]       irq_sources_i,
    
    //=========================================================
    // Memory-mapped Interface
    //=========================================================
    input  wire                         req_valid_i,
    input  wire                         req_we_i,
    input  wire [ADDR_WIDTH-1:0]        req_addr_i,
    input  wire [DATA_WIDTH-1:0]        req_wdata_i,
    output reg                          req_ready_o,
    
    output reg                          resp_valid_o,
    output reg  [DATA_WIDTH-1:0]        resp_data_o,
    
    //=========================================================
    // Interrupt Outputs (to targets)
    //=========================================================
    output wire [NUM_TARGETS-1:0]       irq_o         // Interrupt to each target
);

    //=========================================================
    // Address Map (relative to BASE_ADDR)
    // 0x000000 - 0x000FFF: Priority registers (4 bytes per source)
    // 0x001000 - 0x001FFF: Pending bits
    // 0x002000 - 0x1FFFFF: Enable bits per target
    // 0x200000 - 0x3FFFFF: Priority threshold and claim/complete per target
    //=========================================================
    localparam PRIORITY_BASE   = 24'h000000;
    localparam PENDING_BASE    = 24'h001000;
    localparam ENABLE_BASE     = 24'h002000;
    localparam CONTEXT_BASE    = 24'h200000;
    
    // Context stride
    localparam ENABLE_STRIDE   = 24'h000080;  // 128 bytes per target
    localparam CONTEXT_STRIDE  = 24'h001000;  // 4KB per target
    
    //=========================================================
    // Registers
    //=========================================================
    // Priority for each source (0 = disabled, 1-7 = priority)
    reg [2:0] priority_reg [0:NUM_SOURCES-1];
    
    // Pending bits (read-only, set by gateway, cleared by claim)
    reg [NUM_SOURCES-1:0] pending;
    
    // Enable bits per target
    reg [NUM_SOURCES-1:0] enable [0:NUM_TARGETS-1];
    
    // Priority threshold per target
    reg [2:0] threshold [0:NUM_TARGETS-1];
    
    // Claimed interrupt per target
    reg [5:0] claimed [0:NUM_TARGETS-1];  // Source ID being serviced
    reg [NUM_TARGETS-1:0] claim_active;
    
    //=========================================================
    // Edge Detection for Interrupt Sources
    //=========================================================
    reg [NUM_SOURCES-1:0] irq_prev;
    wire [NUM_SOURCES-1:0] irq_edge = irq_sources_i & ~irq_prev;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_prev <= 0;
        end else begin
            irq_prev <= irq_sources_i;
        end
    end
    
    //=========================================================
    // Pending Bit Update (Gateway)
    //=========================================================
    integer s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending <= 0;
        end else begin
            for (s = 1; s < NUM_SOURCES; s = s + 1) begin
                // Set on rising edge, clear on claim
                if (irq_edge[s]) begin
                    pending[s] <= 1'b1;
                end
            end
        end
    end
    
    //=========================================================
    // Interrupt Arbitration per Target
    //=========================================================
    reg [5:0]  max_id      [0:NUM_TARGETS-1];
    reg [2:0]  max_pri     [0:NUM_TARGETS-1];
    reg        has_pending [0:NUM_TARGETS-1];
    
    integer t, src;
    always @(*) begin
        for (t = 0; t < NUM_TARGETS; t = t + 1) begin
            max_id[t] = 0;
            max_pri[t] = 0;
            has_pending[t] = 0;
            
            for (src = 1; src < NUM_SOURCES; src = src + 1) begin
                if (pending[src] && enable[t][src] && 
                    (priority_reg[src] > threshold[t]) &&
                    (priority_reg[src] > max_pri[t])) begin
                    max_id[t] = src[5:0];
                    max_pri[t] = priority_reg[src];
                    has_pending[t] = 1;
                end
            end
        end
    end
    
    //=========================================================
    // Interrupt Output
    //=========================================================
    genvar tg;
    generate
        for (tg = 0; tg < NUM_TARGETS; tg = tg + 1) begin : gen_irq
            assign irq_o[tg] = has_pending[tg];
        end
    endgenerate
    
    //=========================================================
    // Address Decoding
    //=========================================================
    wire [ADDR_WIDTH-1:0] offset = req_addr_i - BASE_ADDR;
    wire [23:0] reg_offset = offset[23:0];
    
    wire is_priority = (reg_offset < PENDING_BASE);
    wire is_pending = (reg_offset >= PENDING_BASE) && (reg_offset < ENABLE_BASE);
    wire is_enable = (reg_offset >= ENABLE_BASE) && (reg_offset < CONTEXT_BASE);
    wire is_context = (reg_offset >= CONTEXT_BASE);
    
    // Extract indices
    wire [5:0] priority_src = reg_offset[7:2];
    wire [4:0] pending_word = reg_offset[6:2];
    wire [3:0] enable_target = (reg_offset - ENABLE_BASE) / ENABLE_STRIDE;
    wire [4:0] enable_word = ((reg_offset - ENABLE_BASE) % ENABLE_STRIDE) >> 2;
    wire [3:0] context_target = (reg_offset - CONTEXT_BASE) / CONTEXT_STRIDE;
    wire [11:0] context_offset = (reg_offset - CONTEXT_BASE) % CONTEXT_STRIDE;
    
    //=========================================================
    // Read/Write Logic
    //=========================================================
    integer i, j;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_ready_o <= 0;
            resp_valid_o <= 0;
            resp_data_o <= 0;
            claim_active <= 0;
            
            for (i = 0; i < NUM_SOURCES; i = i + 1) begin
                priority_reg[i] <= 0;
            end
            
            for (i = 0; i < NUM_TARGETS; i = i + 1) begin
                enable[i] <= 0;
                threshold[i] <= 0;
                claimed[i] <= 0;
            end
        end else begin
            req_ready_o <= req_valid_i;
            resp_valid_o <= req_valid_i;
            
            if (req_valid_i) begin
                if (req_we_i) begin
                    // Write
                    if (is_priority) begin
                        if (priority_src < NUM_SOURCES) begin
                            priority_reg[priority_src] <= req_wdata_i[2:0];
                        end
                    end else if (is_enable) begin
                        if (enable_target < NUM_TARGETS) begin
                            // Write enable bits (32 sources per word)
                            for (j = 0; j < 32; j = j + 1) begin
                                if ((enable_word * 32 + j) < NUM_SOURCES) begin
                                    enable[enable_target][enable_word * 32 + j] <= req_wdata_i[j];
                                end
                            end
                        end
                    end else if (is_context) begin
                        if (context_target < NUM_TARGETS) begin
                            if (context_offset == 12'h000) begin
                                // Priority threshold
                                threshold[context_target] <= req_wdata_i[2:0];
                            end else if (context_offset == 12'h004) begin
                                // Claim/Complete write = complete
                                if (claim_active[context_target] && 
                                    (req_wdata_i[5:0] == claimed[context_target])) begin
                                    claim_active[context_target] <= 0;
                                    // Re-enable gateway for this source
                                end
                            end
                        end
                    end
                    
                    resp_data_o <= 0;
                end else begin
                    // Read
                    resp_data_o <= 0;
                    
                    if (is_priority) begin
                        if (priority_src < NUM_SOURCES) begin
                            resp_data_o <= {29'b0, priority_reg[priority_src]};
                        end
                    end else if (is_pending) begin
                        // Read pending bits (32 per word)
                        for (j = 0; j < 32; j = j + 1) begin
                            if ((pending_word * 32 + j) < NUM_SOURCES) begin
                                resp_data_o[j] <= pending[pending_word * 32 + j];
                            end
                        end
                    end else if (is_enable) begin
                        if (enable_target < NUM_TARGETS) begin
                            for (j = 0; j < 32; j = j + 1) begin
                                if ((enable_word * 32 + j) < NUM_SOURCES) begin
                                    resp_data_o[j] <= enable[enable_target][enable_word * 32 + j];
                                end
                            end
                        end
                    end else if (is_context) begin
                        if (context_target < NUM_TARGETS) begin
                            if (context_offset == 12'h000) begin
                                resp_data_o <= {29'b0, threshold[context_target]};
                            end else if (context_offset == 12'h004) begin
                                // Claim read
                                resp_data_o <= {26'b0, max_id[context_target]};
                                
                                // Side effect: claim the interrupt
                                if (has_pending[context_target]) begin
                                    claimed[context_target] <= max_id[context_target];
                                    claim_active[context_target] <= 1;
                                    pending[max_id[context_target]] <= 0;
                                end
                            end
                        end
                    end
                end
            end else begin
                resp_valid_o <= 0;
            end
        end
    end

endmodule
