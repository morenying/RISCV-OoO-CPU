//=================================================================
// Module: trap_handler
// Description: Exception and Interrupt Handler Unit
//              Handles trap entry/return, privilege transitions
//              Supports M/S mode trap delegation
// Requirements: Linux requires proper exception handling
//=================================================================

`timescale 1ns/1ps

module trap_handler #(
    parameter XLEN = 32
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    //=========================================================
    // Current State
    //=========================================================
    input  wire [1:0]           priv_mode_i,          // Current privilege mode
    input  wire [XLEN-1:0]      pc_i,                 // Current PC
    
    //=========================================================
    // Exception Sources
    //=========================================================
    input  wire                 exc_valid_i,          // Exception occurred
    input  wire [3:0]           exc_cause_i,          // Exception cause code
    input  wire [XLEN-1:0]      exc_tval_i,           // Trap value (faulting addr/inst)
    
    // Specific exception signals
    input  wire                 inst_addr_misaligned_i,
    input  wire                 inst_access_fault_i,
    input  wire                 illegal_inst_i,
    input  wire                 breakpoint_i,
    input  wire                 load_addr_misaligned_i,
    input  wire                 load_access_fault_i,
    input  wire                 store_addr_misaligned_i,
    input  wire                 store_access_fault_i,
    input  wire                 ecall_u_i,
    input  wire                 ecall_s_i,
    input  wire                 ecall_m_i,
    input  wire                 inst_page_fault_i,
    input  wire                 load_page_fault_i,
    input  wire                 store_page_fault_i,
    
    //=========================================================
    // Interrupt Sources (directly from CLINT/PLIC/CSR)
    //=========================================================
    input  wire                 mti_i,                // Machine timer interrupt
    input  wire                 msi_i,                // Machine software interrupt
    input  wire                 mei_i,                // Machine external interrupt
    input  wire                 sti_i,                // Supervisor timer interrupt
    input  wire                 ssi_i,                // Supervisor software interrupt
    input  wire                 sei_i,                // Supervisor external interrupt
    
    //=========================================================
    // CSR Interface
    //=========================================================
    input  wire [XLEN-1:0]      mstatus_i,
    input  wire [XLEN-1:0]      mie_i,
    input  wire [XLEN-1:0]      mip_i,
    input  wire [XLEN-1:0]      mtvec_i,
    input  wire [XLEN-1:0]      medeleg_i,
    input  wire [XLEN-1:0]      mideleg_i,
    input  wire [XLEN-1:0]      stvec_i,
    
    // CSR write interface
    output reg                  csr_we_o,
    output reg  [11:0]          csr_addr_o,
    output reg  [XLEN-1:0]      csr_wdata_o,
    
    //=========================================================
    // Trap Return Signals
    //=========================================================
    input  wire                 mret_i,
    input  wire                 sret_i,
    input  wire [XLEN-1:0]      mepc_i,
    input  wire [XLEN-1:0]      sepc_i,
    
    //=========================================================
    // Outputs
    //=========================================================
    output reg                  trap_taken_o,         // Trap is being taken
    output reg  [XLEN-1:0]      trap_pc_o,            // Target PC for trap
    output reg  [1:0]           trap_priv_o,          // New privilege mode
    output reg                  trap_is_interrupt_o,  // Is interrupt (vs exception)
    output reg  [XLEN-1:0]      trap_cause_o,         // Cause value for xcause CSR
    output reg  [XLEN-1:0]      trap_tval_o,          // Value for xtval CSR
    
    output wire                 pipeline_flush_o      // Flush pipeline on trap
);

    //=========================================================
    // CSR Addresses
    //=========================================================
    localparam CSR_MEPC     = 12'h341;
    localparam CSR_MCAUSE   = 12'h342;
    localparam CSR_MTVAL    = 12'h343;
    localparam CSR_MSTATUS  = 12'h300;
    localparam CSR_SEPC     = 12'h141;
    localparam CSR_SCAUSE   = 12'h142;
    localparam CSR_STVAL    = 12'h143;
    localparam CSR_SSTATUS  = 12'h100;
    
    //=========================================================
    // Privilege Modes
    //=========================================================
    localparam PRIV_U = 2'b00;
    localparam PRIV_S = 2'b01;
    localparam PRIV_M = 2'b11;
    
    //=========================================================
    // Exception Cause Codes
    //=========================================================
    localparam EXC_INST_ADDR_MISALIGNED = 4'd0;
    localparam EXC_INST_ACCESS_FAULT    = 4'd1;
    localparam EXC_ILLEGAL_INST         = 4'd2;
    localparam EXC_BREAKPOINT           = 4'd3;
    localparam EXC_LOAD_ADDR_MISALIGNED = 4'd4;
    localparam EXC_LOAD_ACCESS_FAULT    = 4'd5;
    localparam EXC_STORE_ADDR_MISALIGNED= 4'd6;
    localparam EXC_STORE_ACCESS_FAULT   = 4'd7;
    localparam EXC_ECALL_U              = 4'd8;
    localparam EXC_ECALL_S              = 4'd9;
    localparam EXC_ECALL_M              = 4'd11;
    localparam EXC_INST_PAGE_FAULT      = 4'd12;
    localparam EXC_LOAD_PAGE_FAULT      = 4'd13;
    localparam EXC_STORE_PAGE_FAULT     = 4'd15;
    
    //=========================================================
    // Interrupt Cause Codes (with MSB set)
    //=========================================================
    localparam INT_SSI = 4'd1;   // Supervisor software
    localparam INT_MSI = 4'd3;   // Machine software
    localparam INT_STI = 4'd5;   // Supervisor timer
    localparam INT_MTI = 4'd7;   // Machine timer
    localparam INT_SEI = 4'd9;   // Supervisor external
    localparam INT_MEI = 4'd11;  // Machine external
    
    //=========================================================
    // mstatus Field Extraction
    //=========================================================
    wire mstatus_mie = mstatus_i[3];
    wire mstatus_sie = mstatus_i[1];
    wire [1:0] mstatus_mpp = mstatus_i[12:11];
    wire mstatus_spp = mstatus_i[8];
    wire mstatus_mpie = mstatus_i[7];
    wire mstatus_spie = mstatus_i[5];
    
    //=========================================================
    // Interrupt Enable Logic
    //=========================================================
    // Global interrupt enable based on privilege mode
    wire m_ie_enabled = (priv_mode_i < PRIV_M) || (priv_mode_i == PRIV_M && mstatus_mie);
    wire s_ie_enabled = (priv_mode_i < PRIV_S) || (priv_mode_i == PRIV_S && mstatus_sie);
    
    // Individual interrupt enable
    wire mei_enabled = mie_i[11] && m_ie_enabled;
    wire msi_enabled = mie_i[3] && m_ie_enabled;
    wire mti_enabled = mie_i[7] && m_ie_enabled;
    wire sei_enabled = mie_i[9] && s_ie_enabled;
    wire ssi_enabled = mie_i[1] && s_ie_enabled;
    wire sti_enabled = mie_i[5] && s_ie_enabled;
    
    // Pending and enabled interrupts
    wire mei_pending = mei_i && mei_enabled;
    wire msi_pending = msi_i && msi_enabled;
    wire mti_pending = mti_i && mti_enabled;
    wire sei_pending = sei_i && sei_enabled && mideleg_i[9];
    wire ssi_pending = ssi_i && ssi_enabled && mideleg_i[1];
    wire sti_pending = sti_i && sti_enabled && mideleg_i[5];
    
    // M-mode interrupts (not delegated)
    wire m_int_pending = mei_pending || msi_pending || mti_pending ||
                         (sei_i && mie_i[9] && m_ie_enabled && !mideleg_i[9]) ||
                         (ssi_i && mie_i[1] && m_ie_enabled && !mideleg_i[1]) ||
                         (sti_i && mie_i[5] && m_ie_enabled && !mideleg_i[5]);
    
    // S-mode interrupts (delegated)
    wire s_int_pending = sei_pending || ssi_pending || sti_pending;
    
    wire any_int_pending = m_int_pending || s_int_pending;
    
    //=========================================================
    // Exception Priority Encoder
    //=========================================================
    reg [3:0] exc_code;
    reg       exc_any;
    
    always @(*) begin
        exc_any = 1'b0;
        exc_code = 4'd0;
        
        // Priority: instruction faults > illegal > breakpoint > ...
        if (inst_addr_misaligned_i) begin
            exc_any = 1'b1;
            exc_code = EXC_INST_ADDR_MISALIGNED;
        end else if (inst_access_fault_i) begin
            exc_any = 1'b1;
            exc_code = EXC_INST_ACCESS_FAULT;
        end else if (inst_page_fault_i) begin
            exc_any = 1'b1;
            exc_code = EXC_INST_PAGE_FAULT;
        end else if (illegal_inst_i) begin
            exc_any = 1'b1;
            exc_code = EXC_ILLEGAL_INST;
        end else if (breakpoint_i) begin
            exc_any = 1'b1;
            exc_code = EXC_BREAKPOINT;
        end else if (ecall_u_i) begin
            exc_any = 1'b1;
            exc_code = EXC_ECALL_U;
        end else if (ecall_s_i) begin
            exc_any = 1'b1;
            exc_code = EXC_ECALL_S;
        end else if (ecall_m_i) begin
            exc_any = 1'b1;
            exc_code = EXC_ECALL_M;
        end else if (load_addr_misaligned_i) begin
            exc_any = 1'b1;
            exc_code = EXC_LOAD_ADDR_MISALIGNED;
        end else if (load_access_fault_i) begin
            exc_any = 1'b1;
            exc_code = EXC_LOAD_ACCESS_FAULT;
        end else if (load_page_fault_i) begin
            exc_any = 1'b1;
            exc_code = EXC_LOAD_PAGE_FAULT;
        end else if (store_addr_misaligned_i) begin
            exc_any = 1'b1;
            exc_code = EXC_STORE_ADDR_MISALIGNED;
        end else if (store_access_fault_i) begin
            exc_any = 1'b1;
            exc_code = EXC_STORE_ACCESS_FAULT;
        end else if (store_page_fault_i) begin
            exc_any = 1'b1;
            exc_code = EXC_STORE_PAGE_FAULT;
        end else if (exc_valid_i) begin
            exc_any = 1'b1;
            exc_code = exc_cause_i;
        end
    end
    
    //=========================================================
    // Interrupt Priority Encoder
    //=========================================================
    reg [3:0] int_code;
    reg       int_selected;
    reg       int_to_m;  // Trap to M-mode
    
    always @(*) begin
        int_selected = 1'b0;
        int_code = 4'd0;
        int_to_m = 1'b1;
        
        // Priority: MEI > MSI > MTI > SEI > SSI > STI
        if (mei_pending) begin
            int_selected = 1'b1;
            int_code = INT_MEI;
            int_to_m = 1'b1;
        end else if (msi_pending) begin
            int_selected = 1'b1;
            int_code = INT_MSI;
            int_to_m = 1'b1;
        end else if (mti_pending) begin
            int_selected = 1'b1;
            int_code = INT_MTI;
            int_to_m = 1'b1;
        end else if (sei_pending) begin
            int_selected = 1'b1;
            int_code = INT_SEI;
            int_to_m = 1'b0;
        end else if (ssi_pending) begin
            int_selected = 1'b1;
            int_code = INT_SSI;
            int_to_m = 1'b0;
        end else if (sti_pending) begin
            int_selected = 1'b1;
            int_code = INT_STI;
            int_to_m = 1'b0;
        end
    end
    
    //=========================================================
    // Trap Delegation Check
    //=========================================================
    wire exc_delegated = (priv_mode_i < PRIV_M) && medeleg_i[exc_code];
    wire trap_to_s = (exc_any && exc_delegated) || (int_selected && !int_to_m);
    wire trap_to_m = (exc_any && !exc_delegated) || (int_selected && int_to_m);
    
    //=========================================================
    // Trap Vector Calculation
    //=========================================================
    wire [XLEN-1:0] mtvec_base = {mtvec_i[XLEN-1:2], 2'b00};
    wire            mtvec_vectored = (mtvec_i[1:0] == 2'b01);
    wire [XLEN-1:0] stvec_base = {stvec_i[XLEN-1:2], 2'b00};
    wire            stvec_vectored = (stvec_i[1:0] == 2'b01);
    
    wire [XLEN-1:0] m_trap_pc = (mtvec_vectored && int_selected) ?
                                 mtvec_base + {int_code, 2'b00} : mtvec_base;
    wire [XLEN-1:0] s_trap_pc = (stvec_vectored && int_selected) ?
                                 stvec_base + {int_code, 2'b00} : stvec_base;
    
    //=========================================================
    // Trap State Machine
    //=========================================================
    localparam TRAP_IDLE    = 3'd0;
    localparam TRAP_ENTRY   = 3'd1;
    localparam TRAP_UPDATE1 = 3'd2;
    localparam TRAP_UPDATE2 = 3'd3;
    localparam TRAP_UPDATE3 = 3'd4;
    localparam TRAP_RETURN  = 3'd5;
    
    reg [2:0] trap_state;
    reg [2:0] trap_next_state;
    
    // Saved trap info
    reg [XLEN-1:0] saved_pc;
    reg [3:0]      saved_cause;
    reg [XLEN-1:0] saved_tval;
    reg            saved_is_int;
    reg            saved_to_s;
    
    //=========================================================
    // State Transition
    //=========================================================
    always @(*) begin
        trap_next_state = trap_state;
        
        case (trap_state)
            TRAP_IDLE: begin
                if (int_selected || exc_any) begin
                    trap_next_state = TRAP_ENTRY;
                end else if (mret_i || sret_i) begin
                    trap_next_state = TRAP_RETURN;
                end
            end
            
            TRAP_ENTRY: begin
                trap_next_state = TRAP_UPDATE1;
            end
            
            TRAP_UPDATE1: begin
                trap_next_state = TRAP_UPDATE2;
            end
            
            TRAP_UPDATE2: begin
                trap_next_state = TRAP_UPDATE3;
            end
            
            TRAP_UPDATE3: begin
                trap_next_state = TRAP_IDLE;
            end
            
            TRAP_RETURN: begin
                trap_next_state = TRAP_IDLE;
            end
        endcase
    end
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trap_state <= TRAP_IDLE;
            trap_taken_o <= 0;
            trap_pc_o <= 0;
            trap_priv_o <= PRIV_M;
            trap_is_interrupt_o <= 0;
            trap_cause_o <= 0;
            trap_tval_o <= 0;
            csr_we_o <= 0;
            csr_addr_o <= 0;
            csr_wdata_o <= 0;
            saved_pc <= 0;
            saved_cause <= 0;
            saved_tval <= 0;
            saved_is_int <= 0;
            saved_to_s <= 0;
        end else begin
            trap_state <= trap_next_state;
            trap_taken_o <= 0;
            csr_we_o <= 0;
            
            case (trap_state)
                TRAP_IDLE: begin
                    if (int_selected || exc_any) begin
                        // Save trap information
                        saved_pc <= pc_i;
                        saved_is_int <= int_selected;
                        saved_to_s <= trap_to_s;
                        
                        if (int_selected) begin
                            saved_cause <= int_code;
                            saved_tval <= 0;
                        end else begin
                            saved_cause <= exc_code;
                            saved_tval <= exc_tval_i;
                        end
                    end
                end
                
                TRAP_ENTRY: begin
                    // Signal trap taken and new PC
                    trap_taken_o <= 1;
                    trap_is_interrupt_o <= saved_is_int;
                    trap_cause_o <= {saved_is_int, {(XLEN-5){1'b0}}, saved_cause};
                    trap_tval_o <= saved_tval;
                    
                    if (saved_to_s) begin
                        trap_pc_o <= s_trap_pc;
                        trap_priv_o <= PRIV_S;
                        
                        // Write SEPC
                        csr_we_o <= 1;
                        csr_addr_o <= CSR_SEPC;
                        csr_wdata_o <= saved_pc;
                    end else begin
                        trap_pc_o <= m_trap_pc;
                        trap_priv_o <= PRIV_M;
                        
                        // Write MEPC
                        csr_we_o <= 1;
                        csr_addr_o <= CSR_MEPC;
                        csr_wdata_o <= saved_pc;
                    end
                end
                
                TRAP_UPDATE1: begin
                    // Write xcause
                    csr_we_o <= 1;
                    if (saved_to_s) begin
                        csr_addr_o <= CSR_SCAUSE;
                    end else begin
                        csr_addr_o <= CSR_MCAUSE;
                    end
                    csr_wdata_o <= {saved_is_int, {(XLEN-5){1'b0}}, saved_cause};
                end
                
                TRAP_UPDATE2: begin
                    // Write xtval
                    csr_we_o <= 1;
                    if (saved_to_s) begin
                        csr_addr_o <= CSR_STVAL;
                    end else begin
                        csr_addr_o <= CSR_MTVAL;
                    end
                    csr_wdata_o <= saved_tval;
                end
                
                TRAP_UPDATE3: begin
                    // Update xstatus (MPP/SPP, MPIE/SPIE, MIE/SIE)
                    csr_we_o <= 1;
                    if (saved_to_s) begin
                        csr_addr_o <= CSR_SSTATUS;
                        // SPP = current priv, SPIE = SIE, SIE = 0
                        csr_wdata_o <= (mstatus_i & ~32'h122) |
                                       {23'b0, priv_mode_i[0], 3'b0, mstatus_sie, 4'b0};
                    end else begin
                        csr_addr_o <= CSR_MSTATUS;
                        // MPP = current priv, MPIE = MIE, MIE = 0
                        csr_wdata_o <= (mstatus_i & ~32'h1888) |
                                       {19'b0, priv_mode_i, 4'b0, mstatus_mie, 3'b0};
                    end
                end
                
                TRAP_RETURN: begin
                    trap_taken_o <= 1;
                    
                    if (mret_i) begin
                        // MRET: return to MPP, MIE = MPIE, MPIE = 1
                        trap_pc_o <= mepc_i;
                        trap_priv_o <= mstatus_mpp;
                        
                        csr_we_o <= 1;
                        csr_addr_o <= CSR_MSTATUS;
                        // Set MIE = MPIE, MPIE = 1, MPP = U (if U supported)
                        csr_wdata_o <= (mstatus_i & ~32'h1888) |
                                       {19'b0, 2'b00, 4'b0, 1'b1, 3'b0} |
                                       {28'b0, mstatus_mpie, 3'b0};
                    end else begin // sret_i
                        // SRET: return to SPP, SIE = SPIE, SPIE = 1
                        trap_pc_o <= sepc_i;
                        trap_priv_o <= {1'b0, mstatus_spp};
                        
                        csr_we_o <= 1;
                        csr_addr_o <= CSR_SSTATUS;
                        // Set SIE = SPIE, SPIE = 1, SPP = U
                        csr_wdata_o <= (mstatus_i & ~32'h122) |
                                       {23'b0, 1'b0, 3'b0, 1'b1, 4'b0} |
                                       {30'b0, mstatus_spie, 1'b0};
                    end
                end
            endcase
        end
    end
    
    assign pipeline_flush_o = trap_taken_o;

endmodule
