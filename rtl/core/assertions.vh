//=================================================================
// File: assertions.vh
// Description: SystemVerilog Assertions for RISC-V OoO CPU
//              Provides property checks for formal verification
//              and simulation-time validation
// Requirements: 4.2, 4.3, 4.5
//=================================================================

`ifndef ASSERTIONS_VH
`define ASSERTIONS_VH

//=================================================================
// Assertion Macros (Verilog 2001 compatible)
//=================================================================

// Simple assertion check (for simulation)
`define ASSERT_ALWAYS(name, condition) \
    always @(posedge clk) begin \
        if (rst_n && !(condition)) begin \
            $display("ASSERTION FAILED: %s at time %0t", name, $time); \
        end \
    end

// Property check with message
`define ASSERT_PROPERTY(name, condition, message) \
    always @(posedge clk) begin \
        if (rst_n && !(condition)) begin \
            $display("ASSERTION FAILED: %s - %s at time %0t", name, message, $time); \
        end \
    end

// FIFO overflow check
`define ASSERT_NO_OVERFLOW(name, count, max_size) \
    always @(posedge clk) begin \
        if (rst_n && (count > max_size)) begin \
            $display("ASSERTION FAILED: %s overflow - count=%0d, max=%0d at time %0t", \
                     name, count, max_size, $time); \
        end \
    end

// FIFO underflow check
`define ASSERT_NO_UNDERFLOW(name, count) \
    always @(posedge clk) begin \
        if (rst_n && ($signed(count) < 0)) begin \
            $display("ASSERTION FAILED: %s underflow - count=%0d at time %0t", \
                     name, count, $time); \
        end \
    end

// Valid state check for FSM
`define ASSERT_VALID_STATE(name, state, valid_states) \
    always @(posedge clk) begin \
        if (rst_n) begin \
            case (state) \
                valid_states: ; /* Valid */ \
                default: $display("ASSERTION FAILED: %s invalid state=%0d at time %0t", \
                                  name, state, $time); \
            endcase \
        end \
    end

// No X/Z check for critical signals
`define ASSERT_NO_X(name, signal) \
    always @(posedge clk) begin \
        if (rst_n && $isunknown(signal)) begin \
            $display("ASSERTION FAILED: %s contains X/Z at time %0t", name, $time); \
        end \
    end

// Range check
`define ASSERT_IN_RANGE(name, value, min_val, max_val) \
    always @(posedge clk) begin \
        if (rst_n && ((value < min_val) || (value > max_val))) begin \
            $display("ASSERTION FAILED: %s out of range - value=%0d, range=[%0d,%0d] at time %0t", \
                     name, value, min_val, max_val, $time); \
        end \
    end

// One-hot check
`define ASSERT_ONEHOT(name, signal) \
    always @(posedge clk) begin \
        if (rst_n && (signal != 0) && ((signal & (signal - 1)) != 0)) begin \
            $display("ASSERTION FAILED: %s not one-hot - value=%b at time %0t", \
                     name, signal, $time); \
        end \
    end

// Mutual exclusion check
`define ASSERT_MUTEX(name, sig1, sig2) \
    always @(posedge clk) begin \
        if (rst_n && sig1 && sig2) begin \
            $display("ASSERTION FAILED: %s mutex violation at time %0t", name, $time); \
        end \
    end

// Handshake protocol check (valid must stay high until ready)
`define ASSERT_HANDSHAKE(name, valid, ready) \
    reg name``_valid_prev; \
    always @(posedge clk or negedge rst_n) begin \
        if (!rst_n) begin \
            name``_valid_prev <= 1'b0; \
        end else begin \
            if (name``_valid_prev && !ready && !valid) begin \
                $display("ASSERTION FAILED: %s handshake - valid dropped before ready at time %0t", \
                         name, $time); \
            end \
            name``_valid_prev <= valid; \
        end \
    end

`endif // ASSERTIONS_VH
