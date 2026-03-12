//=================================================================
// Module: privilege_unit
// Description: Privilege Mode Management Unit
//              Manages M/S/U privilege mode transitions
//              Controls access permissions and mode-dependent behavior
// Requirements: Linux requires M/S/U privilege levels
//=================================================================

`timescale 1ns/1ps

module privilege_unit #(
    parameter XLEN = 32
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    //=========================================================
    // Current Privilege Mode
    //=========================================================
    output reg  [1:0]           priv_mode_o,          // Current mode
    
    //=========================================================
    // Mode Transition Interface
    //=========================================================
    input  wire                 trap_entry_i,         // Taking a trap
    input  wire [1:0]           trap_target_mode_i,   // Target mode for trap
    
    input  wire                 trap_return_i,        // Returning from trap (MRET/SRET)
    input  wire [1:0]           return_target_mode_i, // Mode to return to
    
    //=========================================================
    // CSR Access Control
    //=========================================================
    input  wire [11:0]          csr_addr_i,
    output wire                 csr_access_fault_o,   // Illegal CSR access
    
    //=========================================================
    // Instruction Access Control
    //=========================================================
    input  wire                 inst_wfi_i,           // WFI instruction
    input  wire                 inst_sfence_i,        // SFENCE.VMA
    input  wire                 inst_mret_i,          // MRET
    input  wire                 inst_sret_i,          // SRET
    output wire                 inst_illegal_o,       // Instruction illegal in current mode
    
    //=========================================================
    // Status Bits (from mstatus)
    //=========================================================
    input  wire                 mstatus_tvm_i,        // Trap Virtual Memory
    input  wire                 mstatus_tw_i,         // Timeout Wait (WFI)
    input  wire                 mstatus_tsr_i,        // Trap SRET
    input  wire [1:0]           mstatus_mpp_i,        // Previous privilege (M)
    input  wire                 mstatus_spp_i,        // Previous privilege (S)
    
    //=========================================================
    // Virtual Memory Control
    //=========================================================
    input  wire [XLEN-1:0]      satp_i,
    output wire                 vm_enabled_o,         // Virtual memory is active
    output wire [1:0]           effective_priv_o      // Effective priv for mem access
);

    //=========================================================
    // Privilege Mode Constants
    //=========================================================
    localparam PRIV_U = 2'b00;
    localparam PRIV_S = 2'b01;
    localparam PRIV_M = 2'b11;
    
    //=========================================================
    // Privilege Mode Register
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            priv_mode_o <= PRIV_M;  // Start in Machine mode
        end else begin
            if (trap_entry_i) begin
                priv_mode_o <= trap_target_mode_i;
            end else if (trap_return_i) begin
                priv_mode_o <= return_target_mode_i;
            end
        end
    end
    
    //=========================================================
    // CSR Access Permission Check
    //=========================================================
    // CSR address encoding:
    // [11:10] = read/write (11 = read-only)
    // [9:8] = minimum privilege level
    wire [1:0] csr_min_priv = csr_addr_i[9:8];
    wire csr_read_only = (csr_addr_i[11:10] == 2'b11);
    
    // CSR access is illegal if current privilege < required privilege
    assign csr_access_fault_o = (priv_mode_o < csr_min_priv);
    
    //=========================================================
    // Privileged Instruction Checks
    //=========================================================
    // MRET: only legal in M-mode
    wire mret_illegal = inst_mret_i && (priv_mode_o != PRIV_M);
    
    // SRET: illegal in U-mode, or in S-mode if TSR=1
    wire sret_illegal = inst_sret_i && 
                        ((priv_mode_o == PRIV_U) ||
                         (priv_mode_o == PRIV_S && mstatus_tsr_i));
    
    // WFI: illegal in U-mode, or in S-mode if TW=1
    wire wfi_illegal = inst_wfi_i &&
                       ((priv_mode_o == PRIV_U) ||
                        (priv_mode_o == PRIV_S && mstatus_tw_i));
    
    // SFENCE.VMA: illegal in U-mode, or in S-mode if TVM=1
    wire sfence_illegal = inst_sfence_i &&
                          ((priv_mode_o == PRIV_U) ||
                           (priv_mode_o == PRIV_S && mstatus_tvm_i));
    
    assign inst_illegal_o = mret_illegal || sret_illegal || 
                            wfi_illegal || sfence_illegal;
    
    //=========================================================
    // Virtual Memory Control
    //=========================================================
    wire satp_mode = satp_i[31];  // Sv32 mode bit
    
    // VM is enabled when not in M-mode and satp.MODE != Bare
    assign vm_enabled_o = (priv_mode_o != PRIV_M) && satp_mode;
    
    // Effective privilege for memory access (can differ from priv_mode)
    // M-mode can access user pages with MPRV, but we simplify here
    assign effective_priv_o = priv_mode_o;

endmodule
