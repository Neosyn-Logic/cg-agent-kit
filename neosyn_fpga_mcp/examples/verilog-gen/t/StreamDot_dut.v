/**
 * Title      : Generated from t.StreamDot_dut by Neosyn IDE
 * Project    : home
 *
 * File       : t.StreamDot_dut.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module StreamDot_dut(input clock, input reset_n, input [31 : 0] ia, input ia_valid, output reg ia_ready, input [31 : 0] ib, input ib_valid, output reg ib_ready, output reg [63 : 0] oy, input oy_ready, output reg oy_valid);


  /**
   * State variables
   */
  reg [31 : 0] cnt;
  reg [63 : 0] acc;
  reg  stall;
  reg  internal_ia_valid;
  reg [31 : 0] internal_ia;
  reg  internal_ib_valid;
  reg [31 : 0] internal_ib;
  
  // Argument for the scheduler functions' unused input. A literal would make every call
  // all-constant, and Yosys evaluates such a call as a constant function.
  /* verilator lint_off UNUSED */
  wire _sched_dummy = 1'b0;
  /* verilator lint_on UNUSED */
  
  
  
  // Scheduler of FSM_StreamDot_dut_b (line 37)
  function isSchedulable_FSM_StreamDot_dut_b(input _dummy);
    reg  cond;
  begin
    isSchedulable_FSM_StreamDot_dut_b = (((internal_ia_valid || ia_valid) && (internal_ib_valid || ib_valid)) && ! ((((internal_ia_valid || ia_valid) && (internal_ib_valid || ib_valid)) && (cnt == 32'h3))));
  end
  endfunction
  
  
  /**
   * Combinational process
   */
  always @(*) begin
    ia_ready = 1'b0;
    ib_ready = 1'b0;
    if ((((internal_ia_valid || ia_valid) && (internal_ib_valid || ib_valid)) && (cnt == 32'h3))) begin // line 37
      ia_ready = (oy_ready || ! (oy_valid));
      ib_ready = (oy_ready || ! (oy_valid));
    end else if (isSchedulable_FSM_StreamDot_dut_b(_sched_dummy)) begin // line 37
      ia_ready = (oy_ready || ! (oy_valid));
      ib_ready = (oy_ready || ! (oy_valid));
    end else begin // line 0
      ia_ready = (! (stall) && ! ((internal_ia_valid || ia_valid)));
      ib_ready = (! (stall) && ! ((internal_ib_valid || ib_valid)));
    end
  end
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of StreamDot_dut
    if (~reset_n) begin
      cnt <= 32'h0;
      acc <= 64'h0;
      stall <= 1'b0;
      internal_ia_valid <= 1'b0;
      internal_ia <= 32'b0;
      internal_ib_valid <= 1'b0;
      internal_ib <= 32'b0;
      oy <= 64'b0;
      oy_valid <= 1'b0;
    end else begin
      if (ia_valid) begin
        internal_ia_valid <= 1'b1;
        internal_ia <= ia;
      end
      
      if (ib_valid) begin
        internal_ib_valid <= 1'b1;
        internal_ib <= ib;
      end
      
      // Reset the flags of every OTHER synchronous output; the direct held output keeps its
      // valid (see below), so it must not be defaulted to 0 here.
      // Direct held-producer link (StreamLinkMarker): present the value and HOLD it until the
      // consumer takes it (ready). `oy_valid`/`oy` are registered, so they lag the FSM
      // by a cycle; advance the scheduler (loading the next value) ONLY when the current value is
      // accepted (oy_ready) or none is presented yet (!oy_valid). Otherwise every register
      // holds, so no value is dropped under consumer backpressure.
      if (oy_ready || !oy_valid) begin
        oy_valid <= 1'b0;
        if ((((internal_ia_valid || ia_valid) && (internal_ib_valid || ib_valid)) && (cnt == 32'h3))) begin : FSM_StreamDot_dut_a // line 37
          reg [64 : 0] orion;
        
          orion = (acc + ({32'b0, (internal_ia_valid ? internal_ia : ia)} * {32'b0, (internal_ib_valid ? internal_ib : ib)}));
          oy <= orion[63 : 0];
          oy_valid <= 1'b1;
          cnt <= 32'h0;
          acc <= 64'h0;
          stall <= ! (oy_ready);
          internal_ia_valid <= 1'b0;
          internal_ib_valid <= 1'b0;
        end else if (isSchedulable_FSM_StreamDot_dut_b(_sched_dummy)) begin : FSM_StreamDot_dut_b // line 37
          reg [64 : 0] lyra;
          reg [32 : 0] cygnus;
        
          lyra = (acc + ({32'b0, (internal_ia_valid ? internal_ia : ia)} * {32'b0, (internal_ib_valid ? internal_ib : ib)}));
          acc <= lyra[63 : 0];
          cygnus = (cnt + 32'h1);
          cnt <= cygnus[31 : 0];
          internal_ia_valid <= 1'b0;
          internal_ib_valid <= 1'b0;
        end else begin // line 0
          internal_ia_valid <= 1'b0;
          internal_ib_valid <= 1'b0;
        end
      end
    end
  end

endmodule //StreamDot_dut
