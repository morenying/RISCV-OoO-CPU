//=================================================================
// Module: reservation_station
// Description: Parameterized Reservation Station
//              CDB monitoring and operand capture
//              Oldest-first issue selection
// Requirements: 4.1, 4.2, 4.3, 4.4
//=================================================================

`timescale 1ns/1ps

module reservation_station #(
    parameter NUM_ENTRIES    = 4,
    parameter ENTRY_IDX_BITS = 2,
    parameter PHYS_REG_BITS  = 6,
    parameter DATA_WIDTH     = 32,
    parameter ROB_IDX_BITS   = 5,
    parameter ALU_OP_WIDTH   = 4
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Dispatch interface
    input  wire                     dispatch_valid_i,
    output wire                     dispatch_ready_o,
    input  wire [ALU_OP_WIDTH-1:0]  dispatch_op_i,
    input  wire [PHYS_REG_BITS-1:0] dispatch_src1_preg_i,
    input  wire [DATA_WIDTH-1:0]    dispatch_src1_data_i,
    input  wire                     dispatch_src1_ready_i,
    input  wire [PHYS_REG_BITS-1:0] dispatch_src2_preg_i,
    input  wire [DATA_WIDTH-1:0]    dispatch_src2_data_i,
    input  wire                     dispatch_src2_ready_i,
    input  wire [PHYS_REG_BITS-1:0] dispatch_dst_preg_i,
    input  wire [ROB_IDX_BITS-1:0]  dispatch_rob_idx_i,
    input  wire [DATA_WIDTH-1:0]    dispatch_imm_i,
    input  wire                     dispatch_use_imm_i,
    input  wire [DATA_WIDTH-1:0]    dispatch_pc_i,
    
    // Issue interface
    output reg                      issue_valid_o,
    input  wire                     issue_ready_i,
    output reg  [ALU_OP_WIDTH-1:0]  issue_op_o,
    output reg  [DATA_WIDTH-1:0]    issue_src1_data_o,
    output reg  [DATA_WIDTH-1:0]    issue_src2_data_o,
    output reg  [PHYS_REG_BITS-1:0] issue_dst_preg_o,
    output reg  [ROB_IDX_BITS-1:0]  issue_rob_idx_o,
    output reg  [DATA_WIDTH-1:0]    issue_pc_o,
    
    // CDB interface (for operand capture)
    input  wire                     cdb_valid_i,
    input  wire [PHYS_REG_BITS-1:0] cdb_preg_i,
    input  wire [DATA_WIDTH-1:0]    cdb_data_i,
    
    // Flush interface
    input  wire                     flush_i,
    
    // Status
    output wire                     empty_o,
    output wire                     full_o
);

    //=========================================================
    // Entry Storage
    //=========================================================
    reg                     valid      [0:NUM_ENTRIES-1];
    reg [ALU_OP_WIDTH-1:0]  op         [0:NUM_ENTRIES-1];
    reg [PHYS_REG_BITS-1:0] src1_preg  [0:NUM_ENTRIES-1];
    reg [DATA_WIDTH-1:0]    src1_data  [0:NUM_ENTRIES-1];
    reg                     src1_ready [0:NUM_ENTRIES-1];
    reg [PHYS_REG_BITS-1:0] src2_preg  [0:NUM_ENTRIES-1];
    reg [DATA_WIDTH-1:0]    src2_data  [0:NUM_ENTRIES-1];
    reg                     src2_ready [0:NUM_ENTRIES-1];
    reg [PHYS_REG_BITS-1:0] dst_preg   [0:NUM_ENTRIES-1];
    reg [ROB_IDX_BITS-1:0]  rob_idx    [0:NUM_ENTRIES-1];
    reg [DATA_WIDTH-1:0]    pc         [0:NUM_ENTRIES-1];
    reg [ROB_IDX_BITS-1:0]  age        [0:NUM_ENTRIES-1];  // For oldest-first selection
    
    integer i;
    
    //=========================================================
    // Status Signals
    //=========================================================
    reg [ENTRY_IDX_BITS:0] count;
    
    assign empty_o = (count == 0);
    assign full_o = (count == NUM_ENTRIES);
    assign dispatch_ready_o = !full_o;
    
    //=========================================================
    // Find Free Entry
    //=========================================================
    reg [ENTRY_IDX_BITS-1:0] free_idx;
    reg                      free_found;
    
    always @(*) begin
        free_idx = 0;
        free_found = 0;
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (!valid[i] && !free_found) begin
                free_idx = i[ENTRY_IDX_BITS-1:0];
                free_found = 1;
            end
        end
    end
    
    //=========================================================
    // Find Ready Entry (oldest-first)
    //=========================================================
    reg [ENTRY_IDX_BITS-1:0] issue_idx;
    reg                      issue_found;
    reg [ROB_IDX_BITS-1:0]   oldest_age;
    
    always @(*) begin
        issue_idx = 0;
        issue_found = 0;
        oldest_age = {ROB_IDX_BITS{1'b1}};  // Max value
        
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (valid[i] && src1_ready[i] && src2_ready[i]) begin
                // Compare ages (smaller age = older instruction)
                if (!issue_found || (age[i] < oldest_age)) begin
                    issue_idx = i[ENTRY_IDX_BITS-1:0];
                    issue_found = 1;
                    oldest_age = age[i];
                end
            end
        end
    end

    //=========================================================
    // Issue Output Logic
    //=========================================================
    always @(*) begin
        issue_valid_o = issue_found;
        issue_op_o = op[issue_idx];
        issue_src1_data_o = src1_data[issue_idx];
        issue_src2_data_o = src2_data[issue_idx];
        issue_dst_preg_o = dst_preg[issue_idx];
        issue_rob_idx_o = rob_idx[issue_idx];
        issue_pc_o = pc[issue_idx];
    end
    
    //=========================================================
    // Age Counter
    //=========================================================
    reg [ROB_IDX_BITS-1:0] age_counter;
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
            age_counter <= 0;
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 0;
                op[i] <= 0;
                src1_preg[i] <= 0;
                src1_data[i] <= 0;
                src1_ready[i] <= 0;
                src2_preg[i] <= 0;
                src2_data[i] <= 0;
                src2_ready[i] <= 0;
                dst_preg[i] <= 0;
                rob_idx[i] <= 0;
                pc[i] <= 0;
                age[i] <= 0;
            end
        end else if (flush_i) begin
            // Flush all entries
            count <= 0;
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 0;
            end
        end else begin
            //=================================================
            // CDB Operand Capture
            //=================================================
            if (cdb_valid_i) begin
                for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                    if (valid[i]) begin
                        // Check src1
                        if (!src1_ready[i] && src1_preg[i] == cdb_preg_i) begin
                            src1_data[i] <= cdb_data_i;
                            src1_ready[i] <= 1'b1;
                        end
                        // Check src2
                        if (!src2_ready[i] && src2_preg[i] == cdb_preg_i) begin
                            src2_data[i] <= cdb_data_i;
                            src2_ready[i] <= 1'b1;
                        end
                    end
                end
            end
            
            //=================================================
            // Dispatch (allocate new entry)
            //=================================================
            if (dispatch_valid_i && !full_o) begin
                valid[free_idx] <= 1'b1;
                op[free_idx] <= dispatch_op_i;
                dst_preg[free_idx] <= dispatch_dst_preg_i;
                rob_idx[free_idx] <= dispatch_rob_idx_i;
                pc[free_idx] <= dispatch_pc_i;
                age[free_idx] <= age_counter;
                age_counter <= age_counter + 1;
                
                // Source 1: check CDB bypass
                if (cdb_valid_i && !dispatch_src1_ready_i && 
                    dispatch_src1_preg_i == cdb_preg_i) begin
                    src1_preg[free_idx] <= dispatch_src1_preg_i;
                    src1_data[free_idx] <= cdb_data_i;
                    src1_ready[free_idx] <= 1'b1;
                end else begin
                    src1_preg[free_idx] <= dispatch_src1_preg_i;
                    src1_data[free_idx] <= dispatch_src1_data_i;
                    src1_ready[free_idx] <= dispatch_src1_ready_i;
                end
                
                // Source 2: check CDB bypass or immediate
                if (dispatch_use_imm_i) begin
                    src2_preg[free_idx] <= 6'd0;
                    src2_data[free_idx] <= dispatch_imm_i;
                    src2_ready[free_idx] <= 1'b1;
                end else if (cdb_valid_i && !dispatch_src2_ready_i && 
                             dispatch_src2_preg_i == cdb_preg_i) begin
                    src2_preg[free_idx] <= dispatch_src2_preg_i;
                    src2_data[free_idx] <= cdb_data_i;
                    src2_ready[free_idx] <= 1'b1;
                end else begin
                    src2_preg[free_idx] <= dispatch_src2_preg_i;
                    src2_data[free_idx] <= dispatch_src2_data_i;
                    src2_ready[free_idx] <= dispatch_src2_ready_i;
                end
            end
            
            //=================================================
            // Issue (deallocate entry)
            //=================================================
            if (issue_found && issue_ready_i) begin
                valid[issue_idx] <= 1'b0;
            end
            
            //=================================================
            // Update Count
            //=================================================
            case ({dispatch_valid_i && !full_o, issue_found && issue_ready_i})
                2'b10: count <= count + 1;
                2'b01: count <= count - 1;
                default: ; // count stays same
            endcase
        end
    end

endmodule
