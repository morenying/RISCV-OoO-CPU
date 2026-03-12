//=================================================================
// Module: ptw
// Description: Page Table Walker
//              Hardware page table traversal for Sv32
//              2-level page table (VPN[1] -> VPN[0] -> PTE)
//              Supports superpages (4MB)
// Requirements: Virtual Memory for Linux
//=================================================================

`timescale 1ns/1ps

module ptw #(
    parameter VADDR_WIDTH    = 32,
    parameter PADDR_WIDTH    = 34,
    parameter PPN_WIDTH      = 22,
    parameter VPN_WIDTH      = 10,
    parameter PTE_WIDTH      = 32,
    parameter ASID_WIDTH     = 9
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Request Interface (from TLB on miss)
    //=========================================================
    input  wire                     req_valid_i,
    input  wire [VADDR_WIDTH-1:0]   req_vaddr_i,
    input  wire [ASID_WIDTH-1:0]    req_asid_i,
    input  wire                     req_is_store_i,
    output wire                     req_ready_o,
    
    //=========================================================
    // Response Interface (to TLB for refill)
    //=========================================================
    output reg                      resp_valid_o,
    output reg  [VADDR_WIDTH-1:0]   resp_vaddr_o,
    output reg  [ASID_WIDTH-1:0]    resp_asid_o,
    output reg  [PPN_WIDTH-1:0]     resp_ppn_o,
    output reg                      resp_d_o,
    output reg                      resp_a_o,
    output reg                      resp_g_o,
    output reg                      resp_u_o,
    output reg                      resp_x_o,
    output reg                      resp_w_o,
    output reg                      resp_r_o,
    output reg                      resp_superpage_o,
    output reg                      resp_fault_o,
    output reg  [3:0]               resp_fault_type_o,
    
    //=========================================================
    // SATP Register Input
    //=========================================================
    input  wire [VADDR_WIDTH-1:0]   satp_i,           // SATP register value
    
    //=========================================================
    // Memory Interface (to D-Cache or Memory)
    //=========================================================
    output reg                      mem_req_valid_o,
    output reg  [PADDR_WIDTH-1:0]   mem_req_addr_o,
    input  wire                     mem_req_ready_i,
    
    input  wire                     mem_resp_valid_i,
    input  wire [PTE_WIDTH-1:0]     mem_resp_data_i
);

    //=========================================================
    // SATP Field Extraction
    //=========================================================
    wire        satp_mode = satp_i[31];                    // MODE (1=Sv32)
    wire [ASID_WIDTH-1:0] satp_asid = satp_i[30:22];      // ASID
    wire [PPN_WIDTH-1:0]  satp_ppn = satp_i[21:0];        // Root page table PPN
    
    //=========================================================
    // Virtual Address Decomposition
    //=========================================================
    wire [VPN_WIDTH-1:0] vpn1 = req_vaddr_i[31:22];       // VPN[1]
    wire [VPN_WIDTH-1:0] vpn0 = req_vaddr_i[21:12];       // VPN[0]
    wire [11:0] page_offset = req_vaddr_i[11:0];
    
    //=========================================================
    // PTE Field Extraction
    //=========================================================
    wire        pte_v = mem_resp_data_i[0];               // Valid
    wire        pte_r = mem_resp_data_i[1];               // Read
    wire        pte_w = mem_resp_data_i[2];               // Write
    wire        pte_x = mem_resp_data_i[3];               // Execute
    wire        pte_u = mem_resp_data_i[4];               // User
    wire        pte_g = mem_resp_data_i[5];               // Global
    wire        pte_a = mem_resp_data_i[6];               // Accessed
    wire        pte_d = mem_resp_data_i[7];               // Dirty
    wire [1:0]  pte_rsw = mem_resp_data_i[9:8];           // Reserved for SW
    wire [PPN_WIDTH-1:0] pte_ppn = mem_resp_data_i[31:10]; // PPN
    
    // Leaf PTE check: any of R, W, X is set
    wire pte_is_leaf = pte_r || pte_w || pte_x;
    
    // Invalid PTE checks
    wire pte_invalid = !pte_v || (!pte_r && pte_w);       // V=0 or W=1,R=0
    
    //=========================================================
    // State Machine
    //=========================================================
    localparam STATE_IDLE     = 3'd0;
    localparam STATE_LEVEL1   = 3'd1;  // Fetch PTE at level 1 (VPN[1])
    localparam STATE_WAIT1    = 3'd2;  // Wait for level 1 response
    localparam STATE_LEVEL0   = 3'd3;  // Fetch PTE at level 0 (VPN[0])
    localparam STATE_WAIT0    = 3'd4;  // Wait for level 0 response
    localparam STATE_DONE     = 3'd5;  // Complete
    localparam STATE_FAULT    = 3'd6;  // Page fault
    
    reg [2:0] state;
    reg [2:0] next_state;
    
    // Saved request
    reg [VADDR_WIDTH-1:0]  saved_vaddr;
    reg [ASID_WIDTH-1:0]   saved_asid;
    reg                    saved_is_store;
    
    // Current PTE address
    reg [PADDR_WIDTH-1:0]  pte_addr;
    
    // Saved PTE from level 1 (for superpage detection)
    reg [PTE_WIDTH-1:0]    saved_pte;
    reg                    is_superpage;
    
    assign req_ready_o = (state == STATE_IDLE);
    
    //=========================================================
    // State Transition Logic
    //=========================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            STATE_IDLE: begin
                if (req_valid_i && satp_mode) begin
                    next_state = STATE_LEVEL1;
                end else if (req_valid_i && !satp_mode) begin
                    // No translation (bare mode)
                    next_state = STATE_DONE;
                end
            end
            
            STATE_LEVEL1: begin
                if (mem_req_ready_i) begin
                    next_state = STATE_WAIT1;
                end
            end
            
            STATE_WAIT1: begin
                if (mem_resp_valid_i) begin
                    if (pte_invalid) begin
                        next_state = STATE_FAULT;
                    end else if (pte_is_leaf) begin
                        // Superpage found
                        next_state = STATE_DONE;
                    end else begin
                        // Continue to level 0
                        next_state = STATE_LEVEL0;
                    end
                end
            end
            
            STATE_LEVEL0: begin
                if (mem_req_ready_i) begin
                    next_state = STATE_WAIT0;
                end
            end
            
            STATE_WAIT0: begin
                if (mem_resp_valid_i) begin
                    if (pte_invalid || !pte_is_leaf) begin
                        next_state = STATE_FAULT;
                    end else begin
                        next_state = STATE_DONE;
                    end
                end
            end
            
            STATE_DONE, STATE_FAULT: begin
                next_state = STATE_IDLE;
            end
        endcase
    end
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            saved_vaddr <= 0;
            saved_asid <= 0;
            saved_is_store <= 0;
            pte_addr <= 0;
            saved_pte <= 0;
            is_superpage <= 0;
            
            resp_valid_o <= 0;
            resp_vaddr_o <= 0;
            resp_asid_o <= 0;
            resp_ppn_o <= 0;
            resp_d_o <= 0;
            resp_a_o <= 0;
            resp_g_o <= 0;
            resp_u_o <= 0;
            resp_x_o <= 0;
            resp_w_o <= 0;
            resp_r_o <= 0;
            resp_superpage_o <= 0;
            resp_fault_o <= 0;
            resp_fault_type_o <= 0;
            
            mem_req_valid_o <= 0;
            mem_req_addr_o <= 0;
        end else begin
            state <= next_state;
            resp_valid_o <= 0;
            mem_req_valid_o <= 0;
            
            case (state)
                STATE_IDLE: begin
                    if (req_valid_i) begin
                        saved_vaddr <= req_vaddr_i;
                        saved_asid <= req_asid_i;
                        saved_is_store <= req_is_store_i;
                        is_superpage <= 0;
                        
                        if (!satp_mode) begin
                            // Bare mode - identity mapping
                            resp_valid_o <= 1;
                            resp_vaddr_o <= req_vaddr_i;
                            resp_asid_o <= req_asid_i;
                            resp_ppn_o <= req_vaddr_i[VADDR_WIDTH-1:12];
                            resp_d_o <= 1;
                            resp_a_o <= 1;
                            resp_g_o <= 1;
                            resp_u_o <= 1;
                            resp_x_o <= 1;
                            resp_w_o <= 1;
                            resp_r_o <= 1;
                            resp_superpage_o <= 0;
                            resp_fault_o <= 0;
                        end
                    end
                end
                
                STATE_LEVEL1: begin
                    // Request PTE at level 1
                    mem_req_valid_o <= 1;
                    // PTE address = root_ppn * 4096 + VPN[1] * 4
                    mem_req_addr_o <= {satp_ppn, 12'b0} + {vpn1, 2'b00};
                end
                
                STATE_WAIT1: begin
                    if (mem_resp_valid_i) begin
                        saved_pte <= mem_resp_data_i;
                        
                        if (!pte_invalid && pte_is_leaf) begin
                            // Superpage - check alignment
                            // For Sv32 superpages, PPN[0] must be 0
                            is_superpage <= 1;
                            if (pte_ppn[VPN_WIDTH-1:0] != 0) begin
                                // Misaligned superpage - fault
                                state <= STATE_FAULT;
                            end
                        end
                    end
                end
                
                STATE_LEVEL0: begin
                    // Request PTE at level 0
                    mem_req_valid_o <= 1;
                    // PTE address = PPN from level 1 * 4096 + VPN[0] * 4
                    mem_req_addr_o <= {saved_pte[31:10], 12'b0} + {vpn0, 2'b00};
                end
                
                STATE_DONE: begin
                    resp_valid_o <= 1;
                    resp_vaddr_o <= saved_vaddr;
                    resp_asid_o <= saved_asid;
                    resp_fault_o <= 0;
                    
                    if (is_superpage) begin
                        // Use saved PTE from level 1
                        resp_ppn_o <= saved_pte[31:10];
                        resp_d_o <= saved_pte[7];
                        resp_a_o <= saved_pte[6];
                        resp_g_o <= saved_pte[5];
                        resp_u_o <= saved_pte[4];
                        resp_x_o <= saved_pte[3];
                        resp_w_o <= saved_pte[2];
                        resp_r_o <= saved_pte[1];
                        resp_superpage_o <= 1;
                    end else begin
                        // Use current PTE (from level 0 or bare)
                        resp_ppn_o <= pte_ppn;
                        resp_d_o <= pte_d;
                        resp_a_o <= pte_a;
                        resp_g_o <= pte_g;
                        resp_u_o <= pte_u;
                        resp_x_o <= pte_x;
                        resp_w_o <= pte_w;
                        resp_r_o <= pte_r;
                        resp_superpage_o <= 0;
                    end
                end
                
                STATE_FAULT: begin
                    resp_valid_o <= 1;
                    resp_vaddr_o <= saved_vaddr;
                    resp_asid_o <= saved_asid;
                    resp_fault_o <= 1;
                    resp_fault_type_o <= saved_is_store ? 4'd15 : 4'd13;  // Store/Load page fault
                end
            endcase
        end
    end

endmodule
