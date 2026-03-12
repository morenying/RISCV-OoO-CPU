//=================================================================
// Module: free_list
// Description: Free List for Physical Register Management
//              FIFO structure managing 64 physical registers
//              Supports allocation and release operations
// Requirements: 3.2, 3.3, 3.4
//=================================================================

`timescale 1ns/1ps

module free_list #(
    parameter NUM_PHYS_REGS = 64,
    parameter PHYS_REG_BITS = 6
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Allocation interface (from Rename stage)
    input  wire                     alloc_req_i,      // Request to allocate a register
    output wire [PHYS_REG_BITS-1:0] alloc_preg_o,     // Allocated physical register
    output wire                     alloc_valid_o,    // Allocation successful
    
    // Release interface (from Commit stage)
    input  wire                     release_req_i,    // Request to release a register
    input  wire [PHYS_REG_BITS-1:0] release_preg_i,   // Physical register to release
    
    // Recovery interface (for branch misprediction)
    input  wire                     recover_i,        // Recover to checkpoint
    input  wire [PHYS_REG_BITS-1:0] recover_head_i,   // Head pointer at checkpoint
    input  wire [PHYS_REG_BITS-1:0] recover_tail_i,   // Tail pointer at checkpoint
    input  wire [PHYS_REG_BITS-1:0] recover_count_i,  // Count at checkpoint
    
    // Checkpoint interface
    output wire [PHYS_REG_BITS-1:0] checkpoint_head_o,
    output wire [PHYS_REG_BITS-1:0] checkpoint_tail_o,
    output wire [PHYS_REG_BITS-1:0] checkpoint_count_o,
    
    // Status
    output wire                     empty_o,
    output wire                     full_o,
    output wire [PHYS_REG_BITS-1:0] free_count_o
);

    //=========================================================
    // Internal Signals
    //=========================================================
    reg [PHYS_REG_BITS-1:0] fifo [0:NUM_PHYS_REGS-1];
    reg [PHYS_REG_BITS-1:0] head;      // Read pointer
    reg [PHYS_REG_BITS-1:0] tail;      // Write pointer
    reg [PHYS_REG_BITS-1:0] count;     // Number of free registers
    
    integer i;
    
    //=========================================================
    // Output Assignments
    //=========================================================
    assign alloc_preg_o = fifo[head];
    // alloc_valid_o indicates a register is available for allocation
    // NOT dependent on alloc_req_i to avoid combinational loop
    assign alloc_valid_o = !empty_o;
    
    assign empty_o = (count == 0);
    assign full_o = (count == NUM_PHYS_REGS);
    assign free_count_o = count;
    
    assign checkpoint_head_o = head;
    assign checkpoint_tail_o = tail;
    assign checkpoint_count_o = count;
    
    //=========================================================
    // FIFO Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize: P0 is reserved for x0, P1-P31 map to x1-x31
            // P32-P63 are initially free
            head <= 6'd0;   // Start reading from index 0
            tail <= 6'd32;  // Next write position after initial entries
            count <= 6'd32; // 32 free registers (P32-P63)
            
            // Initialize FIFO with free registers P32-P63 at indices 0-31
            for (i = 0; i < NUM_PHYS_REGS; i = i + 1) begin
                if (i < 32) begin
                    fifo[i] <= i + 32;  // fifo[0]=P32, fifo[1]=P33, ..., fifo[31]=P63
                end else begin
                    fifo[i] <= 6'd0;    // Unused initially
                end
            end
        end else if (recover_i) begin
            // Recovery: restore checkpoint state
            head <= recover_head_i;
            tail <= recover_tail_i;
            count <= recover_count_i;
        end else begin
            // Normal operation
            case ({alloc_req_i && !empty_o, release_req_i && !full_o})
                2'b10: begin
                    // Allocation only
                    head <= (head == NUM_PHYS_REGS - 1) ? 6'd0 : head + 1;
                    count <= count - 1;
                end
                2'b01: begin
                    // Release only
                    fifo[tail] <= release_preg_i;
                    tail <= (tail == NUM_PHYS_REGS - 1) ? 6'd0 : tail + 1;
                    count <= count + 1;
                end
                2'b11: begin
                    // Both allocation and release
                    head <= (head == NUM_PHYS_REGS - 1) ? 6'd0 : head + 1;
                    fifo[tail] <= release_preg_i;
                    tail <= (tail == NUM_PHYS_REGS - 1) ? 6'd0 : tail + 1;
                    // count stays the same
                end
                default: begin
                    // No operation
                end
            endcase
        end
    end

endmodule
