
/**
 * Verified Cg base — an indexed REGISTER FILE: an array addressed by a runtime
 * value, with one entry hardwired to zero (the RISC-V x0 convention) and
 * write-first read semantics.
 * 
 * Patterns worth copying:
 * - `registers[addr]` with a RUNTIME index works for both read and write.
 * - "hardwired zero": guard the write (`if (wa != 0)`) and the read
 * (`a == 0 ? 0 : registers[a]`) so entry 0 is always 0 without a real cell.
 * - write-first: do the write before the reads in loop(), so a read of a
 * register written this cycle sees the new value.
 * - `we` is a PUSH port — available() == "a write is requested this cycle";
 * a `null` in the test vector means no write that cycle.
 */
module RegisterFile(input clock, input reset_n, input [4 : 0] we, input we_valid, input [31 : 0] wdata, input [4 : 0] rs1, input [4 : 0] rs2, output reg [31 : 0] rdata1, output reg [31 : 0] rdata2);


  /**
   * State variables
   */
  reg [31 : 0] registers [0 : 31];
  initial begin : registers_zero_init
    integer init_i;
    for (init_i = 0; init_i < 32; init_i = init_i + 1) begin
      registers[init_i] = 0;
    end
  end
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of RegisterFile
    if (~reset_n) begin
      rdata1 <= 32'b0;
      rdata2 <= 32'b0;
    end else begin
      
      if ((we_valid && (we_valid && (we != 5'h0)))) begin : FSM_RegisterFile_a // line 41
        reg [31 : 0] local_registers [0 : 31];
        reg [31 : 0] tmp_if_2;
        reg [31 : 0] registers_0_1;
        reg [31 : 0] tmp_if_0_2;
        reg [31 : 0] registers_1_1;
        reg [31 : 0] loop_idx;
      
        for (loop_idx = 0; loop_idx < 32; loop_idx = loop_idx + 1) begin
          local_registers[loop_idx] = registers[loop_idx];
        end
        // entry 0 is hardwired zero — never written
        local_registers[$unsigned(we)] = wdata;
        if ((rs1 == 5'h0)) begin
          tmp_if_2 = 32'h0;
        end else begin
          registers_0_1 = local_registers[$unsigned(rs1)];
          tmp_if_2 = registers_0_1;
        end
        rdata1 <= tmp_if_2;
        if ((rs2 == 5'h0)) begin
          tmp_if_0_2 = 32'h0;
        end else begin
          registers_1_1 = local_registers[$unsigned(rs2)];
          tmp_if_0_2 = registers_1_1;
        end
        rdata2 <= tmp_if_0_2;
        for (loop_idx = 0; loop_idx < 32; loop_idx = loop_idx + 1) begin
          registers[loop_idx] <= local_registers[loop_idx];
        end
      end else if ((we_valid && (we_valid && ! ((we != 5'h0))))) begin : FSM_RegisterFile_b // line 41
        reg [31 : 0] tmp_if_2;
        reg [31 : 0] registers_0_1;
        reg [31 : 0] tmp_if_0_2;
        reg [31 : 0] registers_1_1;
      
        if ((rs1 == 5'h0)) begin
          tmp_if_2 = 32'h0;
        end else begin
          registers_0_1 = registers[$unsigned(rs1)];
          tmp_if_2 = registers_0_1;
        end
        rdata1 <= tmp_if_2;
        if ((rs2 == 5'h0)) begin
          tmp_if_0_2 = 32'h0;
        end else begin
          registers_1_1 = registers[$unsigned(rs2)];
          tmp_if_0_2 = registers_1_1;
        end
        rdata2 <= tmp_if_0_2;
      end else if (! (we_valid)) begin : FSM_RegisterFile_c // line 46
        reg [31 : 0] tmp_if_2;
        reg [31 : 0] registers_0_1;
        reg [31 : 0] tmp_if_0_2;
        reg [31 : 0] registers_1_1;
      
        if ((rs1 == 5'h0)) begin
          tmp_if_2 = 32'h0;
        end else begin
          registers_0_1 = registers[$unsigned(rs1)];
          tmp_if_2 = registers_0_1;
        end
        rdata1 <= tmp_if_2;
        if ((rs2 == 5'h0)) begin
          tmp_if_0_2 = 32'h0;
        end else begin
          registers_1_1 = registers[$unsigned(rs2)];
          tmp_if_0_2 = registers_1_1;
        end
        rdata2 <= tmp_if_0_2;
      end
    end
  end

endmodule //RegisterFile
