`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// Boot ROM Module
//
// Features:
// - 16KB BRAM-based read-only memory for bootloader code
// - Supports initialization from .hex file
// - Single-cycle read latency
// - 32-bit word-aligned access
// - Immutable at runtime (true ROM behavior)
// - AXI4-Lite slave interface
//
// Memory Organization:
// - Address range: 0x0000_0000 - 0x0000_3FFF (16KB)
// - Word-aligned access only (addr[1:0] ignored)
// - Big-endian byte order in hex file
//
// 禁止事项:
// - 禁止使用分布式 RAM (必须使用 BRAM)
// - 禁止运行时修改 (必须是只读)
// - 禁止硬编码内容 (必须从 hex 文件加载)
//////////////////////////////////////////////////////////////////////////////

module bootrom #(
    parameter DEPTH = 4096,                    // Number of 32-bit words (16KB)
    parameter ADDR_WIDTH = 14,                 // Address width (byte address)
    parameter INIT_FILE = "none"              // Initialization file ("none" = no file)
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // AXI4-Lite Slave Interface (Read-Only)
    input  wire                    axi_arvalid,
    output reg                     axi_arready,
    input  wire [31:0]             axi_araddr,
    
    output reg                     axi_rvalid,
    input  wire                    axi_rready,
    output reg  [31:0]             axi_rdata,
    output wire [1:0]              axi_rresp,
    
    // Write interface (always returns error - ROM is read-only)
    input  wire                    axi_awvalid,
    output wire                    axi_awready,
    input  wire [31:0]             axi_awaddr,
    
    input  wire                    axi_wvalid,
    output wire                    axi_wready,
    input  wire [31:0]             axi_wdata,
    input  wire [3:0]              axi_wstrb,
    
    output reg                     axi_bvalid,
    input  wire                    axi_bready,
    output wire [1:0]              axi_bresp
);

    //==========================================================================
    // BRAM Declaration
    //==========================================================================
    // Use (* ram_style = "block" *) to force BRAM inference in Xilinx
    (* ram_style = "block" *)
    reg [31:0] rom_mem [0:DEPTH-1];
    
    //==========================================================================
    // ROM Initialization from Hex File
    //==========================================================================
    integer init_i;
    initial begin
        // Initialize all memory to NOP (ADDI x0, x0, 0 = 0x00000013)
        for (init_i = 0; init_i < DEPTH; init_i = init_i + 1) begin
            rom_mem[init_i] = 32'h00000013;  // NOP instruction
        end
        
        // Load hex file if specified and not empty
        `ifdef SIMULATION
        if (INIT_FILE != "" && INIT_FILE != "none") begin
            $readmemh(INIT_FILE, rom_mem);
        end
        `else
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, rom_mem);
        end
        `endif
    end
    
    //==========================================================================
    // Address Calculation
    //==========================================================================
    wire [ADDR_WIDTH-3:0] word_addr;  // Word address (drop lower 2 bits)
    reg  [ADDR_WIDTH-3:0] read_addr_reg;
    
    assign word_addr = axi_araddr[ADDR_WIDTH-1:2];
    
    //==========================================================================
    // Read Response
    //==========================================================================
    // ROM always returns OKAY for reads
    assign axi_rresp = 2'b00;  // OKAY
    
    //==========================================================================
    // Write Response (Always Error - ROM is Read-Only)
    //==========================================================================
    // Writes to ROM return SLVERR (slave error)
    assign axi_awready = 1'b1;  // Accept address immediately
    assign axi_wready  = 1'b1;  // Accept data immediately
    assign axi_bresp   = 2'b10; // SLVERR - write to ROM not allowed
    
    //==========================================================================
    // Read State Machine
    //==========================================================================
    // AXI4-Lite Read Protocol:
    // 1. Master asserts ARVALID with address
    // 2. Slave asserts ARREADY to accept address (handshake on ARVALID && ARREADY)
    // 3. Slave asserts RVALID with data
    // 4. Master asserts RREADY to accept data (handshake on RVALID && RREADY)
    // 5. Transaction complete
    //
    // State machine: IDLE -> DATA -> RESP -> IDLE
    // - IDLE: Wait for address, arready=1
    // - DATA: Read from BRAM (1 cycle latency for BRAM)
    // - RESP: Hold rvalid=1 until rready
    //==========================================================================
    
    localparam READ_IDLE = 2'b00;
    localparam READ_DATA = 2'b01;
    localparam READ_RESP = 2'b10;
    
    reg [1:0] read_state;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_state    <= READ_IDLE;
            axi_arready   <= 1'b1;
            axi_rvalid    <= 1'b0;
            axi_rdata     <= 32'd0;
            read_addr_reg <= {(ADDR_WIDTH-2){1'b0}};
        end else begin
            case (read_state)
                READ_IDLE: begin
                    // Ready to accept new address
                    axi_arready <= 1'b1;
                    axi_rvalid  <= 1'b0;
                    
                    if (axi_arvalid && axi_arready) begin
                        // Address handshake complete - capture address
                        read_addr_reg <= word_addr;
                        axi_arready   <= 1'b0;  // No longer ready for new address
                        read_state    <= READ_DATA;
                    end
                end
                
                READ_DATA: begin
                    // BRAM read - data available after 1 cycle
                    // Output data and assert rvalid
                    axi_rdata  <= rom_mem[read_addr_reg];
                    axi_rvalid <= 1'b1;
                    read_state <= READ_RESP;
                end
                
                READ_RESP: begin
                    // Wait for master to accept data
                    if (axi_rvalid && axi_rready) begin
                        // Data handshake complete
                        axi_rvalid  <= 1'b0;
                        axi_arready <= 1'b1;  // Ready for next address
                        read_state  <= READ_IDLE;
                    end
                    // Keep rvalid asserted until accepted
                end
                
                default: begin
                    read_state  <= READ_IDLE;
                    axi_arready <= 1'b1;
                    axi_rvalid  <= 1'b0;
                end
            endcase
        end
    end
    
    //==========================================================================
    // Write State Machine (Returns Error)
    //==========================================================================
    // ROM does not support writes - return error response
    
    reg write_pending;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_bvalid    <= 1'b0;
            write_pending <= 1'b0;
        end else begin
            // Track write transactions
            if (axi_awvalid && axi_awready) begin
                write_pending <= 1'b1;
            end
            
            // Generate error response when both address and data received
            if (write_pending && axi_wvalid && axi_wready) begin
                axi_bvalid    <= 1'b1;
                write_pending <= 1'b0;
            end
            
            // Clear response when accepted
            if (axi_bvalid && axi_bready) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    //==========================================================================
    // Debug: ROM Content Verification
    //==========================================================================
    `ifdef SIMULATION
    `ifdef DEBUG_BOOTROM
    initial begin
        #100;  // Wait for initialization
        $display("BootROM: Loaded from %s", INIT_FILE);
        $display("BootROM: First 4 instructions:");
        $display("  [0x0000] = 0x%08X", rom_mem[0]);
        $display("  [0x0004] = 0x%08X", rom_mem[1]);
        $display("  [0x0008] = 0x%08X", rom_mem[2]);
        $display("  [0x000C] = 0x%08X", rom_mem[3]);
    end
    `endif
    `endif

endmodule
