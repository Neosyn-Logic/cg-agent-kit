
/**
 * Debouncer + edge detector — the canonical input-conditioning block, and the
 * thing to put between ANY asynchronous real-world input (button, switch,
 * opto/limit sensor, off-chip level) and the rest of your design.
 * 
 * A mechanical contact does not switch cleanly: it chatters for milliseconds,
 * which at fabric speed is thousands of cycles of garbage. Feeding that straight
 * into an FSM produces dozens of spurious events. This block only accepts a new
 * level once it has held for N consecutive cycles, and emits a ONE-CYCLE `rise`
 * or `fall` pulse at the moment it does — so downstream logic gets a clean level
 * plus a clean event, and never sees the chatter.
 * 
 * The state is a counter of how long the input has DISAGREED with the currently
 * accepted level: any disagreement counts up, any agreement resets it to zero,
 * and reaching N flips the level. A glitch shorter than N cycles therefore
 * leaves no trace at all — the test below proves that with a 3-cycle glitch
 * against N=4.
 * 
 * This also IS the edge detector: if you only need "did this signal change",
 * set N=1 and the counter degenerates to the classic one-cycle delay register
 * (`rise` = din AND NOT previous). The debounce counter is just an edge detector
 * with hysteresis.
 * 
 * TO ADAPT:
 * * real debounce time — N is in CLOCK CYCLES; a 10 ms filter at 100 MHz is
 * N = 1_000_000, so widen `cnt` to match (u20 here). Widen the type and the
 * const together; the compare stays the same.
 * * a `tick` enable — for very long filters, count milliseconds instead of
 * cycles: gate the loop body behind a slow tick and keep N small.
 * * one-shot only — drop `stable` and keep `rise` as a clean "button pressed"
 * event.
 * 
 * Timing (as in every Cg FSM): a port reflects the register at the START of the
 * cycle, so publish the CURRENT level and pulses BEFORE updating them — a
 * just-computed pulse would read back one cycle late. The registers are
 * inline-initialized (no setup(), which would add a reset state that offsets
 * the whole stream).
 */
module Debounce(input clock, input reset_n, input  din, input din_valid, output reg  stable, output reg stable_valid, output reg  rise, output reg rise_valid, output reg  fall, output reg fall_valid);


  /**
   * State variables
   */
  localparam signed [31 : 0] N = 32'sh4;
  reg  cur;
  reg [3 : 0] cnt;
  reg  r;
  reg  f;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Debounce
    if (~reset_n) begin
      cur <= 1'b0;
      cnt <= 4'h0;
      r <= 1'b0;
      f <= 1'b0;
      stable <= 1'b0;
      rise <= 1'b0;
      fall <= 1'b0;
      stable_valid <= 1'b0;
      rise_valid <= 1'b0;
      fall_valid <= 1'b0;
    end else begin
      stable_valid <= 1'b0;
      rise_valid <= 1'b0;
      fall_valid <= 1'b0;
      
      if (din_valid) begin : FSM_Debounce_a // line 61
        reg  cur_0_3;
        reg [3 : 0] cnt_0_3;
        reg  r_0_4;
        reg  f_0_4;
        reg  r_0_5;
        reg  f_0_5;
        reg  cur_0_4;
        reg [3 : 0] cnt_0_5;
        reg  r_0_6;
        reg  f_0_6;
        reg [4 : 0] orion;
      
        // Moore outputs for the CURRENT state — published BEFORE the transition.
        stable <= cur;
        // Moore outputs for the CURRENT state — published BEFORE the transition.
        stable_valid <= 1'b1;
        rise <= r;
        rise_valid <= 1'b1;
        fall <= f;
        fall_valid <= 1'b1;
        if ((din != cur)) begin
          if (($signed({29'b0, cnt}) == ($signed({{1{N[31]}}, N}) - 33'sh1))) begin
            if (din) begin
              r_0_4 = 1'b1;
              f_0_4 = 1'b0;
            end else begin
              r_0_4 = 1'b0;
              f_0_4 = 1'b1;
            end
            cur_0_3 = din;
            cnt_0_3 = 4'h0;
            r_0_5 = r_0_4;
            f_0_5 = f_0_4;
          end else begin
            cur_0_3 = cur;
            orion = (cnt + 4'h1);
            cnt_0_3 = orion[3 : 0];
            r_0_5 = 1'b0;
            f_0_5 = 1'b0;
          end
          cur_0_4 = cur_0_3;
          cnt_0_5 = cnt_0_3;
          r_0_6 = r_0_5;
          f_0_6 = f_0_5;
        end else begin
          cur_0_4 = cur;
          cnt_0_5 = 4'h0;
          r_0_6 = 1'b0;
          f_0_6 = 1'b0;
        end
        cur <= cur_0_4;
        r <= r_0_6;
        f <= f_0_6;
        cnt <= cnt_0_5;
      end
    end
  end

endmodule //Debounce
