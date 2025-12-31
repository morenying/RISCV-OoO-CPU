//=================================================================
// Module: csr_unit
// Description: Control and Status Register Unit
//              Implements Machine-mode CSRs
//              Supports CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI
// Requirements: 6.4, 6.5, 1.3
//=================================================================

`timescale 1ns/1ps

module csr_unit #(
    parameter XLEN = 32
)(
    input  wire                clk,
    input  wire                rst_n,
    
    // CSR access interface
    input  wire                csr_valid_i,
    input  wire [11:0]         csr_addr_i,
    input  wire [2:0]          csr_op_i,      // funct3
    input  wire [XLEN-1:0]     csr_wdata_i,
    output reg  [XLEN-1:0]     csr_rdata_o,
    output reg                 csr_illegal_o,
    
    // Exception interface
    input  wire                exception_i,
    input  wire [3:0]          exc_code_i,
    input  wire [XLEN-1:0]     exc_pc_i,
    input  wire [XLEN-1:0]     exc_tval_i,
    
    // MRET
    input  wire                mret_i,
    
    // Interrupt interface
    input  wire                ext_irq_i,
    input  wire                timer_irq_i,
    input  wire                sw_irq_i,
    output wire                irq_pending_o,
    
    // Trap handling outputs
    output wire [XLEN-1:0]     mtvec_o,
    output wire [XLEN-1:0]     mepc_o,
    output wire                mie_o,
    
    // Hart ID
    input  wire [XLEN-1:0]     hart_id_i
);

    //=========================================================
    // CSR Addresses
    //=========================================================
    localparam CSR_MSTATUS   = 12'h300;
    localparam CSR_MISA      = 12'h301;
    localparam CSR_MIE       = 12'h304;
    localparam CSR_MTVEC     = 12'h305;
    localparam CSR_MSCRATCH  = 12'h340;
    localparam CSR_MEPC      = 12'h341;
    localparam CSR_MCAUSE    = 12'h342;
    localparam CSR_MTVAL     = 12'h343;
    localparam CSR_MIP       = 12'h344;
    localparam CSR_MCYCLE    = 12'hB00;
    localparam CSR_MINSTRET  = 12'hB02;
    localparam CSR_MCYCLEH   = 12'hB80;
    localparam CSR_MINSTRETH = 12'hB82;
    localparam CSR_MVENDORID = 12'hF11;
    localparam CSR_MARCHID   = 12'hF12;
    localparam CSR_MIMPID    = 12'hF13;
    localparam CSR_MHARTID   = 12'hF14;
    
    //=========================================================
    // CSR Registers
    //=========================================================
    // mstatus fields
    reg        mstatus_mie;   // Machine Interrupt Enable
    reg        mstatus_mpie;  // Previous MIE
    reg [1:0]  mstatus_mpp;   // Previous Privilege (always M-mode = 2'b11)
    
    // misa (read-only)
    wire [XLEN-1:0] misa;
    assign misa = {2'b01,           // MXL = 32-bit
                   4'b0,            // Reserved
                   26'b00000001000100000100000000};  // I, M extensions
    
    // mie - interrupt enable
    reg        mie_meie;  // Machine External Interrupt Enable
    reg        mie_mtie;  // Machine Timer Interrupt Enable
    reg        mie_msie;  // Machine Software Interrupt Enable
    
    // mtvec
    reg [XLEN-1:0] mtvec;
    
    // mscratch
    reg [XLEN-1:0] mscratch;
    
    // mepc
    reg [XLEN-1:0] mepc;
    
    // mcause
    reg        mcause_interrupt;
    reg [3:0]  mcause_code;
    
    // mtval
    reg [XLEN-1:0] mtval;
    
    // mip - interrupt pending (partially read-only)
    wire       mip_meip;  // External interrupt pending
    wire       mip_mtip;  // Timer interrupt pending
    wire       mip_msip;  // Software interrupt pending
    
    assign mip_meip = ext_irq_i;
    assign mip_mtip = timer_irq_i;
    assign mip_msip = sw_irq_i;
    
    // Counters
    reg [63:0] mcycle;
    reg [63:0] minstret;
    
    //=========================================================
    // Output Assignments
    //=========================================================
    assign mtvec_o = mtvec;
    assign mepc_o = mepc;
    assign mie_o = mstatus_mie;
    
    // Interrupt pending
    assign irq_pending_o = mstatus_mie && (
        (mie_meie && mip_meip) ||
        (mie_mtie && mip_mtip) ||
        (mie_msie && mip_msip)
    );
    
    //=========================================================
    // CSR Read Logic
    //=========================================================
    always @(*) begin
        csr_rdata_o = 0;
        csr_illegal_o = 0;
        
        case (csr_addr_i)
            CSR_MSTATUS: begin
                csr_rdata_o = {19'b0, mstatus_mpp, 3'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};
            end
            CSR_MISA: csr_rdata_o = misa;
            CSR_MIE: begin
                csr_rdata_o = {20'b0, mie_meie, 3'b0, mie_mtie, 3'b0, mie_msie, 3'b0};
            end
            CSR_MTVEC: csr_rdata_o = mtvec;
            CSR_MSCRATCH: csr_rdata_o = mscratch;
            CSR_MEPC: csr_rdata_o = mepc;
            CSR_MCAUSE: csr_rdata_o = {mcause_interrupt, 27'b0, mcause_code};
            CSR_MTVAL: csr_rdata_o = mtval;
            CSR_MIP: begin
                csr_rdata_o = {20'b0, mip_meip, 3'b0, mip_mtip, 3'b0, mip_msip, 3'b0};
            end
            CSR_MCYCLE: csr_rdata_o = mcycle[31:0];
            CSR_MCYCLEH: csr_rdata_o = mcycle[63:32];
            CSR_MINSTRET: csr_rdata_o = minstret[31:0];
            CSR_MINSTRETH: csr_rdata_o = minstret[63:32];
            CSR_MVENDORID: csr_rdata_o = 32'h0;
            CSR_MARCHID: csr_rdata_o = 32'h0;
            CSR_MIMPID: csr_rdata_o = 32'h0;
            CSR_MHARTID: csr_rdata_o = hart_id_i;
            default: csr_illegal_o = csr_valid_i;
        endcase
    end

    //=========================================================
    // CSR Write Logic
    //=========================================================
    wire [XLEN-1:0] csr_wdata_final;
    reg  [XLEN-1:0] csr_rdata_reg;
    
    // Compute write data based on operation
    always @(*) begin
        csr_rdata_reg = csr_rdata_o;
    end
    
    assign csr_wdata_final = (csr_op_i == 3'b001) ? csr_wdata_i :                    // CSRRW
                             (csr_op_i == 3'b010) ? (csr_rdata_reg | csr_wdata_i) :  // CSRRS
                             (csr_op_i == 3'b011) ? (csr_rdata_reg & ~csr_wdata_i) : // CSRRC
                             (csr_op_i == 3'b101) ? csr_wdata_i :                    // CSRRWI
                             (csr_op_i == 3'b110) ? (csr_rdata_reg | csr_wdata_i) :  // CSRRSI
                             (csr_op_i == 3'b111) ? (csr_rdata_reg & ~csr_wdata_i) : // CSRRCI
                             csr_wdata_i;
    
    //=========================================================
    // Sequential Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // mstatus
            mstatus_mie <= 1'b0;
            mstatus_mpie <= 1'b0;
            mstatus_mpp <= 2'b11;  // M-mode
            
            // mie
            mie_meie <= 1'b0;
            mie_mtie <= 1'b0;
            mie_msie <= 1'b0;
            
            // Other CSRs
            mtvec <= 32'h0;
            mscratch <= 32'h0;
            mepc <= 32'h0;
            mcause_interrupt <= 1'b0;
            mcause_code <= 4'h0;
            mtval <= 32'h0;
            
            // Counters
            mcycle <= 64'h0;
            minstret <= 64'h0;
        end else begin
            // Increment cycle counter
            mcycle <= mcycle + 1;
            
            //=================================================
            // Exception Handling
            //=================================================
            if (exception_i) begin
                // Save current state
                mstatus_mpie <= mstatus_mie;
                mstatus_mie <= 1'b0;  // Disable interrupts
                mstatus_mpp <= 2'b11; // Previous mode = M
                
                // Save exception info
                mepc <= exc_pc_i;
                mcause_interrupt <= 1'b0;
                mcause_code <= exc_code_i;
                mtval <= exc_tval_i;
            end
            //=================================================
            // MRET
            //=================================================
            else if (mret_i) begin
                mstatus_mie <= mstatus_mpie;
                mstatus_mpie <= 1'b1;
                mstatus_mpp <= 2'b11;
            end
            //=================================================
            // CSR Write
            //=================================================
            else if (csr_valid_i && !csr_illegal_o) begin
                case (csr_addr_i)
                    CSR_MSTATUS: begin
                        mstatus_mie <= csr_wdata_final[3];
                        mstatus_mpie <= csr_wdata_final[7];
                        mstatus_mpp <= csr_wdata_final[12:11];
                    end
                    CSR_MIE: begin
                        mie_msie <= csr_wdata_final[3];
                        mie_mtie <= csr_wdata_final[7];
                        mie_meie <= csr_wdata_final[11];
                    end
                    CSR_MTVEC: mtvec <= {csr_wdata_final[XLEN-1:2], 2'b00};
                    CSR_MSCRATCH: mscratch <= csr_wdata_final;
                    CSR_MEPC: mepc <= {csr_wdata_final[XLEN-1:2], 2'b00};
                    CSR_MCAUSE: begin
                        mcause_interrupt <= csr_wdata_final[31];
                        mcause_code <= csr_wdata_final[3:0];
                    end
                    CSR_MTVAL: mtval <= csr_wdata_final;
                    // MIP is mostly read-only
                    // Counters are read-only in this implementation
                    default: ;
                endcase
            end
        end
    end

endmodule
