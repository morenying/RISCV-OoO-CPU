//=================================================================
// Module: speculative_history_manager
// Description: Speculative Branch History Manager
//              Manages speculative updates to GHR
//              8 checkpoints for branch recovery
//              Fast rollback on branch misprediction
// Requirements: 2.3, 6.1
//=================================================================

`timescale 1ns/1ps

module speculative_history_manager #(
    parameter GHR_WIDTH       = 256,
    parameter NUM_CHECKPOINTS = 8,
    parameter CHECKPOINT_BITS = 3,       // log2(8)
    parameter ROB_IDX_BITS    = 6
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Speculative Update Interface (from BPU)
    //=========================================================
    input  wire                     update_valid_i,
    input  wire                     update_taken_i,
    input  wire                     update_is_branch_i,
    input  wire [31:0]              update_pc_i,
    
    //=========================================================
    // Checkpoint Interface (from Rename on branch allocation)
    //=========================================================
    input  wire                     checkpoint_create_i,
    input  wire [ROB_IDX_BITS-1:0]  checkpoint_rob_idx_i,
    output wire [CHECKPOINT_BITS-1:0] checkpoint_id_o,
    output wire                     checkpoint_valid_o,
    
    //=========================================================
    // Recovery Interface (from Execute on misprediction)
    //=========================================================
    input  wire                     recover_valid_i,
    input  wire [CHECKPOINT_BITS-1:0] recover_id_i,
    input  wire                     recover_direction_i,  // Actual branch direction
    
    //=========================================================
    // Commit Interface (from ROB)
    //=========================================================
    input  wire                     commit_valid_i,
    input  wire [ROB_IDX_BITS-1:0]  commit_rob_idx_i,
    input  wire                     commit_is_branch_i,
    input  wire                     commit_taken_i,
    
    //=========================================================
    // Flush Interface
    //=========================================================
    input  wire                     flush_i,
    
    //=========================================================
    // GHR Output (to BPU components)
    //=========================================================
    output wire [GHR_WIDTH-1:0]     speculative_ghr_o,
    output wire [GHR_WIDTH-1:0]     committed_ghr_o,
    
    //=========================================================
    // Path History Output
    //=========================================================
    output wire [31:0]              path_history_o
);

    //=========================================================
    // Speculative GHR
    //=========================================================
    reg [GHR_WIDTH-1:0] spec_ghr;
    reg [GHR_WIDTH-1:0] committed_ghr;
    
    //=========================================================
    // Path History (XOR of branch PCs)
    //=========================================================
    reg [31:0] path_history;
    reg [31:0] committed_path_history;
    
    //=========================================================
    // Checkpoint Storage
    //=========================================================
    reg [GHR_WIDTH-1:0]     checkpoint_ghr     [0:NUM_CHECKPOINTS-1];
    reg [31:0]              checkpoint_path    [0:NUM_CHECKPOINTS-1];
    reg [ROB_IDX_BITS-1:0]  checkpoint_rob_idx [0:NUM_CHECKPOINTS-1];
    reg [NUM_CHECKPOINTS-1:0] checkpoint_valid;
    
    // Checkpoint allocation pointer (circular)
    reg [CHECKPOINT_BITS-1:0] alloc_ptr;
    
    integer i;
    
    //=========================================================
    // Outputs
    //=========================================================
    assign speculative_ghr_o = spec_ghr;
    assign committed_ghr_o = committed_ghr;
    assign path_history_o = path_history;
    
    // Find next free checkpoint
    wire [CHECKPOINT_BITS-1:0] next_checkpoint_id;
    wire has_free_checkpoint;
    
    reg [CHECKPOINT_BITS-1:0] free_id;
    reg found_free;
    
    always @(*) begin
        free_id = alloc_ptr;
        found_free = 0;
        
        for (i = 0; i < NUM_CHECKPOINTS; i = i + 1) begin
            if (!checkpoint_valid[(alloc_ptr + i) % NUM_CHECKPOINTS] && !found_free) begin
                free_id = (alloc_ptr + i) % NUM_CHECKPOINTS;
                found_free = 1;
            end
        end
    end
    
    assign next_checkpoint_id = free_id;
    assign has_free_checkpoint = found_free || !(&checkpoint_valid);
    assign checkpoint_id_o = next_checkpoint_id;
    assign checkpoint_valid_o = has_free_checkpoint;
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spec_ghr <= {GHR_WIDTH{1'b0}};
            committed_ghr <= {GHR_WIDTH{1'b0}};
            path_history <= 32'b0;
            committed_path_history <= 32'b0;
            checkpoint_valid <= {NUM_CHECKPOINTS{1'b0}};
            alloc_ptr <= 0;
            
            for (i = 0; i < NUM_CHECKPOINTS; i = i + 1) begin
                checkpoint_ghr[i] <= {GHR_WIDTH{1'b0}};
                checkpoint_path[i] <= 32'b0;
                checkpoint_rob_idx[i] <= 0;
            end
        end else if (flush_i) begin
            // On full flush, restore to committed state
            spec_ghr <= committed_ghr;
            path_history <= committed_path_history;
            checkpoint_valid <= {NUM_CHECKPOINTS{1'b0}};
            alloc_ptr <= 0;
        end else begin
            //=================================================
            // Speculative Update
            //=================================================
            if (update_valid_i && update_is_branch_i) begin
                // Shift GHR and insert new prediction
                spec_ghr <= {spec_ghr[GHR_WIDTH-2:0], update_taken_i};
                
                // Update path history
                path_history <= path_history ^ {update_pc_i[31:2], update_taken_i, 1'b0};
            end
            
            //=================================================
            // Checkpoint Creation
            //=================================================
            if (checkpoint_create_i && has_free_checkpoint) begin
                checkpoint_ghr[next_checkpoint_id] <= spec_ghr;
                checkpoint_path[next_checkpoint_id] <= path_history;
                checkpoint_rob_idx[next_checkpoint_id] <= checkpoint_rob_idx_i;
                checkpoint_valid[next_checkpoint_id] <= 1'b1;
                
                // Update allocation pointer
                alloc_ptr <= (next_checkpoint_id + 1) % NUM_CHECKPOINTS;
            end
            
            //=================================================
            // Recovery on Misprediction
            //=================================================
            if (recover_valid_i && checkpoint_valid[recover_id_i]) begin
                // Restore GHR from checkpoint
                spec_ghr <= {checkpoint_ghr[recover_id_i][GHR_WIDTH-2:0], recover_direction_i};
                
                // Restore path history (with correction for actual direction)
                path_history <= checkpoint_path[recover_id_i];
                
                // Invalidate this checkpoint and all younger ones
                for (i = 0; i < NUM_CHECKPOINTS; i = i + 1) begin
                    if (checkpoint_valid[i] && 
                        checkpoint_rob_idx[i] >= checkpoint_rob_idx[recover_id_i]) begin
                        checkpoint_valid[i] <= 1'b0;
                    end
                end
            end
            
            //=================================================
            // Commit
            //=================================================
            if (commit_valid_i && commit_is_branch_i) begin
                // Update committed GHR
                committed_ghr <= {committed_ghr[GHR_WIDTH-2:0], commit_taken_i};
                
                // Free checkpoints older than committed
                for (i = 0; i < NUM_CHECKPOINTS; i = i + 1) begin
                    if (checkpoint_valid[i] && 
                        checkpoint_rob_idx[i] <= commit_rob_idx_i) begin
                        checkpoint_valid[i] <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
