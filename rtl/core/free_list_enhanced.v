//=================================================================
// Module: free_list_enhanced
// Description: Enhanced Free List for Physical Register Management
//              128 physical registers (doubled from 64)
//              Dual allocation and dual release ports
//              Checkpoint mechanism for fast branch recovery
// Requirements: 4.5, 4.6
//=================================================================

`timescale 1ns/1ps

module free_list_enhanced #(
    parameter NUM_PHYS_REGS   = 128,
    parameter PHYS_REG_BITS   = 7,        // log2(128)
    parameter NUM_ARCH_REGS   = 32,
    parameter NUM_CHECKPOINTS = 8
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Dual Allocation Interface (from Rename stage)
    //=========================================================
    // Port 0
    input  wire                     alloc0_req_i,
    output wire                     alloc0_valid_o,
    output wire [PHYS_REG_BITS-1:0] alloc0_preg_o,
    
    // Port 1
    input  wire                     alloc1_req_i,
    output wire                     alloc1_valid_o,
    output wire [PHYS_REG_BITS-1:0] alloc1_preg_o,
    
    //=========================================================
    // Dual Release Interface (from Commit stage)
    //=========================================================
    // Port 0
    input  wire                     release0_valid_i,
    input  wire [PHYS_REG_BITS-1:0] release0_preg_i,
    
    // Port 1
    input  wire                     release1_valid_i,
    input  wire [PHYS_REG_BITS-1:0] release1_preg_i,
    
    //=========================================================
    // Checkpoint Interface
    //=========================================================
    input  wire                     checkpoint_create_i,
    input  wire [2:0]               checkpoint_id_i,
    
    input  wire                     recover_i,
    input  wire [2:0]               recover_id_i,
    
    //=========================================================
    // Flush Interface
    //=========================================================
    input  wire                     flush_i,
    
    //=========================================================
    // Status
    //=========================================================
    output wire                     empty_o,        // No free registers
    output wire                     almost_empty_o, // Less than 4 free
    output wire [PHYS_REG_BITS:0]   free_count_o
);

    //=========================================================
    // Free List Storage (FIFO queue)
    //=========================================================
    localparam QUEUE_SIZE = NUM_PHYS_REGS;
    localparam PTR_BITS = PHYS_REG_BITS + 1;
    
    reg [PHYS_REG_BITS-1:0] free_queue [0:QUEUE_SIZE-1];
    reg [PTR_BITS-1:0] head;  // Allocation pointer
    reg [PTR_BITS-1:0] tail;  // Release pointer
    reg [PTR_BITS-1:0] count;
    
    //=========================================================
    // Checkpoint Storage
    //=========================================================
    reg [PTR_BITS-1:0] checkpoint_head  [0:NUM_CHECKPOINTS-1];
    reg [PTR_BITS-1:0] checkpoint_count [0:NUM_CHECKPOINTS-1];
    // Store a bitmap for more accurate recovery
    reg [NUM_PHYS_REGS-1:0] checkpoint_free_bitmap [0:NUM_CHECKPOINTS-1];
    reg [NUM_PHYS_REGS-1:0] free_bitmap;  // Current free bitmap
    
    //=========================================================
    // Pointer Calculations
    //=========================================================
    wire [PTR_BITS-1:0] head_plus_1 = (head == QUEUE_SIZE - 1) ? 0 : head + 1;
    wire [PTR_BITS-1:0] head_plus_2 = (head >= QUEUE_SIZE - 2) ? head + 2 - QUEUE_SIZE : head + 2;
    wire [PTR_BITS-1:0] tail_plus_1 = (tail == QUEUE_SIZE - 1) ? 0 : tail + 1;
    wire [PTR_BITS-1:0] tail_plus_2 = (tail >= QUEUE_SIZE - 2) ? tail + 2 - QUEUE_SIZE : tail + 2;
    
    //=========================================================
    // Status Signals
    //=========================================================
    assign empty_o = (count == 0);
    assign almost_empty_o = (count < 4);
    assign free_count_o = count[PHYS_REG_BITS:0];
    
    //=========================================================
    // Allocation Outputs
    //=========================================================
    assign alloc0_valid_o = (count >= 1);
    assign alloc1_valid_o = (count >= 2);
    
    assign alloc0_preg_o = free_queue[head[PHYS_REG_BITS-1:0]];
    assign alloc1_preg_o = free_queue[head_plus_1[PHYS_REG_BITS-1:0]];
    
    integer i;
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize free list with registers 32-127
            // (0-31 are initially mapped to arch registers)
            head <= 0;
            tail <= NUM_PHYS_REGS - NUM_ARCH_REGS;
            count <= NUM_PHYS_REGS - NUM_ARCH_REGS;
            
            for (i = 0; i < NUM_PHYS_REGS - NUM_ARCH_REGS; i = i + 1) begin
                free_queue[i] <= i + NUM_ARCH_REGS;  // Put regs 32-127 in queue
            end
            
            // Initialize free bitmap (0-31 not free, 32-127 free)
            free_bitmap <= {{(NUM_PHYS_REGS-NUM_ARCH_REGS){1'b1}}, {NUM_ARCH_REGS{1'b0}}};
            
            for (i = 0; i < NUM_CHECKPOINTS; i = i + 1) begin
                checkpoint_head[i] <= 0;
                checkpoint_count[i] <= NUM_PHYS_REGS - NUM_ARCH_REGS;
                checkpoint_free_bitmap[i] <= {{(NUM_PHYS_REGS-NUM_ARCH_REGS){1'b1}}, {NUM_ARCH_REGS{1'b0}}};
            end
        end else if (flush_i) begin
            // Full flush: reset to initial state
            head <= 0;
            tail <= NUM_PHYS_REGS - NUM_ARCH_REGS;
            count <= NUM_PHYS_REGS - NUM_ARCH_REGS;
            
            for (i = 0; i < NUM_PHYS_REGS - NUM_ARCH_REGS; i = i + 1) begin
                free_queue[i] <= i + NUM_ARCH_REGS;
            end
            
            free_bitmap <= {{(NUM_PHYS_REGS-NUM_ARCH_REGS){1'b1}}, {NUM_ARCH_REGS{1'b0}}};
        end else if (recover_i) begin
            // Recover to checkpoint
            head <= checkpoint_head[recover_id_i];
            count <= checkpoint_count[recover_id_i];
            free_bitmap <= checkpoint_free_bitmap[recover_id_i];
            // Note: tail doesn't need to be restored as we use bitmap for recovery
        end else begin
            //=================================================
            // Checkpoint Creation
            //=================================================
            if (checkpoint_create_i) begin
                checkpoint_head[checkpoint_id_i] <= head;
                checkpoint_count[checkpoint_id_i] <= count;
                checkpoint_free_bitmap[checkpoint_id_i] <= free_bitmap;
            end
            
            //=================================================
            // Allocation Logic
            //=================================================
            if (alloc0_req_i && alloc0_valid_o) begin
                free_bitmap[alloc0_preg_o] <= 1'b0;
                
                if (alloc1_req_i && alloc1_valid_o) begin
                    // Dual allocation
                    free_bitmap[alloc1_preg_o] <= 1'b0;
                    head <= head_plus_2;
                end else begin
                    head <= head_plus_1;
                end
            end else if (alloc1_req_i && alloc1_valid_o) begin
                // Only second allocation (unusual)
                free_bitmap[alloc1_preg_o] <= 1'b0;
                head <= head_plus_1;
            end
            
            //=================================================
            // Release Logic
            //=================================================
            if (release0_valid_i && (release0_preg_i >= NUM_ARCH_REGS)) begin
                free_queue[tail[PHYS_REG_BITS-1:0]] <= release0_preg_i;
                free_bitmap[release0_preg_i] <= 1'b1;
                
                if (release1_valid_i && (release1_preg_i >= NUM_ARCH_REGS)) begin
                    // Dual release
                    free_queue[tail_plus_1[PHYS_REG_BITS-1:0]] <= release1_preg_i;
                    free_bitmap[release1_preg_i] <= 1'b1;
                    tail <= tail_plus_2;
                end else begin
                    tail <= tail_plus_1;
                end
            end else if (release1_valid_i && (release1_preg_i >= NUM_ARCH_REGS)) begin
                // Only second release
                free_queue[tail[PHYS_REG_BITS-1:0]] <= release1_preg_i;
                free_bitmap[release1_preg_i] <= 1'b1;
                tail <= tail_plus_1;
            end
            
            //=================================================
            // Count Update
            //=================================================
            begin
                reg [2:0] alloc_cnt;
                reg [1:0] release_cnt;
                
                alloc_cnt = (alloc0_req_i && alloc0_valid_o ? 1 : 0) +
                            (alloc1_req_i && alloc1_valid_o ? 1 : 0);
                release_cnt = (release0_valid_i && (release0_preg_i >= NUM_ARCH_REGS) ? 1 : 0) +
                              (release1_valid_i && (release1_preg_i >= NUM_ARCH_REGS) ? 1 : 0);
                
                count <= count - alloc_cnt + release_cnt;
            end
        end
    end

endmodule
