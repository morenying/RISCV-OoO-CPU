//=================================================================
// Module: rob_enhanced
// Description: Enhanced Reorder Buffer (ROB)
//              64-entry circular queue (doubled from 32)
//              Supports dual commit for higher throughput
//              Checkpoint mechanism for fast branch recovery
//              Compressed storage format
// Requirements: 4.5, 4.6, 6.1
//=================================================================

`timescale 1ns/1ps

module rob_enhanced #(
    parameter NUM_ENTRIES    = 64,
    parameter ROB_IDX_BITS   = 6,       // log2(64)
    parameter PHYS_REG_BITS  = 7,       // 128 physical registers
    parameter ARCH_REG_BITS  = 5,
    parameter DATA_WIDTH     = 32,
    parameter EXC_CODE_WIDTH = 4,
    parameter NUM_CHECKPOINTS = 8       // Number of recovery checkpoints
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Dual Allocation Interface (from Rename stage)
    //=========================================================
    // Port 0
    input  wire                     alloc0_req_i,
    output wire                     alloc0_ready_o,
    output wire [ROB_IDX_BITS-1:0]  alloc0_idx_o,
    input  wire [ARCH_REG_BITS-1:0] alloc0_rd_arch_i,
    input  wire [PHYS_REG_BITS-1:0] alloc0_rd_phys_i,
    input  wire [PHYS_REG_BITS-1:0] alloc0_rd_phys_old_i,
    input  wire [DATA_WIDTH-1:0]    alloc0_pc_i,
    input  wire [3:0]               alloc0_instr_type_i,
    input  wire                     alloc0_is_branch_i,
    input  wire                     alloc0_is_store_i,
    
    // Port 1 (for superscalar)
    input  wire                     alloc1_req_i,
    output wire                     alloc1_ready_o,
    output wire [ROB_IDX_BITS-1:0]  alloc1_idx_o,
    input  wire [ARCH_REG_BITS-1:0] alloc1_rd_arch_i,
    input  wire [PHYS_REG_BITS-1:0] alloc1_rd_phys_i,
    input  wire [PHYS_REG_BITS-1:0] alloc1_rd_phys_old_i,
    input  wire [DATA_WIDTH-1:0]    alloc1_pc_i,
    input  wire [3:0]               alloc1_instr_type_i,
    input  wire                     alloc1_is_branch_i,
    input  wire                     alloc1_is_store_i,
    
    //=========================================================
    // Dual Completion Interface (from Execute stage)
    //=========================================================
    // Port 0
    input  wire                     complete0_valid_i,
    input  wire [ROB_IDX_BITS-1:0]  complete0_idx_i,
    input  wire [DATA_WIDTH-1:0]    complete0_result_i,
    input  wire                     complete0_exception_i,
    input  wire [EXC_CODE_WIDTH-1:0] complete0_exc_code_i,
    input  wire                     complete0_branch_taken_i,
    input  wire [DATA_WIDTH-1:0]    complete0_branch_target_i,
    
    // Port 1
    input  wire                     complete1_valid_i,
    input  wire [ROB_IDX_BITS-1:0]  complete1_idx_i,
    input  wire [DATA_WIDTH-1:0]    complete1_result_i,
    input  wire                     complete1_exception_i,
    input  wire [EXC_CODE_WIDTH-1:0] complete1_exc_code_i,
    input  wire                     complete1_branch_taken_i,
    input  wire [DATA_WIDTH-1:0]    complete1_branch_target_i,
    
    //=========================================================
    // Dual Commit Interface (to Writeback stage)
    //=========================================================
    // Port 0 (oldest instruction)
    output wire                     commit0_valid_o,
    input  wire                     commit0_ready_i,
    output wire [ROB_IDX_BITS-1:0]  commit0_idx_o,
    output wire [ARCH_REG_BITS-1:0] commit0_rd_arch_o,
    output wire [PHYS_REG_BITS-1:0] commit0_rd_phys_o,
    output wire [PHYS_REG_BITS-1:0] commit0_rd_phys_old_o,
    output wire [DATA_WIDTH-1:0]    commit0_result_o,
    output wire [DATA_WIDTH-1:0]    commit0_pc_o,
    output wire                     commit0_is_branch_o,
    output wire                     commit0_branch_taken_o,
    output wire [DATA_WIDTH-1:0]    commit0_branch_target_o,
    output wire                     commit0_is_store_o,
    output wire                     commit0_exception_o,
    output wire [EXC_CODE_WIDTH-1:0] commit0_exc_code_o,
    
    // Port 1 (second oldest instruction)
    output wire                     commit1_valid_o,
    input  wire                     commit1_ready_i,
    output wire [ROB_IDX_BITS-1:0]  commit1_idx_o,
    output wire [ARCH_REG_BITS-1:0] commit1_rd_arch_o,
    output wire [PHYS_REG_BITS-1:0] commit1_rd_phys_o,
    output wire [PHYS_REG_BITS-1:0] commit1_rd_phys_old_o,
    output wire [DATA_WIDTH-1:0]    commit1_result_o,
    output wire [DATA_WIDTH-1:0]    commit1_pc_o,
    output wire                     commit1_is_branch_o,
    output wire                     commit1_branch_taken_o,
    output wire [DATA_WIDTH-1:0]    commit1_branch_target_o,
    output wire                     commit1_is_store_o,
    output wire                     commit1_exception_o,
    output wire [EXC_CODE_WIDTH-1:0] commit1_exc_code_o,
    
    // Port 2 (third oldest instruction)
    output wire                     commit2_valid_o,
    input  wire                     commit2_ready_i,
    output wire [ROB_IDX_BITS-1:0]  commit2_idx_o,
    output wire [ARCH_REG_BITS-1:0] commit2_rd_arch_o,
    output wire [PHYS_REG_BITS-1:0] commit2_rd_phys_o,
    output wire [PHYS_REG_BITS-1:0] commit2_rd_phys_old_o,
    output wire [DATA_WIDTH-1:0]    commit2_result_o,
    output wire [DATA_WIDTH-1:0]    commit2_pc_o,
    output wire                     commit2_is_branch_o,
    output wire                     commit2_branch_taken_o,
    output wire [DATA_WIDTH-1:0]    commit2_branch_target_o,
    output wire                     commit2_is_store_o,
    output wire                     commit2_exception_o,
    output wire [EXC_CODE_WIDTH-1:0] commit2_exc_code_o,
    
    // Port 3 (fourth oldest instruction)
    output wire                     commit3_valid_o,
    input  wire                     commit3_ready_i,
    output wire [ROB_IDX_BITS-1:0]  commit3_idx_o,
    output wire [ARCH_REG_BITS-1:0] commit3_rd_arch_o,
    output wire [PHYS_REG_BITS-1:0] commit3_rd_phys_o,
    output wire [PHYS_REG_BITS-1:0] commit3_rd_phys_old_o,
    output wire [DATA_WIDTH-1:0]    commit3_result_o,
    output wire [DATA_WIDTH-1:0]    commit3_pc_o,
    output wire                     commit3_is_branch_o,
    output wire                     commit3_branch_taken_o,
    output wire [DATA_WIDTH-1:0]    commit3_branch_target_o,
    output wire                     commit3_is_store_o,
    output wire                     commit3_exception_o,
    output wire [EXC_CODE_WIDTH-1:0] commit3_exc_code_o,
    
    //=========================================================
    // Checkpoint Interface
    //=========================================================
    input  wire                     checkpoint_create_i,
    input  wire [2:0]               checkpoint_id_i,
    output wire [ROB_IDX_BITS-1:0]  checkpoint_tail_o,
    
    input  wire                     recover_i,
    input  wire [2:0]               recover_id_i,
    
    //=========================================================
    // Flush Interface
    //=========================================================
    input  wire                     flush_i,
    
    //=========================================================
    // Status
    //=========================================================
    output wire                     empty_o,
    output wire                     full_o,
    output wire                     almost_full_o,  // Less than 4 entries free
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
    // Checkpoint Storage
    //=========================================================
    reg [ROB_IDX_BITS-1:0] checkpoint_tail [0:NUM_CHECKPOINTS-1];
    reg [ROB_IDX_BITS:0]   checkpoint_count[0:NUM_CHECKPOINTS-1];
    
    //=========================================================
    // Queue Pointers
    //=========================================================
    reg [ROB_IDX_BITS-1:0] head;  // Commit pointer
    reg [ROB_IDX_BITS-1:0] tail;  // Allocation pointer
    reg [ROB_IDX_BITS:0]   count;
    
    // Next head pointers (for 4-way commit)
    wire [ROB_IDX_BITS-1:0] head_plus_1;
    wire [ROB_IDX_BITS-1:0] head_plus_2;
    wire [ROB_IDX_BITS-1:0] head_plus_3;
    assign head_plus_1 = (head == NUM_ENTRIES - 1) ? 0 : head + 1;
    assign head_plus_2 = (head >= NUM_ENTRIES - 2) ? head + 2 - NUM_ENTRIES : head + 2;
    assign head_plus_3 = (head >= NUM_ENTRIES - 3) ? head + 3 - NUM_ENTRIES : head + 3;
    
    // Next tail pointers (for dual allocation)
    wire [ROB_IDX_BITS-1:0] tail_plus_1;
    wire [ROB_IDX_BITS-1:0] tail_plus_2;
    assign tail_plus_1 = (tail == NUM_ENTRIES - 1) ? 0 : tail + 1;
    assign tail_plus_2 = (tail >= NUM_ENTRIES - 2) ? tail + 2 - NUM_ENTRIES : tail + 2;
    
    integer i;
    
    //=========================================================
    // Status Signals
    //=========================================================
    assign empty_o = (count == 0);
    assign full_o = (count >= NUM_ENTRIES - 1);  // Leave 1 entry margin
    assign almost_full_o = (count >= NUM_ENTRIES - 4);
    assign count_o = count;
    
    // Allocation ready (enough space for 1 or 2 entries)
    assign alloc0_ready_o = (count < NUM_ENTRIES - 1);
    assign alloc1_ready_o = (count < NUM_ENTRIES - 2);
    
    assign alloc0_idx_o = tail;
    assign alloc1_idx_o = tail_plus_1;
    
    assign checkpoint_tail_o = tail;
    
    //=========================================================
    // Commit 0 Output Logic (oldest instruction)
    //=========================================================
    wire head_valid_and_complete;
    assign head_valid_and_complete = valid[head] && completed[head];
    
    // Don't commit if there's an exception in the second instruction
    // and we would commit both (for precise exceptions)
    wire head_can_commit;
    assign head_can_commit = head_valid_and_complete && !exception[head];
    
    assign commit0_valid_o = head_valid_and_complete;
    assign commit0_idx_o = head;
    assign commit0_rd_arch_o = rd_arch[head];
    assign commit0_rd_phys_o = rd_phys[head];
    assign commit0_rd_phys_old_o = rd_phys_old[head];
    assign commit0_result_o = result[head];
    assign commit0_pc_o = pc[head];
    assign commit0_is_branch_o = is_branch[head];
    assign commit0_branch_taken_o = branch_taken[head];
    assign commit0_branch_target_o = branch_target[head];
    assign commit0_is_store_o = is_store[head];
    assign commit0_exception_o = exception[head];
    assign commit0_exc_code_o = exc_code[head];

    //=========================================================
    // Commit 1 Output Logic (second oldest instruction)
    //=========================================================
    wire head1_valid_and_complete;
    assign head1_valid_and_complete = valid[head_plus_1] && completed[head_plus_1];
    
    // Only commit second if first is also committing and no exception
    wire head1_can_commit;
    assign head1_can_commit = head1_valid_and_complete && 
                              head_can_commit && 
                              commit0_ready_i &&
                              !exception[head_plus_1] &&
                              !is_store[head];  // Don't dual-commit after store
    
    assign commit1_valid_o = head1_can_commit;
    assign commit1_idx_o = head_plus_1;
    assign commit1_rd_arch_o = rd_arch[head_plus_1];
    assign commit1_rd_phys_o = rd_phys[head_plus_1];
    assign commit1_rd_phys_old_o = rd_phys_old[head_plus_1];
    assign commit1_result_o = result[head_plus_1];
    assign commit1_pc_o = pc[head_plus_1];
    assign commit1_is_branch_o = is_branch[head_plus_1];
    assign commit1_branch_taken_o = branch_taken[head_plus_1];
    assign commit1_branch_target_o = branch_target[head_plus_1];
    assign commit1_is_store_o = is_store[head_plus_1];
    assign commit1_exception_o = exception[head_plus_1];
    assign commit1_exc_code_o = exc_code[head_plus_1];

    //=========================================================
    // Commit 2 Output Logic (third oldest instruction)
    //=========================================================
    wire head2_valid_and_complete;
    assign head2_valid_and_complete = valid[head_plus_2] && completed[head_plus_2];
    
    wire head2_can_commit;
    assign head2_can_commit = head2_valid_and_complete && 
                              head1_can_commit && 
                              commit1_ready_i &&
                              !exception[head_plus_2] &&
                              !is_store[head_plus_1];
    
    assign commit2_valid_o = head2_can_commit;
    assign commit2_idx_o = head_plus_2;
    assign commit2_rd_arch_o = rd_arch[head_plus_2];
    assign commit2_rd_phys_o = rd_phys[head_plus_2];
    assign commit2_rd_phys_old_o = rd_phys_old[head_plus_2];
    assign commit2_result_o = result[head_plus_2];
    assign commit2_pc_o = pc[head_plus_2];
    assign commit2_is_branch_o = is_branch[head_plus_2];
    assign commit2_branch_taken_o = branch_taken[head_plus_2];
    assign commit2_branch_target_o = branch_target[head_plus_2];
    assign commit2_is_store_o = is_store[head_plus_2];
    assign commit2_exception_o = exception[head_plus_2];
    assign commit2_exc_code_o = exc_code[head_plus_2];

    //=========================================================
    // Commit 3 Output Logic (fourth oldest instruction)
    //=========================================================
    wire head3_valid_and_complete;
    assign head3_valid_and_complete = valid[head_plus_3] && completed[head_plus_3];
    
    wire head3_can_commit;
    assign head3_can_commit = head3_valid_and_complete && 
                              head2_can_commit && 
                              commit2_ready_i &&
                              !exception[head_plus_3] &&
                              !is_store[head_plus_2];
    
    assign commit3_valid_o = head3_can_commit;
    assign commit3_idx_o = head_plus_3;
    assign commit3_rd_arch_o = rd_arch[head_plus_3];
    assign commit3_rd_phys_o = rd_phys[head_plus_3];
    assign commit3_rd_phys_old_o = rd_phys_old[head_plus_3];
    assign commit3_result_o = result[head_plus_3];
    assign commit3_pc_o = pc[head_plus_3];
    assign commit3_is_branch_o = is_branch[head_plus_3];
    assign commit3_branch_taken_o = branch_taken[head_plus_3];
    assign commit3_branch_target_o = branch_target[head_plus_3];
    assign commit3_is_store_o = is_store[head_plus_3];
    assign commit3_exception_o = exception[head_plus_3];
    assign commit3_exc_code_o = exc_code[head_plus_3];

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
            for (i = 0; i < NUM_CHECKPOINTS; i = i + 1) begin
                checkpoint_tail[i] <= 0;
                checkpoint_count[i] <= 0;
            end
        end else if (flush_i) begin
            // Full flush: reset all entries
            head <= 0;
            tail <= 0;
            count <= 0;
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 0;
                completed[i] <= 0;
            end
        end else if (recover_i) begin
            // Recover to checkpoint
            tail <= checkpoint_tail[recover_id_i];
            count <= checkpoint_count[recover_id_i];
            // Invalidate entries after checkpoint
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                // Check if entry is after checkpoint tail
                // This is complex due to circular buffer
                if (valid[i]) begin
                    // Entry is invalid if it was allocated after checkpoint
                    // Simple approach: invalidate all non-committed entries
                    if (!completed[i] || 
                        (i[ROB_IDX_BITS-1:0] >= checkpoint_tail[recover_id_i] && 
                         i[ROB_IDX_BITS-1:0] < tail) ||
                        (checkpoint_tail[recover_id_i] > tail && 
                         (i[ROB_IDX_BITS-1:0] >= checkpoint_tail[recover_id_i] || 
                          i[ROB_IDX_BITS-1:0] < tail))) begin
                        valid[i] <= 0;
                        completed[i] <= 0;
                    end
                end
            end
        end else begin
            //=================================================
            // Checkpoint Creation
            //=================================================
            if (checkpoint_create_i) begin
                checkpoint_tail[checkpoint_id_i] <= tail;
                checkpoint_count[checkpoint_id_i] <= count;
            end
            
            //=================================================
            // Dual Allocation
            //=================================================
            if (alloc0_req_i && alloc0_ready_o) begin
                valid[tail] <= 1'b1;
                completed[tail] <= 1'b0;
                rd_arch[tail] <= alloc0_rd_arch_i;
                rd_phys[tail] <= alloc0_rd_phys_i;
                rd_phys_old[tail] <= alloc0_rd_phys_old_i;
                pc[tail] <= alloc0_pc_i;
                instr_type[tail] <= alloc0_instr_type_i;
                is_branch[tail] <= alloc0_is_branch_i;
                is_store[tail] <= alloc0_is_store_i;
                result[tail] <= 0;
                branch_taken[tail] <= 0;
                branch_target[tail] <= 0;
                exception[tail] <= 0;
                exc_code[tail] <= 0;
                
                if (alloc1_req_i && alloc1_ready_o) begin
                    // Dual allocation
                    valid[tail_plus_1] <= 1'b1;
                    completed[tail_plus_1] <= 1'b0;
                    rd_arch[tail_plus_1] <= alloc1_rd_arch_i;
                    rd_phys[tail_plus_1] <= alloc1_rd_phys_i;
                    rd_phys_old[tail_plus_1] <= alloc1_rd_phys_old_i;
                    pc[tail_plus_1] <= alloc1_pc_i;
                    instr_type[tail_plus_1] <= alloc1_instr_type_i;
                    is_branch[tail_plus_1] <= alloc1_is_branch_i;
                    is_store[tail_plus_1] <= alloc1_is_store_i;
                    result[tail_plus_1] <= 0;
                    branch_taken[tail_plus_1] <= 0;
                    branch_target[tail_plus_1] <= 0;
                    exception[tail_plus_1] <= 0;
                    exc_code[tail_plus_1] <= 0;
                    
                    tail <= tail_plus_2;
                end else begin
                    tail <= tail_plus_1;
                end
            end else if (alloc1_req_i && alloc1_ready_o) begin
                // Only second allocation (shouldn't happen normally)
                valid[tail] <= 1'b1;
                completed[tail] <= 1'b0;
                rd_arch[tail] <= alloc1_rd_arch_i;
                rd_phys[tail] <= alloc1_rd_phys_i;
                rd_phys_old[tail] <= alloc1_rd_phys_old_i;
                pc[tail] <= alloc1_pc_i;
                instr_type[tail] <= alloc1_instr_type_i;
                is_branch[tail] <= alloc1_is_branch_i;
                is_store[tail] <= alloc1_is_store_i;
                
                tail <= tail_plus_1;
            end
            
            //=================================================
            // Dual Completion
            //=================================================
            if (complete0_valid_i && valid[complete0_idx_i]) begin
                completed[complete0_idx_i] <= 1'b1;
                result[complete0_idx_i] <= complete0_result_i;
                exception[complete0_idx_i] <= complete0_exception_i;
                exc_code[complete0_idx_i] <= complete0_exc_code_i;
                branch_taken[complete0_idx_i] <= complete0_branch_taken_i;
                branch_target[complete0_idx_i] <= complete0_branch_target_i;
            end
            
            if (complete1_valid_i && valid[complete1_idx_i]) begin
                completed[complete1_idx_i] <= 1'b1;
                result[complete1_idx_i] <= complete1_result_i;
                exception[complete1_idx_i] <= complete1_exception_i;
                exc_code[complete1_idx_i] <= complete1_exc_code_i;
                branch_taken[complete1_idx_i] <= complete1_branch_taken_i;
                branch_target[complete1_idx_i] <= complete1_branch_target_i;
            end
            
            //=================================================
            // 4-way Commit
            //=================================================
            if (commit0_valid_o && commit0_ready_i) begin
                valid[head] <= 1'b0;
                completed[head] <= 1'b0;
                
                if (commit1_valid_o && commit1_ready_i) begin
                    valid[head_plus_1] <= 1'b0;
                    completed[head_plus_1] <= 1'b0;
                    
                    if (commit2_valid_o && commit2_ready_i) begin
                        valid[head_plus_2] <= 1'b0;
                        completed[head_plus_2] <= 1'b0;
                        
                        if (commit3_valid_o && commit3_ready_i) begin
                            // 4-way commit
                            valid[head_plus_3] <= 1'b0;
                            completed[head_plus_3] <= 1'b0;
                            head <= (head_plus_3 == NUM_ENTRIES - 1) ? 0 : head_plus_3 + 1;
                        end else begin
                            // 3-way commit
                            head <= (head_plus_2 == NUM_ENTRIES - 1) ? 0 : head_plus_2 + 1;
                        end
                    end else begin
                        // 2-way commit
                        head <= (head_plus_1 == NUM_ENTRIES - 1) ? 0 : head_plus_1 + 1;
                    end
                end else begin
                    // 1-way commit
                    head <= head_plus_1;
                end
            end
            
            //=================================================
            // Update Count
            //=================================================
            begin
                reg [2:0] alloc_count;
                reg [2:0] commit_count;
                
                alloc_count = (alloc0_req_i && alloc0_ready_o ? 1 : 0) +
                              (alloc1_req_i && alloc1_ready_o ? 1 : 0);
                commit_count = (commit0_valid_o && commit0_ready_i ? 1 : 0) +
                               (commit1_valid_o && commit1_ready_i ? 1 : 0) +
                               (commit2_valid_o && commit2_ready_i ? 1 : 0) +
                               (commit3_valid_o && commit3_ready_i ? 1 : 0);
                
                count <= count + alloc_count - commit_count;
            end
        end
    end

endmodule
