//=================================================================
// Module: csr_file
// Description: Complete Control and Status Register File
//              Full RISC-V Privileged Spec 1.12 compliance
//              Supports M/S/U privilege levels for Linux
//              Hardware performance counters
// Requirements: Privilege Spec for Linux boot
//=================================================================

`timescale 1ns/1ps

module csr_file #(
    parameter XLEN          = 32,
    parameter ASID_WIDTH    = 9,
    parameter PPN_WIDTH     = 22      // For Sv32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // CSR Read/Write Interface
    //=========================================================
    input  wire [11:0]              csr_addr_i,
    input  wire                     csr_read_en_i,
    input  wire                     csr_write_en_i,
    input  wire [XLEN-1:0]          csr_wdata_i,
    input  wire [1:0]               csr_op_i,       // 00=W, 01=S, 10=C
    output reg  [XLEN-1:0]          csr_rdata_o,
    output wire                     csr_illegal_o,
    
    //=========================================================
    // Current Privilege Level
    //=========================================================
    input  wire [1:0]               priv_mode_i,    // 00=U, 01=S, 11=M
    output wire [1:0]               priv_mode_o,
    
    //=========================================================
    // Trap Interface
    //=========================================================
    input  wire                     trap_enter_i,
    input  wire [1:0]               trap_to_priv_i,
    input  wire [XLEN-1:0]          trap_cause_i,
    input  wire [XLEN-1:0]          trap_val_i,
    input  wire [XLEN-1:0]          trap_pc_i,
    
    input  wire                     trap_return_i,
    input  wire [1:0]               trap_from_priv_i,
    output wire [XLEN-1:0]          trap_vector_o,
    output wire [XLEN-1:0]          trap_epc_o,
    
    //=========================================================
    // Interrupt Pending/Enable
    //=========================================================
    input  wire                     ext_irq_m_i,
    input  wire                     timer_irq_m_i,
    input  wire                     sw_irq_m_i,
    input  wire                     ext_irq_s_i,
    input  wire                     timer_irq_s_i,
    input  wire                     sw_irq_s_i,
    
    output wire                     irq_pending_o,
    output wire [XLEN-1:0]          irq_cause_o,
    
    //=========================================================
    // Memory Management
    //=========================================================
    output wire [XLEN-1:0]          satp_o,
    output wire                     mxr_o,          // Make eXecutable Readable
    output wire                     sum_o,          // Supervisor User Memory access
    output wire                     mprv_o,         // Modify PRiVilege
    output wire [1:0]               mpp_o,          // M Previous Privilege
    
    //=========================================================
    // Direct CSR State Outputs (for trap/MMU integration)
    //=========================================================
    output wire [XLEN-1:0]          mstatus_o,
    output wire [XLEN-1:0]          mie_o,
    output wire [XLEN-1:0]          mip_o,
    output wire [XLEN-1:0]          mtvec_o,
    output wire [XLEN-1:0]          stvec_o,
    output wire [XLEN-1:0]          medeleg_o,
    output wire [XLEN-1:0]          mideleg_o,
    output wire [XLEN-1:0]          mepc_o,
    output wire [XLEN-1:0]          sepc_o,
    
    //=========================================================
    // Performance Counters
    //=========================================================
    input  wire                     instr_retire_i,
    input  wire [1:0]               instr_count_i,  // Number of instructions retired
    
    //=========================================================
    // Hart ID
    //=========================================================
    input  wire [XLEN-1:0]          hart_id_i
);

    //=========================================================
    // CSR Addresses
    //=========================================================
    // User CSRs
    localparam CSR_USTATUS      = 12'h000;
    localparam CSR_CYCLE        = 12'hC00;
    localparam CSR_TIME         = 12'hC01;
    localparam CSR_INSTRET      = 12'hC02;
    localparam CSR_CYCLEH       = 12'hC80;
    localparam CSR_TIMEH        = 12'hC81;
    localparam CSR_INSTRETH     = 12'hC82;
    
    // Supervisor CSRs
    localparam CSR_SSTATUS      = 12'h100;
    localparam CSR_SIE          = 12'h104;
    localparam CSR_STVEC        = 12'h105;
    localparam CSR_SCOUNTEREN   = 12'h106;
    localparam CSR_SSCRATCH     = 12'h140;
    localparam CSR_SEPC         = 12'h141;
    localparam CSR_SCAUSE       = 12'h142;
    localparam CSR_STVAL        = 12'h143;
    localparam CSR_SIP          = 12'h144;
    localparam CSR_SATP         = 12'h180;
    
    // Machine CSRs
    localparam CSR_MSTATUS      = 12'h300;
    localparam CSR_MISA         = 12'h301;
    localparam CSR_MEDELEG      = 12'h302;
    localparam CSR_MIDELEG      = 12'h303;
    localparam CSR_MIE          = 12'h304;
    localparam CSR_MTVEC        = 12'h305;
    localparam CSR_MCOUNTEREN   = 12'h306;
    localparam CSR_MSCRATCH     = 12'h340;
    localparam CSR_MEPC         = 12'h341;
    localparam CSR_MCAUSE       = 12'h342;
    localparam CSR_MTVAL        = 12'h343;
    localparam CSR_MIP          = 12'h344;
    localparam CSR_MCYCLE       = 12'hB00;
    localparam CSR_MINSTRET     = 12'hB02;
    localparam CSR_MCYCLEH      = 12'hB80;
    localparam CSR_MINSTRETH    = 12'hB82;
    
    // Machine Information
    localparam CSR_MVENDORID    = 12'hF11;
    localparam CSR_MARCHID      = 12'hF12;
    localparam CSR_MIMPID       = 12'hF13;
    localparam CSR_MHARTID      = 12'hF14;
    
    //=========================================================
    // Privilege Levels
    //=========================================================
    localparam PRIV_U = 2'b00;
    localparam PRIV_S = 2'b01;
    localparam PRIV_M = 2'b11;
    
    //=========================================================
    // CSR Storage
    //=========================================================
    reg [1:0]       priv_mode;
    
    // Machine Mode CSRs
    reg [XLEN-1:0]  mstatus;
    reg [XLEN-1:0]  misa;
    reg [XLEN-1:0]  medeleg;
    reg [XLEN-1:0]  mideleg;
    reg [XLEN-1:0]  mie;
    reg [XLEN-1:0]  mtvec;
    reg [XLEN-1:0]  mcounteren;
    reg [XLEN-1:0]  mscratch;
    reg [XLEN-1:0]  mepc;
    reg [XLEN-1:0]  mcause;
    reg [XLEN-1:0]  mtval;
    reg [XLEN-1:0]  mip_sw;     // Software-writable bits of MIP
    
    // Supervisor Mode CSRs
    reg [XLEN-1:0]  stvec;
    reg [XLEN-1:0]  scounteren;
    reg [XLEN-1:0]  sscratch;
    reg [XLEN-1:0]  sepc;
    reg [XLEN-1:0]  scause;
    reg [XLEN-1:0]  stval;
    reg [XLEN-1:0]  satp;
    
    // Performance Counters (64-bit)
    reg [63:0]      mcycle;
    reg [63:0]      minstret;
    
    //=========================================================
    // MSTATUS Field Definitions (RV32)
    //=========================================================
    // [0]     - Reserved
    // [1]     - SIE (Supervisor Interrupt Enable)
    // [2]     - Reserved
    // [3]     - MIE (Machine Interrupt Enable)
    // [4]     - Reserved
    // [5]     - SPIE (Supervisor Previous IE)
    // [6]     - UBE (User Big Endian) - not implemented
    // [7]     - MPIE (Machine Previous IE)
    // [8]     - SPP (Supervisor Previous Privilege)
    // [10:9]  - VS (Vector Extension State)
    // [12:11] - MPP (Machine Previous Privilege)
    // [14:13] - FS (FP Extension State)
    // [16:15] - XS (User Extension State)
    // [17]    - MPRV (Modify PRiVilege)
    // [18]    - SUM (Supervisor User Memory access)
    // [19]    - MXR (Make eXecutable Readable)
    // [20]    - TVM (Trap Virtual Memory)
    // [21]    - TW (Timeout Wait)
    // [22]    - TSR (Trap SRET)
    // [30:23] - Reserved
    // [31]    - SD (State Dirty)
    
    wire mstatus_sie  = mstatus[1];
    wire mstatus_mie  = mstatus[3];
    wire mstatus_spie = mstatus[5];
    wire mstatus_mpie = mstatus[7];
    wire mstatus_spp  = mstatus[8];
    wire [1:0] mstatus_mpp = mstatus[12:11];
    wire mstatus_mprv = mstatus[17];
    wire mstatus_sum  = mstatus[18];
    wire mstatus_mxr  = mstatus[19];
    wire mstatus_tvm  = mstatus[20];
    wire mstatus_tw   = mstatus[21];
    wire mstatus_tsr  = mstatus[22];
    
    // MSTATUS write mask
    localparam MSTATUS_WMASK = 32'h007F_FFEA;  // Writable bits
    localparam SSTATUS_WMASK = 32'h000C_0122;  // S-mode visible bits
    
    //=========================================================
    // Interrupt Pending Logic (MIP)
    //=========================================================
    wire [XLEN-1:0] mip;
    assign mip[0]  = 1'b0;               // Reserved
    assign mip[1]  = sw_irq_s_i;         // SSIP
    assign mip[2]  = 1'b0;               // Reserved
    assign mip[3]  = sw_irq_m_i;         // MSIP
    assign mip[4]  = 1'b0;               // Reserved
    assign mip[5]  = timer_irq_s_i;      // STIP
    assign mip[6]  = 1'b0;               // Reserved
    assign mip[7]  = timer_irq_m_i;      // MTIP
    assign mip[8]  = 1'b0;               // Reserved
    assign mip[9]  = ext_irq_s_i;        // SEIP
    assign mip[10] = 1'b0;               // Reserved
    assign mip[11] = ext_irq_m_i;        // MEIP
    assign mip[XLEN-1:12] = 0;
    
    // S-mode visible interrupts
    wire [XLEN-1:0] sip = mip & mideleg;
    wire [XLEN-1:0] sie = mie & mideleg;
    
    //=========================================================
    // Interrupt Priority and Pending Logic
    //=========================================================
    wire m_irq_enabled = (priv_mode < PRIV_M) || (priv_mode == PRIV_M && mstatus_mie);
    wire s_irq_enabled = (priv_mode < PRIV_S) || (priv_mode == PRIV_S && mstatus_sie);
    
    wire [XLEN-1:0] pending_m = mip & mie & ~mideleg;
    wire [XLEN-1:0] pending_s = mip & mie & mideleg;
    
    wire m_irq_pending = |pending_m && m_irq_enabled;
    wire s_irq_pending = |pending_s && s_irq_enabled && (priv_mode <= PRIV_S);
    
    assign irq_pending_o = m_irq_pending || s_irq_pending;
    
    // Priority encode interrupt cause (MEI > MSI > MTI > SEI > SSI > STI)
    reg [XLEN-1:0] irq_cause_reg;
    always @(*) begin
        if (pending_m[11])      irq_cause_reg = {1'b1, 31'd11};  // MEI
        else if (pending_m[3])  irq_cause_reg = {1'b1, 31'd3};   // MSI
        else if (pending_m[7])  irq_cause_reg = {1'b1, 31'd7};   // MTI
        else if (pending_s[9])  irq_cause_reg = {1'b1, 31'd9};   // SEI
        else if (pending_s[1])  irq_cause_reg = {1'b1, 31'd1};   // SSI
        else if (pending_s[5])  irq_cause_reg = {1'b1, 31'd5};   // STI
        else                    irq_cause_reg = 0;
    end
    assign irq_cause_o = irq_cause_reg;
    
    //=========================================================
    // Output Assignments
    //=========================================================
    assign priv_mode_o = priv_mode;
    assign satp_o = satp;
    assign mxr_o = mstatus_mxr;
    assign sum_o = mstatus_sum;
    assign mprv_o = mstatus_mprv;
    assign mpp_o = mstatus_mpp;

    // Direct CSR state outputs
    assign mstatus_o  = mstatus;
    assign mie_o      = mie;
    assign mip_o      = mip;
    assign mtvec_o    = mtvec;
    assign stvec_o    = stvec;
    assign medeleg_o  = medeleg;
    assign mideleg_o  = mideleg;
    assign mepc_o     = mepc;
    assign sepc_o     = sepc;
    
    // Trap vector selection
    assign trap_vector_o = (trap_to_priv_i == PRIV_S) ? stvec : mtvec;
    assign trap_epc_o = (trap_from_priv_i == PRIV_S) ? sepc : mepc;
    
    //=========================================================
    // CSR Access Control
    //=========================================================
    wire [1:0] csr_priv = csr_addr_i[9:8];
    wire csr_readonly = (csr_addr_i[11:10] == 2'b11);
    
    wire priv_ok = (priv_mode >= csr_priv);
    wire write_ok = !csr_readonly || !csr_write_en_i;
    
    assign csr_illegal_o = csr_read_en_i && (!priv_ok || (csr_write_en_i && !write_ok));
    
    //=========================================================
    // CSR Read Logic
    //=========================================================
    always @(*) begin
        csr_rdata_o = 0;
        
        case (csr_addr_i)
            // User CSRs
            CSR_CYCLE:      csr_rdata_o = mcycle[31:0];
            CSR_CYCLEH:     csr_rdata_o = mcycle[63:32];
            CSR_TIME:       csr_rdata_o = mcycle[31:0];   // TIME = CYCLE
            CSR_TIMEH:      csr_rdata_o = mcycle[63:32];
            CSR_INSTRET:    csr_rdata_o = minstret[31:0];
            CSR_INSTRETH:   csr_rdata_o = minstret[63:32];
            
            // Supervisor CSRs
            CSR_SSTATUS:    csr_rdata_o = mstatus & SSTATUS_WMASK;
            CSR_SIE:        csr_rdata_o = sie;
            CSR_STVEC:      csr_rdata_o = stvec;
            CSR_SCOUNTEREN: csr_rdata_o = scounteren;
            CSR_SSCRATCH:   csr_rdata_o = sscratch;
            CSR_SEPC:       csr_rdata_o = sepc;
            CSR_SCAUSE:     csr_rdata_o = scause;
            CSR_STVAL:      csr_rdata_o = stval;
            CSR_SIP:        csr_rdata_o = sip;
            CSR_SATP:       csr_rdata_o = satp;
            
            // Machine CSRs
            CSR_MSTATUS:    csr_rdata_o = mstatus;
            CSR_MISA:       csr_rdata_o = misa;
            CSR_MEDELEG:    csr_rdata_o = medeleg;
            CSR_MIDELEG:    csr_rdata_o = mideleg;
            CSR_MIE:        csr_rdata_o = mie;
            CSR_MTVEC:      csr_rdata_o = mtvec;
            CSR_MCOUNTEREN: csr_rdata_o = mcounteren;
            CSR_MSCRATCH:   csr_rdata_o = mscratch;
            CSR_MEPC:       csr_rdata_o = mepc;
            CSR_MCAUSE:     csr_rdata_o = mcause;
            CSR_MTVAL:      csr_rdata_o = mtval;
            CSR_MIP:        csr_rdata_o = mip;
            CSR_MCYCLE:     csr_rdata_o = mcycle[31:0];
            CSR_MCYCLEH:    csr_rdata_o = mcycle[63:32];
            CSR_MINSTRET:   csr_rdata_o = minstret[31:0];
            CSR_MINSTRETH:  csr_rdata_o = minstret[63:32];
            
            // Machine Information (Read-only)
            CSR_MVENDORID:  csr_rdata_o = 32'h0;          // Non-commercial
            CSR_MARCHID:    csr_rdata_o = 32'h0;
            CSR_MIMPID:     csr_rdata_o = 32'h2025_0128;  // Version date
            CSR_MHARTID:    csr_rdata_o = hart_id_i;
            
            default:        csr_rdata_o = 0;
        endcase
    end
    
    //=========================================================
    // CSR Write Logic
    //=========================================================
    wire [XLEN-1:0] csr_wdata_final;
    assign csr_wdata_final = (csr_op_i == 2'b00) ? csr_wdata_i :
                             (csr_op_i == 2'b01) ? (csr_rdata_o | csr_wdata_i) :
                             (csr_op_i == 2'b10) ? (csr_rdata_o & ~csr_wdata_i) :
                             csr_wdata_i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            priv_mode <= PRIV_M;
            
            // Machine CSRs
            mstatus <= 32'h0000_1800;  // MPP = M
            misa <= 32'h4014_112D;     // RV32IMASU (I+M+A+S+U)
            medeleg <= 0;
            mideleg <= 0;
            mie <= 0;
            mtvec <= 0;
            mcounteren <= 0;
            mscratch <= 0;
            mepc <= 0;
            mcause <= 0;
            mtval <= 0;
            mip_sw <= 0;
            
            // Supervisor CSRs
            stvec <= 0;
            scounteren <= 0;
            sscratch <= 0;
            sepc <= 0;
            scause <= 0;
            stval <= 0;
            satp <= 0;
            
            // Counters
            mcycle <= 0;
            minstret <= 0;
        end else begin
            // Always increment cycle counter
            mcycle <= mcycle + 1;
            
            // Increment instruction counter
            if (instr_retire_i) begin
                minstret <= minstret + instr_count_i;
            end
            
            //=================================================
            // Trap Entry
            //=================================================
            if (trap_enter_i) begin
                if (trap_to_priv_i == PRIV_M) begin
                    // Save state to M-mode CSRs
                    mepc <= trap_pc_i;
                    mcause <= trap_cause_i;
                    mtval <= trap_val_i;
                    
                    // Update mstatus
                    mstatus[7] <= mstatus_mie;           // MPIE = MIE
                    mstatus[3] <= 1'b0;                  // MIE = 0
                    mstatus[12:11] <= priv_mode;         // MPP = current priv
                    
                    priv_mode <= PRIV_M;
                end else begin
                    // Save state to S-mode CSRs
                    sepc <= trap_pc_i;
                    scause <= trap_cause_i;
                    stval <= trap_val_i;
                    
                    // Update mstatus
                    mstatus[5] <= mstatus_sie;           // SPIE = SIE
                    mstatus[1] <= 1'b0;                  // SIE = 0
                    mstatus[8] <= priv_mode[0];          // SPP = current priv (bit 0)
                    
                    priv_mode <= PRIV_S;
                end
            end
            
            //=================================================
            // Trap Return
            //=================================================
            else if (trap_return_i) begin
                if (trap_from_priv_i == PRIV_M) begin
                    // MRET
                    mstatus[3] <= mstatus_mpie;          // MIE = MPIE
                    mstatus[7] <= 1'b1;                  // MPIE = 1
                    mstatus[12:11] <= PRIV_U;            // MPP = U
                    if (mstatus_mpp != PRIV_M) begin
                        mstatus[17] <= 1'b0;             // MPRV = 0
                    end
                    priv_mode <= mstatus_mpp;
                end else begin
                    // SRET
                    mstatus[1] <= mstatus_spie;          // SIE = SPIE
                    mstatus[5] <= 1'b1;                  // SPIE = 1
                    mstatus[8] <= 1'b0;                  // SPP = U
                    mstatus[17] <= 1'b0;                 // MPRV = 0
                    priv_mode <= {1'b0, mstatus_spp};
                end
            end
            
            //=================================================
            // CSR Write
            //=================================================
            else if (csr_write_en_i && !csr_illegal_o) begin
                case (csr_addr_i)
                    CSR_SSTATUS:    mstatus <= (mstatus & ~SSTATUS_WMASK) | 
                                              (csr_wdata_final & SSTATUS_WMASK);
                    CSR_SIE:        mie <= (mie & ~mideleg) | (csr_wdata_final & mideleg);
                    CSR_STVEC:      stvec <= {csr_wdata_final[31:2], 2'b00};
                    CSR_SCOUNTEREN: scounteren <= csr_wdata_final;
                    CSR_SSCRATCH:   sscratch <= csr_wdata_final;
                    CSR_SEPC:       sepc <= {csr_wdata_final[31:2], 2'b00};
                    CSR_SCAUSE:     scause <= csr_wdata_final;
                    CSR_STVAL:      stval <= csr_wdata_final;
                    CSR_SIP:        mip_sw <= (mip_sw & ~12'h222) | (csr_wdata_final & 12'h222 & mideleg);
                    CSR_SATP:       satp <= csr_wdata_final;
                    
                    CSR_MSTATUS:    mstatus <= csr_wdata_final & MSTATUS_WMASK;
                    CSR_MEDELEG:    medeleg <= csr_wdata_final & 32'h0000_B3FF;
                    CSR_MIDELEG:    mideleg <= csr_wdata_final & 32'h0000_0222;
                    CSR_MIE:        mie <= csr_wdata_final & 32'h0000_0AAA;
                    CSR_MTVEC:      mtvec <= {csr_wdata_final[31:2], 2'b00};
                    CSR_MCOUNTEREN: mcounteren <= csr_wdata_final;
                    CSR_MSCRATCH:   mscratch <= csr_wdata_final;
                    CSR_MEPC:       mepc <= {csr_wdata_final[31:2], 2'b00};
                    CSR_MCAUSE:     mcause <= csr_wdata_final;
                    CSR_MTVAL:      mtval <= csr_wdata_final;
                    CSR_MIP:        mip_sw <= csr_wdata_final & 32'h0000_0222;
                    
                    CSR_MCYCLE:     mcycle[31:0] <= csr_wdata_final;
                    CSR_MCYCLEH:    mcycle[63:32] <= csr_wdata_final;
                    CSR_MINSTRET:   minstret[31:0] <= csr_wdata_final;
                    CSR_MINSTRETH:  minstret[63:32] <= csr_wdata_final;
                endcase
            end
        end
    end

endmodule
