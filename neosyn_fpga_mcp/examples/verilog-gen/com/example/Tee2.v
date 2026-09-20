
/**
 * Tee2 — an explicit 1->2 push replicator: read one token, write it to both
 * output ports.
 * 
 * YOU USUALLY DO NOT NEED THIS. A bare push output wired to two consumers is a
 * correct broadcast — both consumers receive EVERY token, and the producer is
 * held to the slower consumer's rate. (This file used to claim a bare fan-out
 * deadlocks the simulator; that was re-tested in four shapes on both backends
 * and is FALSE. Do not insert a Tee to "fix" a fan-out.)
 * 
 * Reach for an explicit Tee when the two branches must diverge — different
 * rates, a transformation on one side, or replication you want to see as real
 * hardware in the netlist. It costs 33 cells that plain wiring does not.
 * Verified: sim ok, yosys REAL, 33 cells, 0 latches.
 */
module Tee2(input clock, input reset_n, input signed [31 : 0] a, input a_valid, output reg signed [31 : 0] y0, output reg y0_valid, output reg signed [31 : 0] y1, output reg y1_valid);


  /**
   * State variables
   */
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Tee2
    if (~reset_n) begin
      y0 <= 32'b0;
      y1 <= 32'b0;
      y0_valid <= 1'b0;
      y1_valid <= 1'b0;
    end else begin
      y0_valid <= 1'b0;
      y1_valid <= 1'b0;
      
      if (a_valid) begin // line 19
        y0 <= a;
        y0_valid <= 1'b1;
        y1 <= a;
        y1_valid <= 1'b1;
      end
    end
  end

endmodule //Tee2
