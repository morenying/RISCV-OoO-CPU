//=================================================================
// Module: atomic_unit
// Description: Atomic Instruction Execution Unit
//              Supports LR/SC (Load Reserved / Store Conditional)
//              Supports AMO (Atomic Memory Operations)
//              Required for Linux SMP and synchronization
//=================================================================

`timescale 1ns/1ps

module atomic_unit #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter RESERVATION_SETS = 4   // Number of reservation set entries
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Issue Interface
    //=========================================================
    input  wire                     req_valid_i,
    output wire                     req_ready_o,
    input  wire [4:0]               req_op_i,         // Atomic operation code
    input  wire [ADDR_WIDTH-1:0]    req_addr_i,       // Memory address
    input  wire [DATA_WIDTH-1:0]    req_rs1_data_i,   // rs1 data (for AMO src)
    input  wire [DATA_WIDTH-1:0]    req_rs2_data_i,   // rs2 data (store data)
    input  wire                     req_aq_i,         // Acquire ordering
    input  wire                     req_rl_i,         // Release ordering
    input  wire [4:0]               req_rd_i,         // Destination register
    input  wire [5:0]               req_rob_idx_i,    // ROB index
    
    //=========================================================
    // Response Interface
    //=========================================================
    output reg                      resp_valid_o,
    output reg  [DATA_WIDTH-1:0]    resp_data_o,      // Result data
    output reg  [4:0]               resp_rd_o,
    output reg  [5:0]               resp_rob_idx_o,
    output reg                      resp_sc_fail_o,   // SC failed flag
    
    //=========================================================
    // Memory Interface
    //=========================================================
    output reg                      mem_req_valid_o,
    output reg                      mem_req_we_o,
    output reg  [ADDR_WIDTH-1:0]    mem_req_addr_o,
    output reg  [DATA_WIDTH-1:0]    mem_req_wdata_o,
    input  wire                     mem_req_ready_i,
    
    input  wire                     mem_resp_valid_i,
    input  wire [DATA_WIDTH-1:0]    mem_resp_data_i,
    
    //=========================================================
    // Snoop Interface (for reservation invalidation)
    //=========================================================
    input  wire                     snoop_valid_i,
    input  wire [ADDR_WIDTH-1:0]    snoop_addr_i,
    input  wire                     snoop_we_i,       // Is it a write?
    
    //=========================================================
    // Pipeline Control
    //=========================================================
    input  wire                     flush_i,
    input  wire [5:0]               flush_rob_idx_i
);

    //=========================================================
    // Atomic Operation Codes
    //=========================================================
    localparam OP_LR    = 5'b00010;   // Load Reserved
    localparam OP_SC    = 5'b00011;   // Store Conditional
    localparam OP_SWAP  = 5'b00001;   // AMOSWAP
    localparam OP_ADD   = 5'b00000;   // AMOADD
    localparam OP_XOR   = 5'b00100;   // AMOXOR
    localparam OP_AND   = 5'b01100;   // AMOAND
    localparam OP_OR    = 5'b01000;   // AMOOR
    localparam OP_MIN   = 5'b10000;   // AMOMIN
    localparam OP_MAX   = 5'b10100;   // AMOMAX
    localparam OP_MINU  = 5'b11000;   // AMOMINU
    localparam OP_MAXU  = 5'b11100;   // AMOMAXU
    
    //=========================================================
    // State Machine
    //=========================================================
    localparam STATE_IDLE       = 4'd0;
    localparam STATE_LR_READ    = 4'd1;
    localparam STATE_LR_WAIT    = 4'd2;
    localparam STATE_SC_CHECK   = 4'd3;
    localparam STATE_SC_WRITE   = 4'd4;
    localparam STATE_SC_WAIT    = 4'd5;
    localparam STATE_AMO_READ   = 4'd6;
    localparam STATE_AMO_WAIT   = 4'd7;
    localparam STATE_AMO_CALC   = 4'd8;
    localparam STATE_AMO_WRITE  = 4'd9;
    localparam STATE_AMO_WBWAIT = 4'd10;
    localparam STATE_DONE       = 4'd11;
    
    reg [3:0] state;
    reg [3:0] next_state;
    
    //=========================================================
    // Reservation Set (for LR/SC)
    //=========================================================
    reg [RESERVATION_SETS-1:0] rsrv_valid;
    reg [ADDR_WIDTH-1:0]       rsrv_addr [0:RESERVATION_SETS-1];
    
    // Check if address has valid reservation
    wire rsrv_hit;
    reg [1:0] rsrv_hit_idx;
    
    integer i;
    always @(*) begin
        rsrv_hit_idx = 0;
        for (i = 0; i < RESERVATION_SETS; i = i + 1) begin
            if (rsrv_valid[i] && (rsrv_addr[i][ADDR_WIDTH-1:2] == req_addr_i[ADDR_WIDTH-1:2])) begin
                rsrv_hit_idx = i[1:0];
            end
        end
    end
    
    assign rsrv_hit = |rsrv_valid && 
                      ((rsrv_addr[0][ADDR_WIDTH-1:2] == req_addr_i[ADDR_WIDTH-1:2] && rsrv_valid[0]) ||
                       (rsrv_addr[1][ADDR_WIDTH-1:2] == req_addr_i[ADDR_WIDTH-1:2] && rsrv_valid[1]) ||
                       (rsrv_addr[2][ADDR_WIDTH-1:2] == req_addr_i[ADDR_WIDTH-1:2] && rsrv_valid[2]) ||
                       (rsrv_addr[3][ADDR_WIDTH-1:2] == req_addr_i[ADDR_WIDTH-1:2] && rsrv_valid[3]));
    
    // LRU for reservation replacement
    reg [1:0] rsrv_lru_ptr;
    
    //=========================================================
    // Saved Request
    //=========================================================
    reg [4:0]               saved_op;
    reg [ADDR_WIDTH-1:0]    saved_addr;
    reg [DATA_WIDTH-1:0]    saved_rs2_data;
    reg                     saved_aq;
    reg                     saved_rl;
    reg [4:0]               saved_rd;
    reg [5:0]               saved_rob_idx;
    
    // Saved memory read data
    reg [DATA_WIDTH-1:0]    mem_read_data;
    
    // AMO result
    reg [DATA_WIDTH-1:0]    amo_result;
    
    //=========================================================
    // AMO ALU
    //=========================================================
    wire signed [DATA_WIDTH-1:0] mem_signed = $signed(mem_read_data);
    wire signed [DATA_WIDTH-1:0] rs2_signed = $signed(saved_rs2_data);
    
    always @(*) begin
        case (saved_op)
            OP_SWAP: amo_result = saved_rs2_data;
            OP_ADD:  amo_result = mem_read_data + saved_rs2_data;
            OP_XOR:  amo_result = mem_read_data ^ saved_rs2_data;
            OP_AND:  amo_result = mem_read_data & saved_rs2_data;
            OP_OR:   amo_result = mem_read_data | saved_rs2_data;
            OP_MIN:  amo_result = (mem_signed < rs2_signed) ? mem_read_data : saved_rs2_data;
            OP_MAX:  amo_result = (mem_signed > rs2_signed) ? mem_read_data : saved_rs2_data;
            OP_MINU: amo_result = (mem_read_data < saved_rs2_data) ? mem_read_data : saved_rs2_data;
            OP_MAXU: amo_result = (mem_read_data > saved_rs2_data) ? mem_read_data : saved_rs2_data;
            default: amo_result = saved_rs2_data;
        endcase
    end
    
    //=========================================================
    // Ready Signal
    //=========================================================
    assign req_ready_o = (state == STATE_IDLE);
    
    //=========================================================
    // State Transition Logic
    //=========================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            STATE_IDLE: begin
                if (req_valid_i) begin
                    case (req_op_i)
                        OP_LR:   next_state = STATE_LR_READ;
                        OP_SC:   next_state = STATE_SC_CHECK;
                        default: next_state = STATE_AMO_READ;  // All AMO ops
                    endcase
                end
            end
            
            // LR states
            STATE_LR_READ: begin
                if (mem_req_ready_i) next_state = STATE_LR_WAIT;
            end
            
            STATE_LR_WAIT: begin
                if (mem_resp_valid_i) next_state = STATE_DONE;
            end
            
            // SC states
            STATE_SC_CHECK: begin
                if (rsrv_hit) begin
                    next_state = STATE_SC_WRITE;
                end else begin
                    next_state = STATE_DONE;  // SC fails
                end
            end
            
            STATE_SC_WRITE: begin
                if (mem_req_ready_i) next_state = STATE_SC_WAIT;
            end
            
            STATE_SC_WAIT: begin
                if (mem_resp_valid_i) next_state = STATE_DONE;
            end
            
            // AMO states
            STATE_AMO_READ: begin
                if (mem_req_ready_i) next_state = STATE_AMO_WAIT;
            end
            
            STATE_AMO_WAIT: begin
                if (mem_resp_valid_i) next_state = STATE_AMO_CALC;
            end
            
            STATE_AMO_CALC: begin
                next_state = STATE_AMO_WRITE;
            end
            
            STATE_AMO_WRITE: begin
                if (mem_req_ready_i) next_state = STATE_AMO_WBWAIT;
            end
            
            STATE_AMO_WBWAIT: begin
                if (mem_resp_valid_i) next_state = STATE_DONE;
            end
            
            STATE_DONE: begin
                next_state = STATE_IDLE;
            end
        endcase
        
        // Flush handling
        if (flush_i) begin
            next_state = STATE_IDLE;
        end
    end
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            
            saved_op <= 0;
            saved_addr <= 0;
            saved_rs2_data <= 0;
            saved_aq <= 0;
            saved_rl <= 0;
            saved_rd <= 0;
            saved_rob_idx <= 0;
            
            mem_read_data <= 0;
            
            rsrv_valid <= 0;
            rsrv_lru_ptr <= 0;
            
            resp_valid_o <= 0;
            resp_data_o <= 0;
            resp_rd_o <= 0;
            resp_rob_idx_o <= 0;
            resp_sc_fail_o <= 0;
            
            mem_req_valid_o <= 0;
            mem_req_we_o <= 0;
            mem_req_addr_o <= 0;
            mem_req_wdata_o <= 0;
            
            for (i = 0; i < RESERVATION_SETS; i = i + 1) begin
                rsrv_addr[i] <= 0;
            end
        end else begin
            state <= next_state;
            resp_valid_o <= 0;
            mem_req_valid_o <= 0;
            
            // Snoop invalidation
            if (snoop_valid_i && snoop_we_i) begin
                for (i = 0; i < RESERVATION_SETS; i = i + 1) begin
                    if (rsrv_valid[i] && 
                        (rsrv_addr[i][ADDR_WIDTH-1:2] == snoop_addr_i[ADDR_WIDTH-1:2])) begin
                        rsrv_valid[i] <= 0;
                    end
                end
            end
            
            case (state)
                STATE_IDLE: begin
                    if (req_valid_i) begin
                        saved_op <= req_op_i;
                        saved_addr <= req_addr_i;
                        saved_rs2_data <= req_rs2_data_i;
                        saved_aq <= req_aq_i;
                        saved_rl <= req_rl_i;
                        saved_rd <= req_rd_i;
                        saved_rob_idx <= req_rob_idx_i;
                    end
                end
                
                // LR: Load Reserved
                STATE_LR_READ: begin
                    mem_req_valid_o <= 1;
                    mem_req_we_o <= 0;
                    mem_req_addr_o <= saved_addr;
                end
                
                STATE_LR_WAIT: begin
                    if (mem_resp_valid_i) begin
                        mem_read_data <= mem_resp_data_i;
                        
                        // Set reservation
                        rsrv_valid[rsrv_lru_ptr] <= 1;
                        rsrv_addr[rsrv_lru_ptr] <= saved_addr;
                        rsrv_lru_ptr <= rsrv_lru_ptr + 1;
                    end
                end
                
                // SC: Store Conditional
                STATE_SC_CHECK: begin
                    // Check reservation - handled in next_state logic
                    if (!rsrv_hit) begin
                        // SC fails immediately
                        resp_sc_fail_o <= 1;
                    end
                end
                
                STATE_SC_WRITE: begin
                    mem_req_valid_o <= 1;
                    mem_req_we_o <= 1;
                    mem_req_addr_o <= saved_addr;
                    mem_req_wdata_o <= saved_rs2_data;
                    
                    // Clear our reservation
                    rsrv_valid[rsrv_hit_idx] <= 0;
                end
                
                STATE_SC_WAIT: begin
                    if (mem_resp_valid_i) begin
                        resp_sc_fail_o <= 0;  // SC succeeds
                    end
                end
                
                // AMO operations
                STATE_AMO_READ: begin
                    mem_req_valid_o <= 1;
                    mem_req_we_o <= 0;
                    mem_req_addr_o <= saved_addr;
                end
                
                STATE_AMO_WAIT: begin
                    if (mem_resp_valid_i) begin
                        mem_read_data <= mem_resp_data_i;
                    end
                end
                
                STATE_AMO_CALC: begin
                    // amo_result is calculated combinatorially
                end
                
                STATE_AMO_WRITE: begin
                    mem_req_valid_o <= 1;
                    mem_req_we_o <= 1;
                    mem_req_addr_o <= saved_addr;
                    mem_req_wdata_o <= amo_result;
                end
                
                STATE_AMO_WBWAIT: begin
                    // Wait for write complete
                end
                
                STATE_DONE: begin
                    resp_valid_o <= 1;
                    resp_rd_o <= saved_rd;
                    resp_rob_idx_o <= saved_rob_idx;
                    
                    case (saved_op)
                        OP_LR: begin
                            resp_data_o <= mem_read_data;
                            resp_sc_fail_o <= 0;
                        end
                        OP_SC: begin
                            resp_data_o <= {31'b0, resp_sc_fail_o};  // 0 = success, 1 = fail
                        end
                        default: begin  // AMO
                            resp_data_o <= mem_read_data;  // Return old value
                            resp_sc_fail_o <= 0;
                        end
                    endcase
                end
            endcase
            
            // Flush handling
            if (flush_i) begin
                // Clear all reservations on flush
                rsrv_valid <= 0;
            end
        end
    end

endmodule
