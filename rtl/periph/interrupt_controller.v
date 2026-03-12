`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// Interrupt Controller (INTC)
// 
// Features:
// - 8 interrupt sources with configurable priority
// - Edge-triggered and level-triggered modes (per interrupt)
// - 2-stage synchronizer for external interrupts (async safety)
// - Priority encoder with programmable priorities
// - Interrupt pending, enable, mask, clear registers
// - Nested interrupt support (high priority can preempt low priority)
// - AXI4-Lite register interface
//
// Register Map:
// 0x00 - IRQ_PENDING:  [7:0] Interrupt pending flags (read-only, write-1-clear)
// 0x04 - IRQ_ENABLE:   [7:0] Interrupt enable bits
// 0x08 - IRQ_MASK:     [7:0] Interrupt mask bits (1=masked)
// 0x0C - IRQ_TRIGGER:  [7:0] Trigger mode (0=level, 1=edge)
// 0x10 - IRQ_PRIORITY0:[31:0] Priority for IRQ 0-3 (8 bits each, 0=highest)
// 0x14 - IRQ_PRIORITY1:[31:0] Priority for IRQ 4-7 (8 bits each, 0=highest)
// 0x18 - IRQ_ACTIVE:   [7:0] Currently active interrupt (being serviced)
// 0x1C - IRQ_CURRENT:  [3:0] Current highest priority pending IRQ ID
// 0x20 - IRQ_THRESHOLD:[7:0] Priority threshold (only IRQs with priority < threshold)
// 0x24 - IRQ_EOI:      [7:0] End of interrupt (write IRQ bit to signal completion)
// 0x28 - IRQ_EDGE_DET: [7:0] Edge detection status (for debugging)
// 0x2C - IRQ_CTRL:     [7:0] Control register
//
// 禁止事项:
// - 禁止只支持单一触发模式
// - 禁止固定优先级
// - 禁止直接使用异步信号
// - 禁止禁用嵌套中断来"简化"实现
// - 禁止中断丢失
//////////////////////////////////////////////////////////////////////////////

module interrupt_controller #(
    parameter NUM_IRQS = 8,           // Number of interrupt sources
    parameter SYNC_STAGES = 2,        // Synchronizer stages for async inputs
    parameter DEFAULT_PRIORITY = 8'h0F // Default priority (lower = higher priority)
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // AXI4-Lite Slave Interface
    input  wire                  axi_awvalid,
    output wire                  axi_awready,
    input  wire [7:0]            axi_awaddr,
    
    input  wire                  axi_wvalid,
    output wire                  axi_wready,
    input  wire [31:0]           axi_wdata,
    input  wire [3:0]            axi_wstrb,
    
    output reg                   axi_bvalid,
    input  wire                  axi_bready,
    output wire [1:0]            axi_bresp,
    
    input  wire                  axi_arvalid,
    output wire                  axi_arready,
    input  wire [7:0]            axi_araddr,
    
    output reg                   axi_rvalid,
    input  wire                  axi_rready,
    output reg  [31:0]           axi_rdata,
    output wire [1:0]            axi_rresp,
    
    // Interrupt Sources (directly from peripherals)
    input  wire [NUM_IRQS-1:0]   irq_sources,
    
    // CPU Interface
    output wire                  irq_to_cpu,      // Interrupt request to CPU
    output wire [3:0]            irq_id,          // Current highest priority IRQ ID
    output wire [7:0]            irq_priority_out,// Priority of current IRQ
    input  wire                  irq_ack,         // CPU acknowledges interrupt
    input  wire                  irq_complete     // CPU signals interrupt completion
);

    //==========================================================================
    // Register Addresses
    //==========================================================================
    localparam ADDR_PENDING    = 8'h00;
    localparam ADDR_ENABLE     = 8'h04;
    localparam ADDR_MASK       = 8'h08;
    localparam ADDR_TRIGGER    = 8'h0C;
    localparam ADDR_PRIORITY0  = 8'h10;
    localparam ADDR_PRIORITY1  = 8'h14;
    localparam ADDR_ACTIVE     = 8'h18;
    localparam ADDR_CURRENT    = 8'h1C;
    localparam ADDR_THRESHOLD  = 8'h20;
    localparam ADDR_EOI        = 8'h24;
    localparam ADDR_EDGE_DET   = 8'h28;
    localparam ADDR_CTRL       = 8'h2C;
    
    //==========================================================================
    // Control Register Bits
    //==========================================================================
    localparam CTRL_GLOBAL_EN  = 0;   // Global interrupt enable
    localparam CTRL_NEST_EN    = 1;   // Nested interrupt enable
    localparam CTRL_AUTO_EOI   = 2;   // Automatic EOI on acknowledge
    
    //==========================================================================
    // Internal Registers
    //==========================================================================
    reg [NUM_IRQS-1:0]  irq_pending;      // Pending interrupts
    reg [NUM_IRQS-1:0]  irq_enable;       // Interrupt enable
    reg [NUM_IRQS-1:0]  irq_mask;         // Interrupt mask (1=masked)
    reg [NUM_IRQS-1:0]  irq_trigger;      // Trigger mode (0=level, 1=edge)
    reg [7:0]           irq_priority [0:NUM_IRQS-1]; // Priority per IRQ
    reg [NUM_IRQS-1:0]  irq_active;       // Currently being serviced
    reg [7:0]           irq_threshold;    // Priority threshold
    reg [7:0]           ctrl_reg;         // Control register
    
    //==========================================================================
    // Synchronizer for External Interrupts (2-stage)
    //==========================================================================
    reg [NUM_IRQS-1:0]  irq_sync_stage1;
    reg [NUM_IRQS-1:0]  irq_sync_stage2;
    wire [NUM_IRQS-1:0] irq_synchronized;
    
    // 2-stage synchronizer to prevent metastability
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_sync_stage1 <= {NUM_IRQS{1'b0}};
            irq_sync_stage2 <= {NUM_IRQS{1'b0}};
        end else begin
            irq_sync_stage1 <= irq_sources;
            irq_sync_stage2 <= irq_sync_stage1;
        end
    end
    
    assign irq_synchronized = irq_sync_stage2;
    
    //==========================================================================
    // Edge Detection for Edge-Triggered Interrupts
    //==========================================================================
    reg [NUM_IRQS-1:0]  irq_prev;
    wire [NUM_IRQS-1:0] irq_rising_edge;
    reg [NUM_IRQS-1:0]  edge_detected;    // Latched edge detection
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_prev <= {NUM_IRQS{1'b0}};
        end else begin
            irq_prev <= irq_synchronized;
        end
    end
    
    // Rising edge detection
    assign irq_rising_edge = irq_synchronized & ~irq_prev;
    
    // Edge detection latch - prevents edge loss
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            edge_detected <= {NUM_IRQS{1'b0}};
        end else begin
            // Set on rising edge, clear when pending is set
            edge_detected <= (edge_detected | irq_rising_edge) & ~irq_pending;
        end
    end

    //==========================================================================
    // Interrupt Pending Logic
    //==========================================================================
    // For level-triggered: pending = synchronized signal (follows signal level)
    // For edge-triggered: pending = latched until cleared
    
    wire [NUM_IRQS-1:0] irq_raw_pending;
    
    genvar i;
    generate
        for (i = 0; i < NUM_IRQS; i = i + 1) begin : gen_pending
            assign irq_raw_pending[i] = irq_trigger[i] ? 
                                        edge_detected[i] :  // Edge-triggered
                                        irq_synchronized[i]; // Level-triggered
        end
    endgenerate
    
    // For level-triggered: pending follows signal directly
    // For edge-triggered: pending latches until cleared
    wire [NUM_IRQS-1:0] level_pending = irq_synchronized & ~irq_trigger;  // Level-triggered pending
    wire [NUM_IRQS-1:0] edge_pending_set = edge_detected & irq_trigger;   // Edge-triggered set
    
    //==========================================================================
    // Priority Encoder - Find Highest Priority Pending Interrupt
    //==========================================================================
    // Lower priority value = higher priority
    // Returns IRQ ID of highest priority pending interrupt
    
    reg [3:0]  highest_priority_irq;
    reg [7:0]  highest_priority_val;
    reg        any_pending;
    
    // Effective pending = pending & enabled & ~masked & ~active (unless nesting)
    wire [NUM_IRQS-1:0] effective_pending;
    
    generate
        for (i = 0; i < NUM_IRQS; i = i + 1) begin : gen_effective
            // For nested interrupts: allow if priority < current active priority
            // For non-nested: only allow if not currently servicing any interrupt
            assign effective_pending[i] = irq_pending[i] & 
                                          irq_enable[i] & 
                                          ~irq_mask[i] &
                                          (irq_priority[i] < irq_threshold);
        end
    endgenerate
    
    // Priority encoder - combinational logic
    // Find the lowest priority value (highest priority) among pending interrupts
    always @(*) begin
        highest_priority_irq = 4'd0;
        highest_priority_val = 8'hFF;  // Lowest priority (no interrupt)
        any_pending = 1'b0;
        
        // Check each interrupt source
        // Priority: lower value = higher priority
        if (effective_pending[0] && irq_priority[0] < highest_priority_val) begin
            highest_priority_irq = 4'd0;
            highest_priority_val = irq_priority[0];
            any_pending = 1'b1;
        end
        if (effective_pending[1] && irq_priority[1] < highest_priority_val) begin
            highest_priority_irq = 4'd1;
            highest_priority_val = irq_priority[1];
            any_pending = 1'b1;
        end
        if (effective_pending[2] && irq_priority[2] < highest_priority_val) begin
            highest_priority_irq = 4'd2;
            highest_priority_val = irq_priority[2];
            any_pending = 1'b1;
        end
        if (effective_pending[3] && irq_priority[3] < highest_priority_val) begin
            highest_priority_irq = 4'd3;
            highest_priority_val = irq_priority[3];
            any_pending = 1'b1;
        end
        if (effective_pending[4] && irq_priority[4] < highest_priority_val) begin
            highest_priority_irq = 4'd4;
            highest_priority_val = irq_priority[4];
            any_pending = 1'b1;
        end
        if (effective_pending[5] && irq_priority[5] < highest_priority_val) begin
            highest_priority_irq = 4'd5;
            highest_priority_val = irq_priority[5];
            any_pending = 1'b1;
        end
        if (effective_pending[6] && irq_priority[6] < highest_priority_val) begin
            highest_priority_irq = 4'd6;
            highest_priority_val = irq_priority[6];
            any_pending = 1'b1;
        end
        if (effective_pending[7] && irq_priority[7] < highest_priority_val) begin
            highest_priority_irq = 4'd7;
            highest_priority_val = irq_priority[7];
            any_pending = 1'b1;
        end
    end
    
    //==========================================================================
    // Nested Interrupt Support
    //==========================================================================
    // Track the priority of currently active interrupt for nesting
    reg [7:0]  active_priority;
    reg [3:0]  active_irq_id;
    reg        interrupt_in_service;
    
    // Stack for nested interrupts (up to 8 levels)
    reg [7:0]  priority_stack [0:7];
    reg [3:0]  irq_id_stack [0:7];
    reg [2:0]  stack_ptr;
    
    // Can preempt if: nesting enabled AND new priority < active priority
    wire can_preempt = ctrl_reg[CTRL_NEST_EN] && 
                       interrupt_in_service && 
                       (highest_priority_val < active_priority);
    
    // Generate interrupt to CPU
    wire irq_request = ctrl_reg[CTRL_GLOBAL_EN] && any_pending && 
                       (!interrupt_in_service || can_preempt);
    
    assign irq_to_cpu = irq_request;
    assign irq_id = highest_priority_irq;
    assign irq_priority_out = highest_priority_val;
    
    //==========================================================================
    // Interrupt State Machine
    //==========================================================================
    
    // EOI write signal from AXI
    reg [NUM_IRQS-1:0] eoi_write;
    // Pending clear from AXI write-1-clear
    reg [NUM_IRQS-1:0] pending_clear;
    
    // Combined clear signal
    wire [NUM_IRQS-1:0] pending_clear_all = eoi_write | pending_clear;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_pending <= {NUM_IRQS{1'b0}};
            irq_active <= {NUM_IRQS{1'b0}};
            active_priority <= 8'hFF;
            active_irq_id <= 4'd0;
            interrupt_in_service <= 1'b0;
            stack_ptr <= 3'd0;
        end else begin
            // Update pending register
            // For level-triggered: pending follows signal level directly
            // For edge-triggered: pending latches until cleared
            // Clear: when EOI written, write-1-clear to pending, or auto-EOI on ack
            
            // Calculate new pending value for edge-triggered interrupts
            // Edge-triggered: latch on edge, clear on explicit clear
            // Level-triggered: follows signal directly (handled separately)
            irq_pending <= (level_pending) |                                    // Level: follows signal
                           ((irq_pending & irq_trigger) | edge_pending_set) &   // Edge: latch
                           ~pending_clear_all;                                   // Clear on EOI/write-1-clear
            
            // Handle interrupt acknowledge from CPU
            if (irq_ack && irq_request) begin
                // Push current context if nesting
                if (interrupt_in_service && can_preempt) begin
                    priority_stack[stack_ptr] <= active_priority;
                    irq_id_stack[stack_ptr] <= active_irq_id;
                    stack_ptr <= stack_ptr + 1'b1;
                end
                
                // Mark interrupt as active
                irq_active[highest_priority_irq] <= 1'b1;
                active_priority <= highest_priority_val;
                active_irq_id <= highest_priority_irq;
                interrupt_in_service <= 1'b1;
                
                // Auto-EOI: clear pending immediately on acknowledge (for edge-triggered)
                if (ctrl_reg[CTRL_AUTO_EOI] && irq_trigger[highest_priority_irq]) begin
                    irq_pending[highest_priority_irq] <= 1'b0;
                end
            end
            
            // Handle EOI (End of Interrupt) - clears active and pending
            if (|eoi_write && interrupt_in_service) begin
                // Clear active bit for completed interrupt
                irq_active <= irq_active & ~eoi_write;
                
                // Pop from stack if nested
                if (stack_ptr > 0) begin
                    stack_ptr <= stack_ptr - 1'b1;
                    active_priority <= priority_stack[stack_ptr - 1];
                    active_irq_id <= irq_id_stack[stack_ptr - 1];
                end else begin
                    // No more nested interrupts
                    interrupt_in_service <= 1'b0;
                    active_priority <= 8'hFF;
                    active_irq_id <= 4'd0;
                end
            end
            
            // Handle irq_complete signal from CPU
            if (irq_complete && interrupt_in_service) begin
                irq_active[active_irq_id] <= 1'b0;
                
                if (stack_ptr > 0) begin
                    stack_ptr <= stack_ptr - 1'b1;
                    active_priority <= priority_stack[stack_ptr - 1];
                    active_irq_id <= irq_id_stack[stack_ptr - 1];
                end else begin
                    interrupt_in_service <= 1'b0;
                    active_priority <= 8'hFF;
                    active_irq_id <= 4'd0;
                end
            end
        end
    end

    //==========================================================================
    // AXI Interface Logic
    //==========================================================================
    
    // Write channel
    reg        aw_ready_reg;
    reg        w_ready_reg;
    reg [7:0]  aw_addr_reg;
    reg        aw_valid_reg;
    
    assign axi_awready = aw_ready_reg;
    assign axi_wready  = w_ready_reg;
    assign axi_bresp   = 2'b00;  // OKAY
    
    // Read channel
    reg        ar_ready_reg;
    reg [7:0]  ar_addr_reg;
    
    assign axi_arready = ar_ready_reg;
    assign axi_rresp   = 2'b00;  // OKAY
    
    //==========================================================================
    // Write State Machine
    //==========================================================================
    
    integer j;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_ready_reg  <= 1'b1;
            w_ready_reg   <= 1'b0;
            aw_addr_reg   <= 8'd0;
            aw_valid_reg  <= 1'b0;
            axi_bvalid    <= 1'b0;
            irq_enable    <= {NUM_IRQS{1'b0}};
            irq_mask      <= {NUM_IRQS{1'b0}};
            irq_trigger   <= {NUM_IRQS{1'b0}};  // Default: level-triggered
            irq_threshold <= 8'hFF;              // Allow all priorities
            ctrl_reg      <= 8'h01;              // Global enable by default
            eoi_write     <= {NUM_IRQS{1'b0}};
            pending_clear <= {NUM_IRQS{1'b0}};
            
            // Initialize priorities
            for (j = 0; j < NUM_IRQS; j = j + 1) begin
                irq_priority[j] <= DEFAULT_PRIORITY;
            end
        end else begin
            // Clear one-shot signals
            eoi_write <= {NUM_IRQS{1'b0}};
            pending_clear <= {NUM_IRQS{1'b0}};
            
            // Address phase
            if (axi_awvalid && aw_ready_reg) begin
                aw_addr_reg  <= axi_awaddr;
                aw_valid_reg <= 1'b1;
                aw_ready_reg <= 1'b0;
                w_ready_reg  <= 1'b1;
            end
            
            // Data phase
            if (axi_wvalid && w_ready_reg && aw_valid_reg) begin
                w_ready_reg  <= 1'b0;
                aw_valid_reg <= 1'b0;
                axi_bvalid   <= 1'b1;
                
                // Register writes
                case (aw_addr_reg)
                    ADDR_PENDING: begin
                        // Write-1-clear for pending register
                        if (axi_wstrb[0]) begin
                            pending_clear <= axi_wdata[NUM_IRQS-1:0];
                        end
                    end
                    
                    ADDR_ENABLE: begin
                        if (axi_wstrb[0]) begin
                            irq_enable <= axi_wdata[NUM_IRQS-1:0];
                        end
                    end
                    
                    ADDR_MASK: begin
                        if (axi_wstrb[0]) begin
                            irq_mask <= axi_wdata[NUM_IRQS-1:0];
                        end
                    end
                    
                    ADDR_TRIGGER: begin
                        if (axi_wstrb[0]) begin
                            irq_trigger <= axi_wdata[NUM_IRQS-1:0];
                        end
                    end
                    
                    ADDR_PRIORITY0: begin
                        // IRQ 0-3 priorities
                        if (axi_wstrb[0]) irq_priority[0] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) irq_priority[1] <= axi_wdata[15:8];
                        if (axi_wstrb[2]) irq_priority[2] <= axi_wdata[23:16];
                        if (axi_wstrb[3]) irq_priority[3] <= axi_wdata[31:24];
                    end
                    
                    ADDR_PRIORITY1: begin
                        // IRQ 4-7 priorities
                        if (axi_wstrb[0]) irq_priority[4] <= axi_wdata[7:0];
                        if (axi_wstrb[1]) irq_priority[5] <= axi_wdata[15:8];
                        if (axi_wstrb[2]) irq_priority[6] <= axi_wdata[23:16];
                        if (axi_wstrb[3]) irq_priority[7] <= axi_wdata[31:24];
                    end
                    
                    ADDR_THRESHOLD: begin
                        if (axi_wstrb[0]) begin
                            irq_threshold <= axi_wdata[7:0];
                        end
                    end
                    
                    ADDR_EOI: begin
                        // End of interrupt - write 1 to clear
                        if (axi_wstrb[0]) begin
                            eoi_write <= axi_wdata[NUM_IRQS-1:0];
                        end
                    end
                    
                    ADDR_CTRL: begin
                        if (axi_wstrb[0]) begin
                            ctrl_reg <= axi_wdata[7:0];
                        end
                    end
                    
                    default: ;
                endcase
            end
            
            // Response phase
            if (axi_bvalid && axi_bready) begin
                axi_bvalid   <= 1'b0;
                aw_ready_reg <= 1'b1;
            end
            
            // Apply pending clear (write-1-clear)
            if (|pending_clear) begin
                // This is handled in the main pending logic
            end
        end
    end
    
    //==========================================================================
    // Read State Machine
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_ready_reg <= 1'b1;
            ar_addr_reg  <= 8'd0;
            axi_rvalid   <= 1'b0;
            axi_rdata    <= 32'd0;
        end else begin
            // Address phase
            if (axi_arvalid && ar_ready_reg) begin
                ar_addr_reg  <= axi_araddr;
                ar_ready_reg <= 1'b0;
                axi_rvalid   <= 1'b1;
                
                // Register reads
                case (axi_araddr)
                    ADDR_PENDING: begin
                        axi_rdata <= {24'd0, irq_pending};
                    end
                    
                    ADDR_ENABLE: begin
                        axi_rdata <= {24'd0, irq_enable};
                    end
                    
                    ADDR_MASK: begin
                        axi_rdata <= {24'd0, irq_mask};
                    end
                    
                    ADDR_TRIGGER: begin
                        axi_rdata <= {24'd0, irq_trigger};
                    end
                    
                    ADDR_PRIORITY0: begin
                        axi_rdata <= {irq_priority[3], irq_priority[2], 
                                      irq_priority[1], irq_priority[0]};
                    end
                    
                    ADDR_PRIORITY1: begin
                        axi_rdata <= {irq_priority[7], irq_priority[6], 
                                      irq_priority[5], irq_priority[4]};
                    end
                    
                    ADDR_ACTIVE: begin
                        axi_rdata <= {24'd0, irq_active};
                    end
                    
                    ADDR_CURRENT: begin
                        axi_rdata <= {24'd0, 4'd0, highest_priority_irq};
                    end
                    
                    ADDR_THRESHOLD: begin
                        axi_rdata <= {24'd0, irq_threshold};
                    end
                    
                    ADDR_EOI: begin
                        axi_rdata <= 32'd0;  // Write-only register
                    end
                    
                    ADDR_EDGE_DET: begin
                        axi_rdata <= {24'd0, edge_detected};
                    end
                    
                    ADDR_CTRL: begin
                        axi_rdata <= {24'd0, ctrl_reg};
                    end
                    
                    default: begin
                        axi_rdata <= 32'd0;
                    end
                endcase
            end
            
            // Data phase complete
            if (axi_rvalid && axi_rready) begin
                axi_rvalid   <= 1'b0;
                ar_ready_reg <= 1'b1;
            end
        end
    end
    
    //==========================================================================
    // Update pending with write-1-clear
    //==========================================================================
    // Note: pending_clear_all is used in the interrupt state machine above

endmodule
