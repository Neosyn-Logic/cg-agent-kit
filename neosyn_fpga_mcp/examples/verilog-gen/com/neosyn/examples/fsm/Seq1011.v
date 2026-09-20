
/**
 * Overlapping "1011" sequence detector — the canonical control FSM.
 * One serial bit in per cycle; `found` pulses on the cycle the pattern
 * completes. Overlapping: the trailing 1 of a match can start the next one.
 * 
 * The machine's state is an ENUM (named states, self-documenting). Here it is
 * exposed as a plain integer code `scode` (u2) — the simplest shape for a
 * debug/observation signal. (An enum is ALSO a valid port type, so `out St scode`
 * would work too and carry the enum directly; a shared enum in a `bundle` lets
 * both sides of a cross-actor link name it.) This is the idiomatic Cg
 * state-machine shape: an enum state register + explicit next-state logic in
 * loop(), driving outputs.
 * 
 * Timing (important for any Moore/Mealy FSM in Cg): a port reflects the register
 * as it was at the START of the cycle, so publish the CURRENT state and drive
 * each output BEFORE transitioning — do not write a just-computed *next* state
 * (it would read back one cycle late). `found` is a Mealy output (function of the
 * current state AND the incoming bit); `scode` is a Moore output (the current
 * state alone).
 */
module Seq1011(input clock, input reset_n, input  din, input din_valid, output reg  found, output reg found_valid, output reg [1 : 0] scode, output reg scode_valid);


  /**
   * State variables
   */
  reg [1 : 0] st;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Seq1011
    if (~reset_n) begin
      st <= 2'b0;
      found <= 1'b0;
      scode <= 2'b0;
      found_valid <= 1'b0;
      scode_valid <= 1'b0;
    end else begin
      found_valid <= 1'b0;
      scode_valid <= 1'b0;
      
      if (din_valid) begin : FSM_Seq1011_a // line 41
        reg [1 : 0] st_0_3;
        reg [1 : 0] st_0_5;
        reg [1 : 0] st_0_7;
        reg [1 : 0] st_0_9;
        reg [1 : 0] st_0_11;
        reg [1 : 0] st_0_13;
        reg [1 : 0] st_0_15;
      
        // Mealy: "101" + 1  ==  "1011" completes
        found <= ((st == 2'h3) && din);
        // Mealy: "101" + 1  ==  "1011" completes
        found_valid <= 1'b1;
        scode <= st;
        scode_valid <= 1'b1;
        // --- next-state logic ---
        if ((st == 2'h0)) begin
          // matched nothing
          if (din) begin
            st_0_3 = 2'h1;
          end else begin
            st_0_3 = 2'h0;
          end
          st_0_5 = st_0_3;
        end else begin
          // --- next-state logic ---
          if ((st == 2'h1)) begin
            // matched "1"
            if (din) begin
              st_0_7 = 2'h1;
            end else begin
              st_0_7 = 2'h2;
            end
            st_0_9 = st_0_7;
          end else begin
            // --- next-state logic ---
            if ((st == 2'h2)) begin
              // matched "10"
              if (din) begin
                st_0_11 = 2'h3;
              end else begin
                st_0_11 = 2'h0;
              end
              st_0_13 = st_0_11;
            end else begin
              // matched "101"
              if (din) begin
                st_0_15 = 2'h1;
              end else begin
                st_0_15 = 2'h2;
              end
              st_0_13 = st_0_15;
            end
            st_0_9 = st_0_13;
          end
          st_0_5 = st_0_9;
        end
        st <= st_0_5;
      end
    end
  end

endmodule //Seq1011
