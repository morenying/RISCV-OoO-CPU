//=================================================================
// Module: rob
// Description: Reorder Buffer (ROB)
//              32-entry circular queue
//              Supports allocation, completion, and commit
//              Records exception information
// Requirements: 4.5, 4.6, 6.1
//=================================================================

`timescale 1ns/1ps

module rob #(
    parameter NUM_ENTRIES   = 32,
    parameter ROB_IDX_BITS  = 5,
    parameter PHYS_REG_BITS = 6,
    parameter ARCH_REG_BITS = 5,
    parameter DATA_WIDTH    = 32,
    parameter EXC_CODE_WIDTH = 4
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Allocation interface (from Rename stage)
    input  wire                     alloc_req_i,
    output wire                     alloc_ready_o,
    output wire [ROB_IDX_BITS-1:0]  alloc_idx_o,
    input  wire [ARCH_REG_BITS-1:0] alloc_rd_arch_i,
    input  wire [PHYS_REG_BITS-1:0] alloc_rd_phys_i,
    input  wire [PHYS_REG_BITS-1:0] alloc_rd_phys_old_i,
    input  wire [DATA_WIDTH-1:0]    alloc_pc_i,
    input  wire [3:0]               alloc_instr_type_i,
    input  wire                     alloc_is_branch_i,
    input  wire                     alloc_is_store_i,
    
    // Completion interface (from Execute stage)
    input  wire                     complete_valid_i,
    input  wire [ROB_IDX_BITS-1:0]  complete_idx_i,
    input  wire [DATA_WIDTH-1:0]    complete_result_i,
    input  wire                     complete_exception_i,
    input  wire [EXC_CODE_WIDTH-1:0] complete_exc_code_i,
    input  wire                     complete_branch_taken_i,
    input  wire [DATA_WIDTH-1:0]    complete_branch_target_i,
    
    // Commit interface (to Writeback stage)
    output wire                     commit_valid_o,
    input  wire                     commit_ready_i,
    output wire [ROB_IDX_BITS-1:0]  commit_idx_o,
    output wire [ARCH_REG_BITS-1:0] commit_rd_arch_o,
    output wire [PHYS_REG_BITS-1:0] commit_rd_phys_o,
    output wire [PHYS_REG_BITS-1:0] commit_rd_phys_old_o,
    output wire [DATA_WIDTH-1:0]    commit_result_o,
    output wire [DATA_WIDTH-1:0]    commit_pc_o,
    output wire                     commit_is_branch_o,
    output wire                     commit_branch_taken_o,
    output wire [DATA_WIDTH-1:0]    commit_branch_target_o,
    output wire                     commit_is_store_o,
    output wire                     commit_exception_o,
    output wire [EXC_CODE_WIDTH-1:0] commit_exc_code_o,
    
    // Flush interface
    input  wire                     flush_i,
    
    // Status
    output wire                     empty_o,
    output wire                     full_o,
    output wire [ROB_IDX_BITS:0]    count_o
);

    //=========================================================
    // ROB Entry Storage
    //=========================================================
    reg                     valid       [0:NUM_ENTRIES-1];
    reg                     completed   [0:NUM_ENTRIES-1];
    reg [ARCH_REG_BITS-1:0] rd_arch     [0:NUM_ENTRIES-1];
    reg [PHYS_REG_BITS-1:0] rd_phys     [0:NUM_ENTRIES-1];
    reg [PHYS_REG_BITS-1:0] rd_phys_old [0:NUM_ENTRIES-1];
    reg [DATA_WIDTH-1:0]    result      [0:NUM_ENTRIES-1];
    reg [DATA_WIDTH-1:0]    pc          [0:NUM_ENTRIES-1];
    reg [3:0]               instr_type  [0:NUM_ENTRIES-1];
    reg                     is_branch   [0:NUM_ENTRIES-1];
    reg                     is_store    [0:NUM_ENTRIES-1];
    reg                     branch_taken[0:NUM_ENTRIES-1];
    reg [DATA_WIDTH-1:0]    branch_target[0:NUM_ENTRIES-1];
    reg                     exception   [0:NUM_ENTRIES-1];
    reg [EXC_CODE_WIDTH-1:0] exc_code   [0:NUM_ENTRIES-1];
    
    //=========================================================
    // Queue Pointers
    //=========================================================
    reg [ROB_IDX_BITS-1:0] head;  // Commit pointer
    reg [ROB_IDX_BITS-1:0] tail;  // Allocation pointer
    reg [ROB_IDX_BITS:0]   count;
    
    integer i;
    
    //=========================================================
    // Status Signals
    //=========================================================
    assign empty_o = (count == 0);
    assign full_o = (count == NUM_ENTRIES);
    assign alloc_ready_o = !full_o;
    assign alloc_idx_o = tail;
    assign count_o = count;
    
    //=========================================================
    // Commit Output Logic
    //=========================================================
    wire head_valid_and_complete;
    assign head_valid_and_complete = valid[head] && completed[head];
    
    assign commit_valid_o = head_valid_and_complete;
    assign commit_idx_o = head;
    assign commit_rd_arch_o = rd_arch[head];
    assign commit_rd_phys_o = rd_phys[head];
    assign commit_rd_phys_old_o = rd_phys_old[head];
    assign commit_result_o = result[head];
    assign commit_pc_o = pc[head];
    assign commit_is_branch_o = is_branch[head];
    assign commit_branch_taken_o = branch_taken[head];
    assign commit_branch_target_o = branch_target[head];
    assign commit_is_store_o = is_store[head];
    assign commit_exception_o = exception[head];
    assign commit_exc_code_o = exc_code[head];

    //=========================================================
    // Main Sequential Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= 0;
            tail <= 0;
            count <= 0;
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 0;
                completed[i] <= 0;
                rd_arch[i] <= 0;
                rd_phys[i] <= 0;
                rd_phys_old[i] <= 0;
                result[i] <= 0;
                pc[i] <= 0;
                instr_type[i] <= 0;
                is_branch[i] <= 0;
                is_store[i] <= 0;
                branch_taken[i] <= 0;
                branch_target[i] <= 0;
                exception[i] <= 0;
                exc_code[i] <= 0;
            end
        end else if (flush_i) begin
            // Flush: reset all entries
            head <= 0;
            tail <= 0;
            count <= 0;
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 0;
                completed[i] <= 0;
            end
        end else begin
            //=================================================
            // Allocation
            //=================================================
            if (alloc_req_i && !full_o) begin
                valid[tail] <= 1'b1;
                completed[tail] <= 1'b0;
                rd_arch[tail] <= alloc_rd_arch_i;
                rd_phys[tail] <= alloc_rd_phys_i;
                rd_phys_old[tail] <= alloc_rd_phys_old_i;
                pc[tail] <= alloc_pc_i;
                instr_type[tail] <= alloc_instr_type_i;
                is_branch[tail] <= alloc_is_branch_i;
                is_store[tail] <= alloc_is_store_i;
                result[tail] <= 0;
                branch_taken[tail] <= 0;
                branch_target[tail] <= 0;
                exception[tail] <= 0;
                exc_code[tail] <= 0;
                
                tail <= (tail == NUM_ENTRIES - 1) ? 0 : tail + 1;
            end
            
            //=================================================
            // Completion
            //=================================================
            if (complete_valid_i && valid[complete_idx_i]) begin
                completed[complete_idx_i] <= 1'b1;
                result[complete_idx_i] <= complete_result_i;
                exception[complete_idx_i] <= complete_exception_i;
                exc_code[complete_idx_i] <= complete_exc_code_i;
                branch_taken[complete_idx_i] <= complete_branch_taken_i;
                branch_target[complete_idx_i] <= complete_branch_target_i;
            end
            
            //=================================================
            // Commit
            //=================================================
            if (commit_valid_o && commit_ready_i) begin
                valid[head] <= 1'b0;
                completed[head] <= 1'b0;
                head <= (head == NUM_ENTRIES - 1) ? 0 : head + 1;
            end
            
            //=================================================
            // Update Count
            //=================================================
            case ({alloc_req_i && !full_o, commit_valid_o && commit_ready_i})
                2'b10: count <= count + 1;
                2'b01: count <= count - 1;
                default: ; // count stays same
            endcase
        end
    end

endmodule
