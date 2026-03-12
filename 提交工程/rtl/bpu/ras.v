//=================================================================
// Module: ras
// Description: Return Address Stack
//              16-entry stack for function return prediction
//              Supports checkpoint and recovery
// Requirements: 7.7
//=================================================================

`timescale 1ns/1ps

module ras #(
    parameter DEPTH     = 16,
    parameter PTR_BITS  = 4
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Push interface (on CALL)
    input  wire                    push_i,
    input  wire [31:0]             push_addr_i,
    
    // Pop interface (on RET)
    input  wire                    pop_i,
    output wire [31:0]             pop_addr_o,
    output wire                    valid_o,
    
    // Checkpoint interface
    input  wire                    checkpoint_i,
    output wire [PTR_BITS-1:0]     checkpoint_ptr_o,
    
    // Recovery interface
    input  wire                    recover_i,
    input  wire [PTR_BITS-1:0]     recover_ptr_i
);

    //=========================================================
    // Stack Storage
    //=========================================================
    reg [31:0]         stack [0:DEPTH-1];
    reg [PTR_BITS-1:0] tos;      // Top of stack pointer
    reg [PTR_BITS:0]   count;    // Number of valid entries
    
    integer i;
    
    //=========================================================
    // Output Logic
    //=========================================================
    assign pop_addr_o = stack[tos];
    assign valid_o = (count > 0);
    assign checkpoint_ptr_o = tos;
    
    //=========================================================
    // Stack Operations
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tos <= 0;
            count <= 0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                stack[i] <= 32'd0;
            end
        end else if (recover_i) begin
            // Recovery: restore TOS pointer
            tos <= recover_ptr_i;
            // Note: count is approximate after recovery
        end else begin
            case ({push_i, pop_i})
                2'b10: begin
                    // Push
                    if (count < DEPTH) begin
                        tos <= tos + 1;
                        stack[tos + 1] <= push_addr_i;
                        count <= count + 1;
                    end else begin
                        // Stack full: overwrite oldest (circular)
                        tos <= tos + 1;
                        stack[tos + 1] <= push_addr_i;
                    end
                end
                2'b01: begin
                    // Pop
                    if (count > 0) begin
                        tos <= tos - 1;
                        count <= count - 1;
                    end
                end
                2'b11: begin
                    // Push and Pop simultaneously (rare)
                    stack[tos] <= push_addr_i;
                end
                default: begin
                    // No operation
                end
            endcase
        end
    end

endmodule
