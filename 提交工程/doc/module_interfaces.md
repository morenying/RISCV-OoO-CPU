# Module Interface Documentation

## Core Modules

### cpu_core_top

Top-level CPU core module.

```verilog
module cpu_core_top #(
    parameter XLEN = 32,
    parameter RESET_VECTOR = 32'h0000_0000
) (
    input  wire        clk,
    input  wire        rst_n,
    
    // Instruction AXI Interface
    output wire [31:0] ibus_axi_araddr_o,
    output wire        ibus_axi_arvalid_o,
    input  wire        ibus_axi_arready_i,
    ...
    
    // Data AXI Interface
    output wire [31:0] dbus_axi_araddr_o,
    ...
);
```

### alu_unit

Single-cycle ALU for integer operations.

```verilog
module alu_unit (
    input  wire        clk,
    input  wire        rst_n,
    
    // Input interface
    input  wire        valid_i,
    input  wire [3:0]  op_i,           // ALU operation
    input  wire [31:0] src1_i,         // Source operand 1
    input  wire [31:0] src2_i,         // Source operand 2
    input  wire [5:0]  dst_preg_i,     // Destination physical register
    input  wire [4:0]  rob_idx_i,      // ROB index
    
    // Output interface
    output wire        valid_o,
    output wire [31:0] result_o,
    output wire [5:0]  dst_preg_o,
    output wire [4:0]  rob_idx_o
);
```

### rob (Reorder Buffer)

Maintains program order for in-order commit.

```verilog
module rob #(
    parameter ROB_SIZE = 32,
    parameter XLEN = 32
) (
    input  wire        clk,
    input  wire        rst_n,
    
    // Allocate interface
    input  wire        alloc_valid_i,
    input  wire [4:0]  alloc_arch_rd_i,
    input  wire [5:0]  alloc_phys_rd_i,
    input  wire [31:0] alloc_pc_i,
    output wire [4:0]  alloc_idx_o,
    output wire        alloc_ready_o,
    
    // Complete interface
    input  wire        complete_valid_i,
    input  wire [4:0]  complete_idx_i,
    input  wire [31:0] complete_result_i,
    input  wire        complete_exception_i,
    
    // Commit interface
    output wire        commit_valid_o,
    output wire [4:0]  commit_arch_rd_o,
    output wire [5:0]  commit_phys_rd_o,
    output wire [31:0] commit_result_o,
    output wire [31:0] commit_pc_o,
    
    // Flush interface
    input  wire        flush_i,
    output wire        full_o,
    output wire        empty_o
);
```

### rat (Register Alias Table)

Maps architectural registers to physical registers.

```verilog
module rat #(
    parameter ARCH_REGS = 32,
    parameter PHYS_REGS = 64
) (
    input  wire        clk,
    input  wire        rst_n,
    
    // Read ports (for rename)
    input  wire [4:0]  rs1_arch_i,
    input  wire [4:0]  rs2_arch_i,
    output wire [5:0]  rs1_phys_o,
    output wire [5:0]  rs2_phys_o,
    output wire        rs1_ready_o,
    output wire        rs2_ready_o,
    
    // Write port (for rename)
    input  wire        wr_valid_i,
    input  wire [4:0]  wr_arch_i,
    input  wire [5:0]  wr_phys_i,
    
    // Commit port (mark ready)
    input  wire        commit_valid_i,
    input  wire [5:0]  commit_phys_i,
    
    // Flush
    input  wire        flush_i
);
```

### reservation_station

Holds instructions waiting for operands.

```verilog
module reservation_station #(
    parameter NUM_ENTRIES = 4,
    parameter XLEN = 32
) (
    input  wire        clk,
    input  wire        rst_n,
    
    // Allocate interface
    input  wire        alloc_valid_i,
    input  wire [3:0]  alloc_op_i,
    input  wire [31:0] alloc_src1_data_i,
    input  wire        alloc_src1_ready_i,
    input  wire [5:0]  alloc_src1_tag_i,
    input  wire [31:0] alloc_src2_data_i,
    input  wire        alloc_src2_ready_i,
    input  wire [5:0]  alloc_src2_tag_i,
    input  wire [5:0]  alloc_dst_preg_i,
    input  wire [4:0]  alloc_rob_idx_i,
    output wire        alloc_ready_o,
    
    // Issue interface
    output wire        issue_valid_o,
    output wire [3:0]  issue_op_o,
    output wire [31:0] issue_src1_data_o,
    output wire [31:0] issue_src2_data_o,
    output wire [5:0]  issue_dst_preg_o,
    output wire [4:0]  issue_rob_idx_o,
    input  wire        issue_ack_i,
    
    // CDB broadcast (for wakeup)
    input  wire        cdb_valid_i,
    input  wire [5:0]  cdb_tag_i,
    input  wire [31:0] cdb_data_i,
    
    // Flush
    input  wire        flush_i
);
```

## Memory Modules

### icache

4KB 4-way set associative instruction cache.

```verilog
module icache #(
    parameter CACHE_SIZE = 4096,
    parameter LINE_SIZE = 32,
    parameter WAYS = 4
) (
    input  wire        clk,
    input  wire        rst_n,
    
    // CPU interface
    input  wire [31:0] addr_i,
    input  wire        req_i,
    output wire [31:0] data_o,
    output wire        valid_o,
    output wire        ready_o,
    
    // Memory interface
    output wire [31:0] mem_addr_o,
    output wire        mem_req_o,
    input  wire [31:0] mem_data_i,
    input  wire        mem_valid_i
);
```

### dcache

4KB 4-way set associative data cache with write-back.

```verilog
module dcache #(
    parameter CACHE_SIZE = 4096,
    parameter LINE_SIZE = 32,
    parameter WAYS = 4
) (
    input  wire        clk,
    input  wire        rst_n,
    
    // CPU interface
    input  wire [31:0] addr_i,
    input  wire [31:0] wdata_i,
    input  wire [3:0]  wstrb_i,
    input  wire        req_i,
    input  wire        we_i,
    output wire [31:0] rdata_o,
    output wire        valid_o,
    output wire        ready_o,
    
    // Memory interface
    output wire [31:0] mem_addr_o,
    output wire [31:0] mem_wdata_o,
    output wire        mem_req_o,
    output wire        mem_we_o,
    input  wire [31:0] mem_rdata_i,
    input  wire        mem_valid_i
);
```

### lsq (Load-Store Queue)

Manages memory ordering for out-of-order execution.

```verilog
module lsq #(
    parameter LQ_SIZE = 8,
    parameter SQ_SIZE = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    
    // Allocate interface
    input  wire        alloc_valid_i,
    input  wire        alloc_is_load_i,
    input  wire [4:0]  alloc_rob_idx_i,
    output wire [2:0]  alloc_lq_idx_o,
    output wire [2:0]  alloc_sq_idx_o,
    output wire        alloc_ready_o,
    
    // Address interface
    input  wire        addr_valid_i,
    input  wire [2:0]  addr_idx_i,
    input  wire        addr_is_load_i,
    input  wire [31:0] addr_i,
    
    // Execute interface
    output wire        exec_valid_o,
    output wire        exec_is_load_o,
    output wire [31:0] exec_addr_o,
    output wire [31:0] exec_data_o,
    input  wire        exec_ready_i,
    input  wire [31:0] exec_result_i,
    
    // Commit interface
    input  wire        commit_valid_i,
    input  wire [4:0]  commit_rob_idx_i,
    
    // Flush
    input  wire        flush_i
);
```

## Branch Prediction Modules

### bpu (Branch Prediction Unit)

Top-level branch predictor.

```verilog
module bpu #(
    parameter BTB_SIZE = 256,
    parameter RAS_SIZE = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    
    // Prediction interface
    input  wire [31:0] pc_i,
    input  wire        req_i,
    output wire        pred_taken_o,
    output wire [31:0] pred_target_o,
    output wire        pred_valid_o,
    
    // Update interface
    input  wire        update_valid_i,
    input  wire [31:0] update_pc_i,
    input  wire        update_taken_i,
    input  wire [31:0] update_target_i,
    input  wire        update_is_branch_i,
    input  wire        update_is_call_i,
    input  wire        update_is_ret_i
);
```

## Signal Naming Conventions

- `_i`: Input signal
- `_o`: Output signal
- `_n`: Active-low signal
- `_r`: Registered signal
- `_w`: Wire/combinational signal
- `valid`: Data is valid
- `ready`: Ready to accept data
- `ack`: Acknowledgment
- `req`: Request
