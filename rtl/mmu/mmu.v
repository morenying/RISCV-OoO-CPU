//=================================================================
// Module: mmu
// Description: Memory Management Unit Top Module
//              Integrates TLB + Page Table Walker
//              Supports both I-MMU and D-MMU functions
//              Full Sv32 virtual memory for Linux
//=================================================================

`timescale 1ns/1ps

module mmu #(
    parameter VADDR_WIDTH    = 32,
    parameter PADDR_WIDTH    = 34,
    parameter DATA_WIDTH     = 32,
    parameter TLB_ENTRIES    = 32,
    parameter ASID_WIDTH     = 9
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // I-MMU Interface (Instruction Fetch)
    //=========================================================
    input  wire                     immu_req_valid_i,
    input  wire [VADDR_WIDTH-1:0]   immu_vaddr_i,
    output wire                     immu_req_ready_o,
    
    output wire                     immu_resp_valid_o,
    output wire [PADDR_WIDTH-1:0]   immu_paddr_o,
    output wire                     immu_page_fault_o,
    output wire                     immu_access_fault_o,
    
    //=========================================================
    // D-MMU Interface (Load/Store)
    //=========================================================
    input  wire                     dmmu_req_valid_i,
    input  wire [VADDR_WIDTH-1:0]   dmmu_vaddr_i,
    input  wire                     dmmu_is_store_i,
    output wire                     dmmu_req_ready_o,
    
    output wire                     dmmu_resp_valid_o,
    output wire [PADDR_WIDTH-1:0]   dmmu_paddr_o,
    output wire                     dmmu_page_fault_o,
    output wire                     dmmu_access_fault_o,
    
    //=========================================================
    // Privilege and CSR Interface
    //=========================================================
    input  wire [1:0]               priv_mode_i,      // Current privilege mode
    input  wire [31:0]              satp_i,           // SATP register
    input  wire                     sum_i,            // Status.SUM
    input  wire                     mxr_i,            // Status.MXR
    
    //=========================================================
    // SFENCE.VMA Interface
    //=========================================================
    input  wire                     sfence_valid_i,
    input  wire                     sfence_rs1_zero_i,
    input  wire                     sfence_rs2_zero_i,
    input  wire [VADDR_WIDTH-1:0]   sfence_vaddr_i,
    input  wire [ASID_WIDTH-1:0]    sfence_asid_i,
    
    //=========================================================
    // Memory Interface (for PTW)
    //=========================================================
    output wire                     mem_req_valid_o,
    output wire [PADDR_WIDTH-1:0]   mem_req_addr_o,
    input  wire                     mem_req_ready_i,
    
    input  wire                     mem_resp_valid_i,
    input  wire [DATA_WIDTH-1:0]    mem_resp_data_i
);

    //=========================================================
    // Local Parameters
    //=========================================================
    localparam PPN_WIDTH = 22;
    localparam VPN_WIDTH = 10;
    
    // Privilege modes
    localparam PRIV_U = 2'b00;
    localparam PRIV_S = 2'b01;
    localparam PRIV_M = 2'b11;
    
    //=========================================================
    // SATP Field Extraction
    //=========================================================
    wire        satp_mode = satp_i[31];
    wire [ASID_WIDTH-1:0] satp_asid = satp_i[30:22];
    
    //=========================================================
    // I-TLB Instance
    //=========================================================
    wire                    itlb_hit;
    wire [PPN_WIDTH-1:0]    itlb_ppn;
    wire                    itlb_fault;
    wire [3:0]              itlb_fault_type;
    
    wire                    itlb_refill_valid;
    wire [VADDR_WIDTH-1:0]  itlb_refill_vaddr;
    wire [ASID_WIDTH-1:0]   itlb_refill_asid;
    wire [PPN_WIDTH-1:0]    itlb_refill_ppn;
    wire                    itlb_refill_d, itlb_refill_a, itlb_refill_g;
    wire                    itlb_refill_u, itlb_refill_x, itlb_refill_w, itlb_refill_r;
    wire                    itlb_refill_superpage;
    
    wire [PADDR_WIDTH-1:0] itlb_paddr;  // Full physical address from TLB
    assign itlb_ppn = itlb_paddr[PADDR_WIDTH-1:12];  // Extract PPN from paddr
    
    tlb #(
        .NUM_ENTRIES    (TLB_ENTRIES/2),
        .VADDR_WIDTH    (VADDR_WIDTH),
        .PADDR_WIDTH    (PADDR_WIDTH),
        .ASID_WIDTH     (ASID_WIDTH)
    ) u_itlb (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // Lookup
        .lookup_valid_i (immu_req_valid_i && satp_mode),
        .lookup_vaddr_i (immu_vaddr_i),
        .lookup_asid_i  (satp_asid),
        .lookup_load_i  (1'b0),
        .lookup_store_i (1'b0),
        .lookup_exec_i  (1'b1),
        .lookup_priv_i  (priv_mode_i),
        .lookup_sum_i   (sum_i),
        .lookup_mxr_i   (mxr_i),
        
        .lookup_hit_o   (itlb_hit),
        .lookup_paddr_o (itlb_paddr),
        .lookup_fault_o (itlb_fault),
        .lookup_fault_type_o (itlb_fault_type),
        
        // Refill
        .refill_valid_i (itlb_refill_valid),
        .refill_vaddr_i (itlb_refill_vaddr),
        .refill_asid_i  (itlb_refill_asid),
        .refill_ppn_i   (itlb_refill_ppn),
        .refill_d_i     (itlb_refill_d),
        .refill_a_i     (itlb_refill_a),
        .refill_g_i     (itlb_refill_g),
        .refill_u_i     (itlb_refill_u),
        .refill_x_i     (itlb_refill_x),
        .refill_w_i     (itlb_refill_w),
        .refill_r_i     (itlb_refill_r),
        .refill_superpage_i (itlb_refill_superpage),
        
        // Flush
        .flush_all_i        (sfence_valid_i && sfence_rs1_zero_i && sfence_rs2_zero_i),
        .flush_asid_i       (sfence_valid_i && sfence_rs1_zero_i && !sfence_rs2_zero_i),
        .flush_asid_val_i   (sfence_asid_i),
        .flush_vaddr_i      (sfence_valid_i && !sfence_rs1_zero_i),
        .flush_vaddr_val_i  (sfence_vaddr_i),
        
        // Status
        .full_o             ()
    );
    
    //=========================================================
    // D-TLB Instance
    //=========================================================
    wire                    dtlb_hit;
    wire [PPN_WIDTH-1:0]    dtlb_ppn;
    wire                    dtlb_fault;
    wire [3:0]              dtlb_fault_type;
    
    wire                    dtlb_refill_valid;
    wire [VADDR_WIDTH-1:0]  dtlb_refill_vaddr;
    wire [ASID_WIDTH-1:0]   dtlb_refill_asid;
    wire [PPN_WIDTH-1:0]    dtlb_refill_ppn;
    wire                    dtlb_refill_d, dtlb_refill_a, dtlb_refill_g;
    wire                    dtlb_refill_u, dtlb_refill_x, dtlb_refill_w, dtlb_refill_r;
    wire                    dtlb_refill_superpage;
    
    wire [PADDR_WIDTH-1:0] dtlb_paddr;  // Full physical address from TLB
    assign dtlb_ppn = dtlb_paddr[PADDR_WIDTH-1:12];  // Extract PPN from paddr
    
    tlb #(
        .NUM_ENTRIES    (TLB_ENTRIES/2),
        .VADDR_WIDTH    (VADDR_WIDTH),
        .PADDR_WIDTH    (PADDR_WIDTH),
        .ASID_WIDTH     (ASID_WIDTH)
    ) u_dtlb (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // Lookup
        .lookup_valid_i (dmmu_req_valid_i && satp_mode),
        .lookup_vaddr_i (dmmu_vaddr_i),
        .lookup_asid_i  (satp_asid),
        .lookup_load_i  (!dmmu_is_store_i),
        .lookup_store_i (dmmu_is_store_i),
        .lookup_exec_i  (1'b0),
        .lookup_priv_i  (priv_mode_i),
        .lookup_sum_i   (sum_i),
        .lookup_mxr_i   (mxr_i),
        
        .lookup_hit_o   (dtlb_hit),
        .lookup_paddr_o (dtlb_paddr),
        .lookup_fault_o (dtlb_fault),
        .lookup_fault_type_o (dtlb_fault_type),
        
        // Refill
        .refill_valid_i (dtlb_refill_valid),
        .refill_vaddr_i (dtlb_refill_vaddr),
        .refill_asid_i  (dtlb_refill_asid),
        .refill_ppn_i   (dtlb_refill_ppn),
        .refill_d_i     (dtlb_refill_d),
        .refill_a_i     (dtlb_refill_a),
        .refill_g_i     (dtlb_refill_g),
        .refill_u_i     (dtlb_refill_u),
        .refill_x_i     (dtlb_refill_x),
        .refill_w_i     (dtlb_refill_w),
        .refill_r_i     (dtlb_refill_r),
        .refill_superpage_i (dtlb_refill_superpage),
        
        // Flush
        .flush_all_i        (sfence_valid_i && sfence_rs1_zero_i && sfence_rs2_zero_i),
        .flush_asid_i       (sfence_valid_i && sfence_rs1_zero_i && !sfence_rs2_zero_i),
        .flush_asid_val_i   (sfence_asid_i),
        .flush_vaddr_i      (sfence_valid_i && !sfence_rs1_zero_i),
        .flush_vaddr_val_i  (sfence_vaddr_i),
        
        // Status
        .full_o             ()
    );
    
    //=========================================================
    // PTW Arbiter State Machine
    //=========================================================
    localparam PTW_IDLE     = 2'd0;
    localparam PTW_IFETCH   = 2'd1;
    localparam PTW_DATA     = 2'd2;
    
    reg [1:0] ptw_state;
    reg [1:0] ptw_next_state;
    
    // PTW miss detection
    wire itlb_miss = immu_req_valid_i && satp_mode && !itlb_hit && !itlb_fault;
    wire dtlb_miss = dmmu_req_valid_i && satp_mode && !dtlb_hit && !dtlb_fault;
    
    // PTW request signals
    reg         ptw_req_valid;
    reg [31:0]  ptw_req_vaddr;
    reg [8:0]   ptw_req_asid;
    reg         ptw_req_is_store;
    reg         ptw_for_ifetch;
    
    wire        ptw_req_ready;
    wire        ptw_resp_valid;
    wire [31:0] ptw_resp_vaddr;
    wire [8:0]  ptw_resp_asid;
    wire [21:0] ptw_resp_ppn;
    wire        ptw_resp_d, ptw_resp_a, ptw_resp_g;
    wire        ptw_resp_u, ptw_resp_x, ptw_resp_w, ptw_resp_r;
    wire        ptw_resp_superpage;
    wire        ptw_resp_fault;
    wire [3:0]  ptw_resp_fault_type;
    
    //=========================================================
    // PTW Instance
    //=========================================================
    ptw #(
        .VADDR_WIDTH    (VADDR_WIDTH),
        .PADDR_WIDTH    (PADDR_WIDTH),
        .PPN_WIDTH      (PPN_WIDTH),
        .VPN_WIDTH      (VPN_WIDTH),
        .PTE_WIDTH      (DATA_WIDTH),
        .ASID_WIDTH     (ASID_WIDTH)
    ) u_ptw (
        .clk            (clk),
        .rst_n          (rst_n),
        
        .req_valid_i    (ptw_req_valid),
        .req_vaddr_i    (ptw_req_vaddr),
        .req_asid_i     (ptw_req_asid),
        .req_is_store_i (ptw_req_is_store),
        .req_ready_o    (ptw_req_ready),
        
        .resp_valid_o       (ptw_resp_valid),
        .resp_vaddr_o       (ptw_resp_vaddr),
        .resp_asid_o        (ptw_resp_asid),
        .resp_ppn_o         (ptw_resp_ppn),
        .resp_d_o           (ptw_resp_d),
        .resp_a_o           (ptw_resp_a),
        .resp_g_o           (ptw_resp_g),
        .resp_u_o           (ptw_resp_u),
        .resp_x_o           (ptw_resp_x),
        .resp_w_o           (ptw_resp_w),
        .resp_r_o           (ptw_resp_r),
        .resp_superpage_o   (ptw_resp_superpage),
        .resp_fault_o       (ptw_resp_fault),
        .resp_fault_type_o  (ptw_resp_fault_type),
        
        .satp_i             (satp_i),
        
        .mem_req_valid_o    (mem_req_valid_o),
        .mem_req_addr_o     (mem_req_addr_o),
        .mem_req_ready_i    (mem_req_ready_i),
        .mem_resp_valid_i   (mem_resp_valid_i),
        .mem_resp_data_i    (mem_resp_data_i)
    );
    
    //=========================================================
    // PTW Arbiter FSM
    //=========================================================
    always @(*) begin
        ptw_next_state = ptw_state;
        
        case (ptw_state)
            PTW_IDLE: begin
                // Prioritize data TLB miss over instruction TLB miss
                if (dtlb_miss) begin
                    ptw_next_state = PTW_DATA;
                end else if (itlb_miss) begin
                    ptw_next_state = PTW_IFETCH;
                end
            end
            
            PTW_IFETCH, PTW_DATA: begin
                if (ptw_resp_valid) begin
                    ptw_next_state = PTW_IDLE;
                end
            end
        endcase
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptw_state <= PTW_IDLE;
            ptw_req_valid <= 0;
            ptw_req_vaddr <= 0;
            ptw_req_asid <= 0;
            ptw_req_is_store <= 0;
            ptw_for_ifetch <= 0;
        end else begin
            ptw_state <= ptw_next_state;
            
            case (ptw_state)
                PTW_IDLE: begin
                    if (dtlb_miss) begin
                        ptw_req_valid <= 1;
                        ptw_req_vaddr <= dmmu_vaddr_i;
                        ptw_req_asid <= satp_asid;
                        ptw_req_is_store <= dmmu_is_store_i;
                        ptw_for_ifetch <= 0;
                    end else if (itlb_miss) begin
                        ptw_req_valid <= 1;
                        ptw_req_vaddr <= immu_vaddr_i;
                        ptw_req_asid <= satp_asid;
                        ptw_req_is_store <= 0;
                        ptw_for_ifetch <= 1;
                    end
                end
                
                PTW_IFETCH, PTW_DATA: begin
                    if (ptw_req_ready) begin
                        ptw_req_valid <= 0;
                    end
                end
            endcase
        end
    end
    
    //=========================================================
    // TLB Refill Routing
    //=========================================================
    assign itlb_refill_valid = ptw_resp_valid && ptw_for_ifetch && !ptw_resp_fault;
    assign itlb_refill_vaddr = ptw_resp_vaddr;
    assign itlb_refill_asid = ptw_resp_asid;
    assign itlb_refill_ppn = ptw_resp_ppn;
    assign itlb_refill_d = ptw_resp_d;
    assign itlb_refill_a = ptw_resp_a;
    assign itlb_refill_g = ptw_resp_g;
    assign itlb_refill_u = ptw_resp_u;
    assign itlb_refill_x = ptw_resp_x;
    assign itlb_refill_w = ptw_resp_w;
    assign itlb_refill_r = ptw_resp_r;
    assign itlb_refill_superpage = ptw_resp_superpage;
    
    assign dtlb_refill_valid = ptw_resp_valid && !ptw_for_ifetch && !ptw_resp_fault;
    assign dtlb_refill_vaddr = ptw_resp_vaddr;
    assign dtlb_refill_asid = ptw_resp_asid;
    assign dtlb_refill_ppn = ptw_resp_ppn;
    assign dtlb_refill_d = ptw_resp_d;
    assign dtlb_refill_a = ptw_resp_a;
    assign dtlb_refill_g = ptw_resp_g;
    assign dtlb_refill_u = ptw_resp_u;
    assign dtlb_refill_x = ptw_resp_x;
    assign dtlb_refill_w = ptw_resp_w;
    assign dtlb_refill_r = ptw_resp_r;
    assign dtlb_refill_superpage = ptw_resp_superpage;
    
    //=========================================================
    // Physical Address Generation
    // TLB outputs full physical address directly (handles superpages internally)
    //=========================================================
    wire [PADDR_WIDTH-1:0] immu_paddr_trans = itlb_paddr;
    wire [PADDR_WIDTH-1:0] dmmu_paddr_trans = dtlb_paddr;
    
    //=========================================================
    // Output Logic
    //=========================================================
    // I-MMU outputs
    assign immu_req_ready_o = !itlb_miss || (ptw_state == PTW_IDLE);
    
    reg immu_resp_valid_reg;
    reg [PADDR_WIDTH-1:0] immu_paddr_reg;
    reg immu_page_fault_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            immu_resp_valid_reg <= 0;
            immu_paddr_reg <= 0;
            immu_page_fault_reg <= 0;
        end else begin
            immu_resp_valid_reg <= 0;
            
            if (immu_req_valid_i) begin
                if (!satp_mode) begin
                    // Bare mode - no translation
                    immu_resp_valid_reg <= 1;
                    immu_paddr_reg <= {{(PADDR_WIDTH-VADDR_WIDTH){1'b0}}, immu_vaddr_i};
                    immu_page_fault_reg <= 0;
                end else if (itlb_hit) begin
                    immu_resp_valid_reg <= 1;
                    immu_paddr_reg <= immu_paddr_trans;
                    immu_page_fault_reg <= itlb_fault;
                end
            end
            
            // PTW response for I-MMU
            if (ptw_resp_valid && ptw_for_ifetch) begin
                immu_resp_valid_reg <= 1;
                if (ptw_resp_fault) begin
                    immu_page_fault_reg <= 1;
                    immu_paddr_reg <= 0;
                end else begin
                    immu_page_fault_reg <= 0;
                    immu_paddr_reg <= ptw_resp_superpage ?
                        {ptw_resp_ppn[PPN_WIDTH-1:VPN_WIDTH], ptw_resp_vaddr[21:0]} :
                        {ptw_resp_ppn, ptw_resp_vaddr[11:0]};
                end
            end
        end
    end
    
    assign immu_resp_valid_o = immu_resp_valid_reg;
    assign immu_paddr_o = immu_paddr_reg;
    assign immu_page_fault_o = immu_page_fault_reg;
    assign immu_access_fault_o = 1'b0;  // Access fault from PMA/PMP (not implemented)
    
    // D-MMU outputs
    assign dmmu_req_ready_o = !dtlb_miss || (ptw_state == PTW_IDLE);
    
    reg dmmu_resp_valid_reg;
    reg [PADDR_WIDTH-1:0] dmmu_paddr_reg;
    reg dmmu_page_fault_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmmu_resp_valid_reg <= 0;
            dmmu_paddr_reg <= 0;
            dmmu_page_fault_reg <= 0;
        end else begin
            dmmu_resp_valid_reg <= 0;
            
            if (dmmu_req_valid_i) begin
                if (!satp_mode) begin
                    // Bare mode
                    dmmu_resp_valid_reg <= 1;
                    dmmu_paddr_reg <= {{(PADDR_WIDTH-VADDR_WIDTH){1'b0}}, dmmu_vaddr_i};
                    dmmu_page_fault_reg <= 0;
                end else if (dtlb_hit) begin
                    dmmu_resp_valid_reg <= 1;
                    dmmu_paddr_reg <= dmmu_paddr_trans;
                    dmmu_page_fault_reg <= dtlb_fault;
                end
            end
            
            // PTW response for D-MMU
            if (ptw_resp_valid && !ptw_for_ifetch) begin
                dmmu_resp_valid_reg <= 1;
                if (ptw_resp_fault) begin
                    dmmu_page_fault_reg <= 1;
                    dmmu_paddr_reg <= 0;
                end else begin
                    dmmu_page_fault_reg <= 0;
                    dmmu_paddr_reg <= ptw_resp_superpage ?
                        {ptw_resp_ppn[PPN_WIDTH-1:VPN_WIDTH], ptw_resp_vaddr[21:0]} :
                        {ptw_resp_ppn, ptw_resp_vaddr[11:0]};
                end
            end
        end
    end
    
    assign dmmu_resp_valid_o = dmmu_resp_valid_reg;
    assign dmmu_paddr_o = dmmu_paddr_reg;
    assign dmmu_page_fault_o = dmmu_page_fault_reg;
    assign dmmu_access_fault_o = 1'b0;

endmodule
