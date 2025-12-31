//=================================================================
// Module: rat
// Description: Register Alias Table (RAT)
//              Maps 32 architectural registers to 64 physical registers
//              Supports checkpoint creation and recovery
//              x0 always maps to P0 and is always ready
// Requirements: 3.1, 3.5, 3.6, 1.5
//=================================================================

`timescale 1ns/1ps

module rat #(
    parameter NUM_ARCH_REGS = 32,
    parameter NUM_PHYS_REGS = 64,
    parameter ARCH_REG_BITS = 5,
    parameter PHYS_REG_BITS = 6
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Rename lookup interface (2 source registers)
    input  wire [ARCH_REG_BITS-1:0] rs1_arch_i,
    input  wire [ARCH_REG_BITS-1:0] rs2_arch_i,
    output wire [PHYS_REG_BITS-1:0] rs1_phys_o,
    output wire [PHYS_REG_BITS-1:0] rs2_phys_o,
    output wire                     rs1_ready_o,
    output wire                     rs2_ready_o,
    
    // Rename update interface (destination register)
    input  wire                     rename_valid_i,
    input  wire [ARCH_REG_BITS-1:0] rd_arch_i,
    input  wire [PHYS_REG_BITS-1:0] rd_phys_new_i,    // New physical register
    output wire [PHYS_REG_BITS-1:0] rd_phys_old_o,    // Old physical register (for free list)
    
    // Ready bit update (from CDB)
    input  wire                     cdb_valid_i,
    input  wire [PHYS_REG_BITS-1:0] cdb_preg_i,
    
    // Checkpoint interface
    input  wire                     checkpoint_create_i,
    input  wire [2:0]               checkpoint_id_i,
    
    // Recovery interface
    input  wire                     recover_i,
    input  wire [2:0]               recover_id_i,
    
    // Commit interface (update committed RAT)
    input  wire                     commit_valid_i,
    input  wire [ARCH_REG_BITS-1:0] commit_rd_arch_i,
    input  wire [PHYS_REG_BITS-1:0] commit_rd_phys_i
);

    //=========================================================
    // RAT Storage
    //=========================================================
    // Speculative RAT
    reg [PHYS_REG_BITS-1:0] spec_rat [0:NUM_ARCH_REGS-1];
    reg                     spec_ready [0:NUM_ARCH_REGS-1];
    
    // Committed RAT (for recovery)
    reg [PHYS_REG_BITS-1:0] commit_rat [0:NUM_ARCH_REGS-1];
    
    // Checkpoints (8 checkpoints for branch speculation)
    reg [PHYS_REG_BITS-1:0] checkpoint_rat [0:7][0:NUM_ARCH_REGS-1];
    reg                     checkpoint_ready [0:7][0:NUM_ARCH_REGS-1];
    
    integer i, j;
    
    //=========================================================
    // Lookup Logic (combinational)
    //=========================================================
    // x0 always maps to P0 and is always ready
    assign rs1_phys_o = (rs1_arch_i == 5'd0) ? 6'd0 : spec_rat[rs1_arch_i];
    assign rs2_phys_o = (rs2_arch_i == 5'd0) ? 6'd0 : spec_rat[rs2_arch_i];
    assign rs1_ready_o = (rs1_arch_i == 5'd0) ? 1'b1 : spec_ready[rs1_arch_i];
    assign rs2_ready_o = (rs2_arch_i == 5'd0) ? 1'b1 : spec_ready[rs2_arch_i];
    
    // Old physical register for destination (for free list release)
    assign rd_phys_old_o = (rd_arch_i == 5'd0) ? 6'd0 : spec_rat[rd_arch_i];
    
    //=========================================================
    // RAT Update Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize: arch reg i maps to phys reg i
            for (i = 0; i < NUM_ARCH_REGS; i = i + 1) begin
                spec_rat[i] <= i[PHYS_REG_BITS-1:0];
                spec_ready[i] <= 1'b1;  // All initially ready
                commit_rat[i] <= i[PHYS_REG_BITS-1:0];
            end
            // Initialize checkpoints
            for (j = 0; j < 8; j = j + 1) begin
                for (i = 0; i < NUM_ARCH_REGS; i = i + 1) begin
                    checkpoint_rat[j][i] <= i[PHYS_REG_BITS-1:0];
                    checkpoint_ready[j][i] <= 1'b1;
                end
            end
        end else begin
            //=================================================
            // Recovery from checkpoint
            //=================================================
            if (recover_i) begin
                for (i = 0; i < NUM_ARCH_REGS; i = i + 1) begin
                    spec_rat[i] <= checkpoint_rat[recover_id_i][i];
                    spec_ready[i] <= checkpoint_ready[recover_id_i][i];
                end
            end else begin
                //=================================================
                // Normal rename update
                //=================================================
                if (rename_valid_i && rd_arch_i != 5'd0) begin
                    spec_rat[rd_arch_i] <= rd_phys_new_i;
                    spec_ready[rd_arch_i] <= 1'b0;  // New mapping not ready
                end
                
                //=================================================
                // CDB broadcast - mark register as ready
                //=================================================
                if (cdb_valid_i) begin
                    for (i = 1; i < NUM_ARCH_REGS; i = i + 1) begin
                        if (spec_rat[i] == cdb_preg_i) begin
                            spec_ready[i] <= 1'b1;
                        end
                    end
                    // Also update checkpoints
                    for (j = 0; j < 8; j = j + 1) begin
                        for (i = 1; i < NUM_ARCH_REGS; i = i + 1) begin
                            if (checkpoint_rat[j][i] == cdb_preg_i) begin
                                checkpoint_ready[j][i] <= 1'b1;
                            end
                        end
                    end
                end
            end
            
            //=================================================
            // Checkpoint creation
            //=================================================
            if (checkpoint_create_i && !recover_i) begin
                for (i = 0; i < NUM_ARCH_REGS; i = i + 1) begin
                    checkpoint_rat[checkpoint_id_i][i] <= spec_rat[i];
                    checkpoint_ready[checkpoint_id_i][i] <= spec_ready[i];
                end
            end
            
            //=================================================
            // Commit update
            //=================================================
            if (commit_valid_i && commit_rd_arch_i != 5'd0) begin
                commit_rat[commit_rd_arch_i] <= commit_rd_phys_i;
            end
        end
    end

endmodule
