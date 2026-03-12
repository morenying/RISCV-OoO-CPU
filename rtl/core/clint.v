//=================================================================
// Module: clint
// Description: Core Local Interruptor (CLINT)
//              Provides machine-level timer and software interrupts
//              Memory-mapped registers for mtime, mtimecmp, msip
// Requirements: Linux requires timer interrupts for scheduling
//=================================================================

`timescale 1ns/1ps

module clint #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter NUM_HARTS  = 1,           // Number of hardware threads
    parameter BASE_ADDR  = 32'h0200_0000  // CLINT base address
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     rtc_clk,          // Real-time clock (lower freq)
    
    //=========================================================
    // Memory-mapped Interface
    //=========================================================
    input  wire                     req_valid_i,
    input  wire                     req_we_i,
    input  wire [ADDR_WIDTH-1:0]    req_addr_i,
    input  wire [DATA_WIDTH-1:0]    req_wdata_i,
    input  wire [3:0]               req_be_i,         // Byte enable
    output reg                      req_ready_o,
    
    output reg                      resp_valid_o,
    output reg  [DATA_WIDTH-1:0]    resp_data_o,
    
    //=========================================================
    // Interrupt Outputs (per hart)
    //=========================================================
    output wire [NUM_HARTS-1:0]     msi_o,            // Machine software interrupt
    output wire [NUM_HARTS-1:0]     mti_o             // Machine timer interrupt
);

    //=========================================================
    // Address Map (relative to BASE_ADDR)
    // 0x0000 - 0x3FFF: msip[hart] (4 bytes per hart)
    // 0x4000 - 0xBFF7: mtimecmp[hart] (8 bytes per hart)
    // 0xBFF8 - 0xBFFF: mtime (8 bytes, shared)
    //=========================================================
    localparam MSIP_BASE     = 16'h0000;
    localparam MTIMECMP_BASE = 16'h4000;
    localparam MTIME_ADDR    = 16'hBFF8;
    
    //=========================================================
    // Registers
    //=========================================================
    // mtime: 64-bit timer counter
    reg [63:0] mtime;
    
    // mtimecmp: 64-bit timer compare for each hart
    reg [63:0] mtimecmp [0:NUM_HARTS-1];
    
    // msip: Software interrupt pending for each hart
    reg [NUM_HARTS-1:0] msip;
    
    //=========================================================
    // RTC Synchronization
    //=========================================================
    reg [2:0] rtc_sync;
    wire rtc_tick = rtc_sync[2] ^ rtc_sync[1];
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rtc_sync <= 3'b0;
        end else begin
            rtc_sync <= {rtc_sync[1:0], rtc_clk};
        end
    end
    
    //=========================================================
    // mtime Counter
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime <= 64'b0;
        end else if (rtc_tick) begin
            mtime <= mtime + 1;
        end
    end
    
    //=========================================================
    // Timer Interrupt Generation
    //=========================================================
    genvar h;
    generate
        for (h = 0; h < NUM_HARTS; h = h + 1) begin : gen_mti
            assign mti_o[h] = (mtime >= mtimecmp[h]);
        end
    endgenerate
    
    //=========================================================
    // Software Interrupt Output
    //=========================================================
    assign msi_o = msip;
    
    //=========================================================
    // Address Decoding
    //=========================================================
    wire [ADDR_WIDTH-1:0] offset = req_addr_i - BASE_ADDR;
    wire [15:0] reg_offset = offset[15:0];
    
    // Detect which register is being accessed
    wire is_msip_access = (reg_offset < MTIMECMP_BASE);
    wire is_mtimecmp_access = (reg_offset >= MTIMECMP_BASE) && (reg_offset < MTIME_ADDR);
    wire is_mtime_access = (reg_offset >= MTIME_ADDR);
    
    // Hart index for msip/mtimecmp
    wire [3:0] msip_hart = reg_offset[5:2];
    wire [3:0] mtimecmp_hart = (reg_offset - MTIMECMP_BASE) >> 3;
    wire       mtimecmp_hi = reg_offset[2];  // High or low 32 bits
    wire       mtime_hi = reg_offset[2];
    
    //=========================================================
    // Read/Write Logic
    //=========================================================
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_ready_o <= 0;
            resp_valid_o <= 0;
            resp_data_o <= 0;
            msip <= 0;
            
            for (i = 0; i < NUM_HARTS; i = i + 1) begin
                mtimecmp[i] <= 64'hFFFF_FFFF_FFFF_FFFF;  // Start with max value
            end
        end else begin
            req_ready_o <= req_valid_i;
            resp_valid_o <= req_valid_i;
            
            if (req_valid_i) begin
                if (req_we_i) begin
                    // Write operation
                    if (is_msip_access) begin
                        if (msip_hart < NUM_HARTS) begin
                            msip[msip_hart] <= req_wdata_i[0];
                        end
                    end else if (is_mtimecmp_access) begin
                        if (mtimecmp_hart < NUM_HARTS) begin
                            if (mtimecmp_hi) begin
                                mtimecmp[mtimecmp_hart][63:32] <= req_wdata_i;
                            end else begin
                                mtimecmp[mtimecmp_hart][31:0] <= req_wdata_i;
                            end
                        end
                    end
                    // mtime is read-only (or can be made writable for testing)
                    
                    resp_data_o <= 0;
                end else begin
                    // Read operation
                    resp_data_o <= 0;
                    
                    if (is_msip_access) begin
                        if (msip_hart < NUM_HARTS) begin
                            resp_data_o <= {31'b0, msip[msip_hart]};
                        end
                    end else if (is_mtimecmp_access) begin
                        if (mtimecmp_hart < NUM_HARTS) begin
                            if (mtimecmp_hi) begin
                                resp_data_o <= mtimecmp[mtimecmp_hart][63:32];
                            end else begin
                                resp_data_o <= mtimecmp[mtimecmp_hart][31:0];
                            end
                        end
                    end else if (is_mtime_access) begin
                        if (mtime_hi) begin
                            resp_data_o <= mtime[63:32];
                        end else begin
                            resp_data_o <= mtime[31:0];
                        end
                    end
                end
            end else begin
                resp_valid_o <= 0;
            end
        end
    end

endmodule
