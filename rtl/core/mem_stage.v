//=================================================================
// Module: mem_stage
// Description: Memory Stage
//              D-Cache interface
//              LSQ management
// Requirements: 2.1, 2.8
//=================================================================

`timescale 1ns/1ps

module mem_stage #(
    parameter XLEN = 32,
    parameter PHYS_REG_BITS = 6,
    parameter ROB_IDX_BITS = 5,
    parameter LSQ_IDX_BITS = 3
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    flush_i,
    
    //=========================================================
    // LSU Issue Interface (from RS)
    //=========================================================
    input  wire                    lsu_issue_valid_i,
    output wire                    lsu_issue_ready_o,
    input  wire                    lsu_issue_is_load_i,
    input  wire [1:0]              lsu_issue_mem_size_i,
    input  wire                    lsu_issue_mem_sign_ext_i,
    input  wire [XLEN-1:0]         lsu_issue_base_i,
    input  wire [XLEN-1:0]         lsu_issue_offset_i,
    input  wire [XLEN-1:0]         lsu_issue_store_data_i,
    input  wire [PHYS_REG_BITS-1:0] lsu_issue_dst_preg_i,
    input  wire [ROB_IDX_BITS-1:0] lsu_issue_rob_idx_i,
    
    //=========================================================
    // D-Cache Interface
    //=========================================================
    output wire                    dcache_req_valid_o,
    output wire                    dcache_req_write_o,
    output wire [XLEN-1:0]         dcache_req_addr_o,
    output wire [XLEN-1:0]         dcache_req_wdata_o,
    output wire [3:0]              dcache_req_wmask_o,
    input  wire                    dcache_req_ready_i,
    input  wire                    dcache_resp_valid_i,
    input  wire [XLEN-1:0]         dcache_resp_rdata_i,
    
    //=========================================================
    // Store Commit Interface (from ROB)
    //=========================================================
    input  wire                    store_commit_valid_i,
    input  wire [ROB_IDX_BITS-1:0] store_commit_rob_idx_i,
    
    //=========================================================
    // CDB Output Interface
    //=========================================================
    output wire                    lsu_cdb_valid_o,
    input  wire                    lsu_cdb_ready_i,
    output wire [PHYS_REG_BITS-1:0] lsu_cdb_preg_o,
    output wire [XLEN-1:0]         lsu_cdb_data_o,
    output wire [ROB_IDX_BITS-1:0] lsu_cdb_rob_idx_o,
    output wire                    lsu_cdb_exception_o,
    output wire [3:0]              lsu_cdb_exc_code_o,
    
    //=========================================================
    // Memory Ordering Violation
    //=========================================================
    output wire                    mem_violation_o,
    output wire [ROB_IDX_BITS-1:0] mem_violation_rob_idx_o
);

    //=========================================================
    // Address Generation
    //=========================================================
    wire [XLEN-1:0] mem_addr = lsu_issue_base_i + lsu_issue_offset_i;
    
    //=========================================================
    // Address Alignment Check
    //=========================================================
    reg addr_misaligned;
    always @(*) begin
        case (lsu_issue_mem_size_i)
            2'b00: addr_misaligned = 1'b0;                    // Byte - always aligned
            2'b01: addr_misaligned = mem_addr[0];             // Half - must be 2-byte aligned
            2'b10: addr_misaligned = |mem_addr[1:0];          // Word - must be 4-byte aligned
            default: addr_misaligned = 1'b0;
        endcase
    end
    
    //=========================================================
    // Write Mask Generation
    //=========================================================
    reg [3:0] write_mask;
    always @(*) begin
        case (lsu_issue_mem_size_i)
            2'b00: begin  // Byte
                case (mem_addr[1:0])
                    2'b00: write_mask = 4'b0001;
                    2'b01: write_mask = 4'b0010;
                    2'b10: write_mask = 4'b0100;
                    2'b11: write_mask = 4'b1000;
                endcase
            end
            2'b01: begin  // Half
                write_mask = mem_addr[1] ? 4'b1100 : 4'b0011;
            end
            2'b10: begin  // Word
                write_mask = 4'b1111;
            end
            default: write_mask = 4'b1111;
        endcase
    end
    
    //=========================================================
    // Store Data Alignment
    //=========================================================
    reg [XLEN-1:0] aligned_store_data;
    always @(*) begin
        case (lsu_issue_mem_size_i)
            2'b00: begin  // Byte
                aligned_store_data = {4{lsu_issue_store_data_i[7:0]}};
            end
            2'b01: begin  // Half
                aligned_store_data = {2{lsu_issue_store_data_i[15:0]}};
            end
            default: begin  // Word
                aligned_store_data = lsu_issue_store_data_i;
            end
        endcase
    end
    
    //=========================================================
    // State Machine
    //=========================================================
    localparam IDLE     = 3'b000;
    localparam LOAD_REQ = 3'b001;
    localparam LOAD_WAIT = 3'b010;
    localparam STORE_PEND = 3'b011;
    localparam STORE_REQ = 3'b100;
    localparam STORE_WAIT = 3'b101;
    
    reg [2:0] state;
    
    // Pending operation storage
    reg                    pend_is_load;
    reg [1:0]              pend_mem_size;
    reg                    pend_sign_ext;
    reg [XLEN-1:0]         pend_addr;
    reg [XLEN-1:0]         pend_store_data;
    reg [3:0]              pend_wmask;
    reg [PHYS_REG_BITS-1:0] pend_dst_preg;
    reg [ROB_IDX_BITS-1:0] pend_rob_idx;
    reg                    pend_misaligned;
    
    // Store queue for committed stores
    reg [XLEN-1:0]         sq_addr [0:7];
    reg [XLEN-1:0]         sq_data [0:7];
    reg [3:0]              sq_wmask [0:7];
    reg [ROB_IDX_BITS-1:0] sq_rob_idx [0:7];
    reg                    sq_valid [0:7];
    reg                    sq_committed [0:7];
    reg [2:0]              sq_head, sq_tail;
    reg [3:0]              sq_count;
    
    integer i;
    
    //=========================================================
    // Issue Ready
    //=========================================================
    assign lsu_issue_ready_o = (state == IDLE) && (sq_count < 8);
    
    //=========================================================
    // D-Cache Interface
    //=========================================================
    assign dcache_req_valid_o = (state == LOAD_REQ) || (state == STORE_REQ);
    assign dcache_req_write_o = (state == STORE_REQ);
    assign dcache_req_addr_o = pend_addr;
    assign dcache_req_wdata_o = pend_store_data;
    assign dcache_req_wmask_o = pend_wmask;
    
    //=========================================================
    // Load Data Extraction
    //=========================================================
    reg [XLEN-1:0] load_data;
    always @(*) begin
        case (pend_mem_size)
            2'b00: begin  // Byte
                case (pend_addr[1:0])
                    2'b00: load_data = pend_sign_ext ? 
                           {{24{dcache_resp_rdata_i[7]}}, dcache_resp_rdata_i[7:0]} :
                           {24'b0, dcache_resp_rdata_i[7:0]};
                    2'b01: load_data = pend_sign_ext ?
                           {{24{dcache_resp_rdata_i[15]}}, dcache_resp_rdata_i[15:8]} :
                           {24'b0, dcache_resp_rdata_i[15:8]};
                    2'b10: load_data = pend_sign_ext ?
                           {{24{dcache_resp_rdata_i[23]}}, dcache_resp_rdata_i[23:16]} :
                           {24'b0, dcache_resp_rdata_i[23:16]};
                    2'b11: load_data = pend_sign_ext ?
                           {{24{dcache_resp_rdata_i[31]}}, dcache_resp_rdata_i[31:24]} :
                           {24'b0, dcache_resp_rdata_i[31:24]};
                endcase
            end
            2'b01: begin  // Half
                if (pend_addr[1])
                    load_data = pend_sign_ext ?
                        {{16{dcache_resp_rdata_i[31]}}, dcache_resp_rdata_i[31:16]} :
                        {16'b0, dcache_resp_rdata_i[31:16]};
                else
                    load_data = pend_sign_ext ?
                        {{16{dcache_resp_rdata_i[15]}}, dcache_resp_rdata_i[15:0]} :
                        {16'b0, dcache_resp_rdata_i[15:0]};
            end
            default: begin  // Word
                load_data = dcache_resp_rdata_i;
            end
        endcase
    end
    
    //=========================================================
    // Result Output
    //=========================================================
    reg result_valid;
    reg [XLEN-1:0] result_data;
    reg [PHYS_REG_BITS-1:0] result_preg;
    reg [ROB_IDX_BITS-1:0] result_rob_idx;
    reg result_exception;
    reg [3:0] result_exc_code;
    
    assign lsu_cdb_valid_o = result_valid;
    assign lsu_cdb_preg_o = result_preg;
    assign lsu_cdb_data_o = result_data;
    assign lsu_cdb_rob_idx_o = result_rob_idx;
    assign lsu_cdb_exception_o = result_exception;
    assign lsu_cdb_exc_code_o = result_exc_code;
    
    // No memory ordering violation detection in this simplified version
    assign mem_violation_o = 1'b0;
    assign mem_violation_rob_idx_o = 0;
    
    //=========================================================
    // Main State Machine
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pend_is_load <= 0;
            pend_mem_size <= 0;
            pend_sign_ext <= 0;
            pend_addr <= 0;
            pend_store_data <= 0;
            pend_wmask <= 0;
            pend_dst_preg <= 0;
            pend_rob_idx <= 0;
            pend_misaligned <= 0;
            
            result_valid <= 0;
            result_data <= 0;
            result_preg <= 0;
            result_rob_idx <= 0;
            result_exception <= 0;
            result_exc_code <= 0;
            
            sq_head <= 0;
            sq_tail <= 0;
            sq_count <= 0;
            for (i = 0; i < 8; i = i + 1) begin
                sq_valid[i] <= 0;
                sq_committed[i] <= 0;
            end
        end else if (flush_i) begin
            state <= IDLE;
            result_valid <= 0;
            // Clear uncommitted stores
            for (i = 0; i < 8; i = i + 1) begin
                if (!sq_committed[i]) begin
                    sq_valid[i] <= 0;
                end
            end
        end else begin
            // Default: clear result valid
            result_valid <= 1'b0;
            
            // Mark stores as committed
            if (store_commit_valid_i) begin
                for (i = 0; i < 8; i = i + 1) begin
                    if (sq_valid[i] && sq_rob_idx[i] == store_commit_rob_idx_i) begin
                        sq_committed[i] <= 1'b1;
                    end
                end
            end
            
            case (state)
                IDLE: begin
                    if (lsu_issue_valid_i && lsu_issue_ready_o) begin
                        pend_is_load <= lsu_issue_is_load_i;
                        pend_mem_size <= lsu_issue_mem_size_i;
                        pend_sign_ext <= lsu_issue_mem_sign_ext_i;
                        pend_addr <= mem_addr;
                        pend_store_data <= aligned_store_data;
                        pend_wmask <= write_mask;
                        pend_dst_preg <= lsu_issue_dst_preg_i;
                        pend_rob_idx <= lsu_issue_rob_idx_i;
                        pend_misaligned <= addr_misaligned;
                        
                        if (addr_misaligned) begin
                            // Report misalignment exception immediately
                            result_valid <= 1'b1;
                            result_preg <= lsu_issue_dst_preg_i;
                            result_data <= 0;
                            result_rob_idx <= lsu_issue_rob_idx_i;
                            result_exception <= 1'b1;
                            result_exc_code <= lsu_issue_is_load_i ? 4'd4 : 4'd6;
                        end else if (lsu_issue_is_load_i) begin
                            state <= LOAD_REQ;
                        end else begin
                            // Store: add to store queue
                            sq_addr[sq_tail] <= mem_addr;
                            sq_data[sq_tail] <= aligned_store_data;
                            sq_wmask[sq_tail] <= write_mask;
                            sq_rob_idx[sq_tail] <= lsu_issue_rob_idx_i;
                            sq_valid[sq_tail] <= 1'b1;
                            sq_committed[sq_tail] <= 1'b0;
                            sq_tail <= sq_tail + 1;
                            sq_count <= sq_count + 1;
                            
                            // Store completes immediately (will write on commit)
                            result_valid <= 1'b1;
                            result_preg <= 0;
                            result_data <= 0;
                            result_rob_idx <= lsu_issue_rob_idx_i;
                            result_exception <= 1'b0;
                            result_exc_code <= 0;
                        end
                    end
                    
                    // Process committed stores
                    if (sq_valid[sq_head] && sq_committed[sq_head] && state == IDLE) begin
                        pend_addr <= sq_addr[sq_head];
                        pend_store_data <= sq_data[sq_head];
                        pend_wmask <= sq_wmask[sq_head];
                        state <= STORE_REQ;
                    end
                end
                
                LOAD_REQ: begin
                    if (dcache_req_ready_i) begin
                        state <= LOAD_WAIT;
                    end
                end
                
                LOAD_WAIT: begin
                    if (dcache_resp_valid_i) begin
                        result_valid <= 1'b1;
                        result_preg <= pend_dst_preg;
                        result_data <= load_data;
                        result_rob_idx <= pend_rob_idx;
                        result_exception <= 1'b0;
                        result_exc_code <= 0;
                        state <= IDLE;
                    end
                end
                
                STORE_REQ: begin
                    if (dcache_req_ready_i) begin
                        state <= STORE_WAIT;
                    end
                end
                
                STORE_WAIT: begin
                    if (dcache_resp_valid_i) begin
                        // Store completed, remove from queue
                        sq_valid[sq_head] <= 1'b0;
                        sq_committed[sq_head] <= 1'b0;
                        sq_head <= sq_head + 1;
                        sq_count <= sq_count - 1;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
