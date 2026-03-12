//=================================================================
// Module: tlb
// Description: Translation Lookaside Buffer
//              32-entry fully associative TLB
//              Sv32 virtual memory support (2-level page table)
//              ASID support for fast context switching
//              Separate I-TLB and D-TLB recommended
// Requirements: Virtual Memory for Linux
//=================================================================

`timescale 1ns/1ps

module tlb #(
    parameter NUM_ENTRIES    = 32,
    parameter VADDR_WIDTH    = 32,
    parameter PADDR_WIDTH    = 34,     // 34-bit physical address for Sv32
    parameter ASID_WIDTH     = 9,
    parameter VPN_WIDTH      = 10,     // 10 bits per VPN level in Sv32
    parameter PPN_WIDTH      = 22,     // 22-bit PPN for Sv32
    parameter PAGE_OFFSET    = 12     // 4KB pages
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Lookup Interface
    //=========================================================
    input  wire                     lookup_valid_i,
    input  wire [VADDR_WIDTH-1:0]   lookup_vaddr_i,
    input  wire [ASID_WIDTH-1:0]    lookup_asid_i,
    input  wire [1:0]               lookup_priv_i,    // Current privilege
    input  wire                     lookup_sum_i,     // SUM bit from mstatus
    input  wire                     lookup_mxr_i,     // MXR bit from mstatus
    input  wire                     lookup_load_i,    // Load operation
    input  wire                     lookup_store_i,   // Store operation
    input  wire                     lookup_exec_i,    // Instruction fetch
    
    output wire                     lookup_hit_o,
    output wire [PADDR_WIDTH-1:0]   lookup_paddr_o,
    output wire                     lookup_fault_o,
    output wire [3:0]               lookup_fault_type_o,  // Exception type
    
    //=========================================================
    // Refill Interface (from Page Table Walker)
    //=========================================================
    input  wire                     refill_valid_i,
    input  wire [VADDR_WIDTH-1:0]   refill_vaddr_i,
    input  wire [ASID_WIDTH-1:0]    refill_asid_i,
    input  wire [PPN_WIDTH-1:0]     refill_ppn_i,
    input  wire                     refill_d_i,       // Dirty
    input  wire                     refill_a_i,       // Accessed
    input  wire                     refill_g_i,       // Global
    input  wire                     refill_u_i,       // User accessible
    input  wire                     refill_x_i,       // Executable
    input  wire                     refill_w_i,       // Writable
    input  wire                     refill_r_i,       // Readable
    input  wire                     refill_superpage_i, // 4MB superpage
    
    //=========================================================
    // Flush Interface
    //=========================================================
    input  wire                     flush_all_i,      // SFENCE.VMA with no args
    input  wire                     flush_asid_i,     // SFENCE.VMA with ASID
    input  wire [ASID_WIDTH-1:0]    flush_asid_val_i,
    input  wire                     flush_vaddr_i,    // SFENCE.VMA with VA
    input  wire [VADDR_WIDTH-1:0]   flush_vaddr_val_i,
    
    //=========================================================
    // Status
    //=========================================================
    output wire                     full_o
);

    //=========================================================
    // Exception Codes
    //=========================================================
    localparam EXC_INST_PAGE_FAULT  = 4'd12;
    localparam EXC_LOAD_PAGE_FAULT  = 4'd13;
    localparam EXC_STORE_PAGE_FAULT = 4'd15;
    
    //=========================================================
    // Privilege Levels
    //=========================================================
    localparam PRIV_U = 2'b00;
    localparam PRIV_S = 2'b01;
    localparam PRIV_M = 2'b11;
    
    //=========================================================
    // TLB Entry Storage
    //=========================================================
    reg [NUM_ENTRIES-1:0]   valid;
    reg [ASID_WIDTH-1:0]    asid    [0:NUM_ENTRIES-1];
    reg [VPN_WIDTH*2-1:0]   vpn     [0:NUM_ENTRIES-1];   // VPN[1] and VPN[0]
    reg [PPN_WIDTH-1:0]     ppn     [0:NUM_ENTRIES-1];
    reg [NUM_ENTRIES-1:0]   dirty;
    reg [NUM_ENTRIES-1:0]   accessed;
    reg [NUM_ENTRIES-1:0]   global_bit;
    reg [NUM_ENTRIES-1:0]   user;
    reg [NUM_ENTRIES-1:0]   exec;
    reg [NUM_ENTRIES-1:0]   write;
    reg [NUM_ENTRIES-1:0]   read;
    reg [NUM_ENTRIES-1:0]   superpage;  // 4MB superpage flag
    
    // PLRU replacement bits (tree-based for 32 entries)
    reg [NUM_ENTRIES-2:0]   plru_bits;
    
    //=========================================================
    // Lookup Logic
    //=========================================================
    wire [VPN_WIDTH*2-1:0] lookup_vpn = lookup_vaddr_i[VADDR_WIDTH-1:PAGE_OFFSET];
    wire [VPN_WIDTH-1:0]   lookup_vpn1 = lookup_vaddr_i[31:22];  // VPN[1]
    wire [VPN_WIDTH-1:0]   lookup_vpn0 = lookup_vaddr_i[21:12];  // VPN[0]
    
    // Match logic for each entry
    wire [NUM_ENTRIES-1:0] vpn_match;
    wire [NUM_ENTRIES-1:0] asid_match;
    wire [NUM_ENTRIES-1:0] entry_match;
    
    genvar i;
    generate
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin : gen_match
            // VPN match - for superpages, only VPN[1] needs to match
            wire vpn1_match = (vpn[i][VPN_WIDTH*2-1:VPN_WIDTH] == lookup_vpn1);
            wire vpn0_match = (vpn[i][VPN_WIDTH-1:0] == lookup_vpn0);
            
            assign vpn_match[i] = superpage[i] ? vpn1_match : (vpn1_match && vpn0_match);
            
            // ASID match - global entries match any ASID
            assign asid_match[i] = global_bit[i] || (asid[i] == lookup_asid_i);
            
            // Final match
            assign entry_match[i] = valid[i] && vpn_match[i] && asid_match[i];
        end
    endgenerate
    
    // Hit detection
    wire hit = |entry_match;
    assign lookup_hit_o = lookup_valid_i && hit;
    
    // Priority encoder to find matching entry
    reg [4:0] hit_idx;
    integer j;
    always @(*) begin
        hit_idx = 0;
        for (j = 0; j < NUM_ENTRIES; j = j + 1) begin
            if (entry_match[j]) hit_idx = j[4:0];
        end
    end
    
    //=========================================================
    // Physical Address Generation
    //=========================================================
    wire [PPN_WIDTH-1:0] hit_ppn = ppn[hit_idx];
    wire hit_superpage = superpage[hit_idx];
    
    // For superpages, lower PPN bits come from VPN[0]
    wire [PADDR_WIDTH-1:0] paddr_normal = {hit_ppn, lookup_vaddr_i[PAGE_OFFSET-1:0]};
    wire [PADDR_WIDTH-1:0] paddr_super = {hit_ppn[PPN_WIDTH-1:VPN_WIDTH], 
                                          lookup_vpn0, 
                                          lookup_vaddr_i[PAGE_OFFSET-1:0]};
    
    assign lookup_paddr_o = hit_superpage ? paddr_super : paddr_normal;
    
    //=========================================================
    // Permission Checking
    //=========================================================
    wire hit_r = read[hit_idx];
    wire hit_w = write[hit_idx];
    wire hit_x = exec[hit_idx];
    wire hit_u = user[hit_idx];
    wire hit_d = dirty[hit_idx];
    wire hit_a = accessed[hit_idx];
    
    // Effective read permission (MXR allows reading executable pages)
    wire eff_read = hit_r || (lookup_mxr_i && hit_x);
    
    // User/Supervisor access check
    wire user_access = (lookup_priv_i == PRIV_U);
    wire supervisor_access = (lookup_priv_i == PRIV_S);
    
    // SUM allows supervisor to access user pages
    wire can_access_user_page = user_access || (supervisor_access && lookup_sum_i);
    
    // Permission violations
    wire user_page_violation = hit_u && supervisor_access && !lookup_sum_i;
    wire supervisor_page_violation = !hit_u && user_access;
    
    wire read_violation = lookup_load_i && !eff_read;
    wire write_violation = lookup_store_i && !hit_w;
    wire exec_violation = lookup_exec_i && !hit_x;
    wire dirty_violation = lookup_store_i && !hit_d;
    wire access_violation = !hit_a;
    wire priv_violation = user_page_violation || supervisor_page_violation;
    
    // Page fault detection
    wire page_fault = hit && (read_violation || write_violation || exec_violation || 
                              dirty_violation || access_violation || priv_violation);
    
    assign lookup_fault_o = lookup_valid_i && (page_fault || !hit);
    
    // Fault type
    assign lookup_fault_type_o = lookup_exec_i ? EXC_INST_PAGE_FAULT :
                                  lookup_store_i ? EXC_STORE_PAGE_FAULT :
                                  EXC_LOAD_PAGE_FAULT;
    
    //=========================================================
    // Replacement Policy (Tree PLRU)
    // Generic for power-of-two NUM_ENTRIES (e.g. 16, 32)
    // plru_bits encodes which subtree is LRU at each internal node:
    //   0 -> left subtree is LRU, 1 -> right subtree is LRU
    //=========================================================
    localparam integer PLRU_LEVELS = $clog2(NUM_ENTRIES);
    reg [4:0] replace_idx;
    reg [4:0] plru_victim_idx;
    reg       found_invalid;
    integer   rp;
    integer   node;
    integer   lvl;

    // Compute PLRU victim, but prefer invalid entries when not full
    always @(*) begin
        // Tree traversal to find victim leaf
        node = 0;
        for (lvl = 0; lvl < PLRU_LEVELS; lvl = lvl + 1) begin
            if (plru_bits[node] == 1'b0)
                node = (node * 2) + 1; // go left
            else
                node = (node * 2) + 2; // go right
        end
        plru_victim_idx = node - (NUM_ENTRIES - 1);

        // Prefer first invalid entry if any
        replace_idx = plru_victim_idx;
        found_invalid = 1'b0;
        for (rp = 0; rp < NUM_ENTRIES; rp = rp + 1) begin
            if (!valid[rp] && !found_invalid) begin
                replace_idx = rp[4:0];
                found_invalid = 1'b1;
            end
        end
    end

    integer node_upd;
    integer lvl_upd;
    
    assign full_o = &valid;
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    integer k;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid <= 0;
            plru_bits <= 0;
            
            for (k = 0; k < NUM_ENTRIES; k = k + 1) begin
                asid[k] <= 0;
                vpn[k] <= 0;
                ppn[k] <= 0;
                dirty[k] <= 0;
                accessed[k] <= 0;
                global_bit[k] <= 0;
                user[k] <= 0;
                exec[k] <= 0;
                write[k] <= 0;
                read[k] <= 0;
                superpage[k] <= 0;
            end
        end else begin
            //=================================================
            // Flush Operations
            //=================================================
            if (flush_all_i) begin
                // Flush all entries
                valid <= 0;
            end else if (flush_asid_i && !flush_vaddr_i) begin
                // Flush all entries with matching ASID (except global)
                for (k = 0; k < NUM_ENTRIES; k = k + 1) begin
                    if (asid[k] == flush_asid_val_i && !global_bit[k]) begin
                        valid[k] <= 1'b0;
                    end
                end
            end else if (flush_vaddr_i && !flush_asid_i) begin
                // Flush entry with matching VA (any ASID)
                for (k = 0; k < NUM_ENTRIES; k = k + 1) begin
                    if (vpn[k] == flush_vaddr_val_i[31:12]) begin
                        valid[k] <= 1'b0;
                    end
                end
            end else if (flush_vaddr_i && flush_asid_i) begin
                // Flush entry with matching VA and ASID
                for (k = 0; k < NUM_ENTRIES; k = k + 1) begin
                    if (vpn[k] == flush_vaddr_val_i[31:12] && 
                        (asid[k] == flush_asid_val_i || global_bit[k])) begin
                        valid[k] <= 1'b0;
                    end
                end
            end
            
            //=================================================
            // Refill (from Page Table Walker)
            //=================================================
            else if (refill_valid_i) begin
                valid[replace_idx] <= 1'b1;
                asid[replace_idx] <= refill_asid_i;
                vpn[replace_idx] <= refill_vaddr_i[31:12];
                ppn[replace_idx] <= refill_ppn_i;
                dirty[replace_idx] <= refill_d_i;
                accessed[replace_idx] <= refill_a_i;
                global_bit[replace_idx] <= refill_g_i;
                user[replace_idx] <= refill_u_i;
                exec[replace_idx] <= refill_x_i;
                write[replace_idx] <= refill_w_i;
                read[replace_idx] <= refill_r_i;
                superpage[replace_idx] <= refill_superpage_i;

                // Update PLRU state as this entry becomes MRU
                node_upd = 0;
                for (lvl_upd = 0; lvl_upd < PLRU_LEVELS; lvl_upd = lvl_upd + 1) begin
                    if (replace_idx[PLRU_LEVELS-1-lvl_upd] == 1'b0) begin
                        plru_bits[node_upd] <= 1'b1; // right subtree becomes LRU
                        node_upd = (node_upd * 2) + 1;
                    end else begin
                        plru_bits[node_upd] <= 1'b0; // left subtree becomes LRU
                        node_upd = (node_upd * 2) + 2;
                    end
                end
            end
            
            //=================================================
            // Update PLRU on Hit
            //=================================================
            else if (lookup_valid_i && hit) begin
                // Update PLRU bits along the access path (mark hit as MRU)
                node_upd = 0;
                for (lvl_upd = 0; lvl_upd < PLRU_LEVELS; lvl_upd = lvl_upd + 1) begin
                    if (hit_idx[PLRU_LEVELS-1-lvl_upd] == 1'b0) begin
                        plru_bits[node_upd] <= 1'b1;
                        node_upd = (node_upd * 2) + 1;
                    end else begin
                        plru_bits[node_upd] <= 1'b0;
                        node_upd = (node_upd * 2) + 2;
                    end
                end
            end
        end
    end

endmodule
