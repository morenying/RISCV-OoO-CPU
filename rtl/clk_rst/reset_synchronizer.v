//=============================================================================
// Module: reset_synchronizer
// Description: Asynchronous reset synchronizer with async assert, sync deassert
//              
// This module implements the industry-standard reset synchronization pattern:
//   - Reset ASSERTION is asynchronous (immediate response to async reset)
//   - Reset DEASSERTION is synchronous (aligned to clock edge)
//
// STRICT CONSTRAINTS:
//   - Must be 2-stage synchronizer minimum (3-stage for extra safety)
//   - Must NOT be a simple wire passthrough
//   - Reset release MUST be on clock rising edge
//   - Must handle metastability from async reset deassertion
//
// Requirements: 3.1, 3.2
//=============================================================================

`timescale 1ns/1ps

module reset_synchronizer #(
    // Number of synchronizer stages (minimum 2, recommended 3)
    parameter SYNC_STAGES = 3,
    // Reset polarity: 1 = active high, 0 = active low
    parameter RESET_ACTIVE_HIGH = 0
)(
    // Destination clock domain
    input  wire        clk,
    // Asynchronous reset input (directly from external source)
    input  wire        rst_async,
    // Synchronized reset output (safe to use in clk domain)
    output wire        rst_sync
);

    //=========================================================================
    // Parameter validation
    //=========================================================================
    initial begin
        if (SYNC_STAGES < 2) begin
            $error("SYNC_STAGES must be at least 2 for proper metastability handling");
        end
    end

    //=========================================================================
    // Synchronizer chain
    //
    // The key insight is:
    //   - Async reset SETS all flip-flops immediately (async set/reset)
    //   - When async reset releases, the '1' propagates through the chain
    //   - This ensures reset release is synchronized to clock
    //=========================================================================
    
    // For active-low reset (rst_async = 0 means reset)
    // We want rst_sync = 0 during reset, rst_sync = 1 during normal operation
    
    generate
        if (RESET_ACTIVE_HIGH == 0) begin : gen_active_low
            // Active-low reset: rst_async=0 means reset
            // Synchronizer chain with async clear
            
            reg [SYNC_STAGES-1:0] sync_chain;
            
            // Async assert (clear), sync deassert
            always @(posedge clk or negedge rst_async) begin
                if (!rst_async) begin
                    // Async reset assertion - immediate
                    sync_chain <= {SYNC_STAGES{1'b0}};
                end else begin
                    // Sync reset deassertion - shift in 1's
                    sync_chain <= {sync_chain[SYNC_STAGES-2:0], 1'b1};
                end
            end
            
            // Output is the last stage
            assign rst_sync = sync_chain[SYNC_STAGES-1];
            
        end else begin : gen_active_high
            // Active-high reset: rst_async=1 means reset
            // Synchronizer chain with async preset
            
            reg [SYNC_STAGES-1:0] sync_chain;
            
            // Async assert (preset), sync deassert
            always @(posedge clk or posedge rst_async) begin
                if (rst_async) begin
                    // Async reset assertion - immediate
                    sync_chain <= {SYNC_STAGES{1'b1}};
                end else begin
                    // Sync reset deassertion - shift in 0's
                    sync_chain <= {sync_chain[SYNC_STAGES-2:0], 1'b0};
                end
            end
            
            // Output is the last stage
            assign rst_sync = sync_chain[SYNC_STAGES-1];
        end
    endgenerate

    //=========================================================================
    // Assertions for verification
    //=========================================================================
    
`ifdef SIMULATION
    // Track reset transitions for verification
    reg rst_async_prev;
    reg rst_sync_prev;
    
    always @(posedge clk) begin
        rst_async_prev <= rst_async;
        rst_sync_prev <= rst_sync;
    end
    
    // Property: Reset assertion should be fast (within 1-2 cycles)
    // Note: Due to async nature, assertion is actually immediate
    
    // Property: Reset deassertion should take SYNC_STAGES cycles
    // This is verified by observing the delay between rst_async release
    // and rst_sync release
    
    // Property: rst_sync should never have X or Z
    always @(posedge clk) begin
        if (rst_sync === 1'bx || rst_sync === 1'bz) begin
            $error("ASSERTION FAILED: rst_sync has X or Z value");
        end
    end
`endif

endmodule

//=============================================================================
// Module: reset_synchronizer_with_filter
// Description: Reset synchronizer with glitch filter for noisy reset sources
//              
// Adds a glitch filter that requires reset to be stable for a minimum
// number of cycles before recognizing it.
//=============================================================================

module reset_synchronizer_with_filter #(
    parameter SYNC_STAGES = 3,
    parameter RESET_ACTIVE_HIGH = 0,
    // Minimum cycles reset must be stable to be recognized
    parameter FILTER_CYCLES = 4
)(
    input  wire        clk,
    input  wire        rst_async,
    output wire        rst_sync
);

    //=========================================================================
    // First stage: Basic synchronization of async reset
    //=========================================================================
    reg [1:0] rst_meta_sync;
    wire      rst_async_internal = RESET_ACTIVE_HIGH ? rst_async : ~rst_async;
    
    always @(posedge clk or posedge rst_async_internal) begin
        if (rst_async_internal) begin
            rst_meta_sync <= 2'b11;
        end else begin
            rst_meta_sync <= {rst_meta_sync[0], 1'b0};
        end
    end
    
    wire rst_synced = rst_meta_sync[1];
    
    //=========================================================================
    // Second stage: Glitch filter
    // Requires reset to be stable for FILTER_CYCLES before changing output
    //=========================================================================
    reg [$clog2(FILTER_CYCLES+1)-1:0] filter_cnt;
    reg rst_filtered;
    
    always @(posedge clk or posedge rst_async_internal) begin
        if (rst_async_internal) begin
            filter_cnt <= 0;
            rst_filtered <= 1'b1;
        end else begin
            if (rst_synced != rst_filtered) begin
                // Input differs from output, count
                if (filter_cnt < FILTER_CYCLES) begin
                    filter_cnt <= filter_cnt + 1;
                end else begin
                    // Stable long enough, update output
                    rst_filtered <= rst_synced;
                    filter_cnt <= 0;
                end
            end else begin
                // Input matches output, reset counter
                filter_cnt <= 0;
            end
        end
    end
    
    //=========================================================================
    // Third stage: Final synchronizer chain
    //=========================================================================
    reg [SYNC_STAGES-1:0] final_sync;
    
    always @(posedge clk or posedge rst_async_internal) begin
        if (rst_async_internal) begin
            final_sync <= {SYNC_STAGES{1'b1}};
        end else begin
            final_sync <= {final_sync[SYNC_STAGES-2:0], rst_filtered};
        end
    end
    
    // Convert back to original polarity
    assign rst_sync = RESET_ACTIVE_HIGH ? final_sync[SYNC_STAGES-1] 
                                        : ~final_sync[SYNC_STAGES-1];

endmodule
