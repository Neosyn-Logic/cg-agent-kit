
/**
 * Sliding-window moving average over the last N samples — the cheapest useful
 * low-pass filter, and the standard way to smooth an ADC reading, a sensor, a
 * packet-rate estimate or an error signal before a control loop sees it.
 * 
 * THE TRICK THAT MAKES IT CHEAP — a RUNNING SUM. The definition of the average
 * is "add up the last N samples and divide", which sounds like N adders and N
 * registers of arithmetic every cycle. It is not: the window only changes by one
 * sample per cycle, so
 * acc = acc - (the sample leaving the window) + (the new sample)
 * is ONE add and ONE subtract, no matter how large N is. The window memory is
 * still N deep (you have to know which sample is leaving), but it is a plain
 * circular buffer with a wrapping write pointer — an array indexed by a runtime
 * value, exactly as in RegisterFile. Cost is O(1) arithmetic + O(N) storage.
 * This block is Accumulator with a subtraction added; that is the whole delta.
 * 
 * READ `win[wp]` BEFORE WRITING IT. `wp` points at the OLDEST sample, which is
 * also the slot the newest one goes into. Do the read first (line order matters
 * here) or you subtract the sample you just wrote and the sum drifts forever.
 * 
 * `full` IS NOT DECORATION. The buffer starts zero-filled, so for the first N-1
 * cycles the average is being diluted by zeros that were never real samples —
 * the output ramps up from 1, 3, 7, 12 while the input is already 10, 20, 30, 40.
 * Any consumer must ignore the output until `full` goes high (same data/valid
 * discipline as UartRx's byte). The alternative, if you cannot wait N cycles, is
 * to preload every slot with the first sample.
 * 
 * DIVIDING BY N COSTS NOTHING HERE, and does not need to be a power of two.
 * N = 8 folds to a shift, but the compiler also compiles `acc / 10` and
 * `acc / 3` inline as a reciprocal multiply — one multiplier, single cycle, no
 * divider (see the notes in RECIPES.md). So pick the window your signal wants,
 * not the one that is a power of two. Only a RUNTIME divisor needs
 * `std.math.Divide`.
 * 
 * THE WIDTH RULE: `acc` must hold N * max(x), or it wraps and the filter goes
 * mad. u8 samples with N = 8 needs 255*8 = 2040, so u16. Widen `acc` and `sum`
 * together with N.
 * 
 * TO ADAPT:
 * * a different window — change N, the array size and the width of `wp`
 * (`u3` addresses 8 slots, `u4` addresses 16). Keep `acc` wide enough.
 * * SIGNED samples — make x/win/acc signed; nothing else changes.
 * * a BOXCAR FIR — this IS an N-tap FIR with all coefficients 1/N. For shaped
 * coefficients use Fir instead; a moving average has a poor stopband
 * (sinc-shaped) and is chosen for its price, not its response.
 * * an EXPONENTIAL moving average (IIR) when you do not want the N-deep memory
 * at all — `acc = acc - (acc >> k) + x`, one register, no buffer, no `full`
 * warm-up. See Accumulator's "integrator with a leak".
 * * a moving SUM / a windowed max — same skeleton; drop the divide, or replace
 * the accumulator with a comparison tree.
 * * a big window (N = 1024) — swap the array for `std.mem.SinglePortRAM` so it
 * maps to a block RAM instead of registers.
 * 
 * Timing: `sum`/`avg` are published AFTER the update, so they include the sample
 * read this cycle (the Accumulator convention — swap the lines for a registered,
 * one-cycle-late output). All state is inline-initialized (no setup(), which
 * would add a reset state that offsets the whole stream).
 */
module MovingAverage(input clock, input reset_n, input [7 : 0] x, input x_valid, output reg [15 : 0] sum, output reg sum_valid, output reg [7 : 0] avg, output reg avg_valid, output reg  full, output reg full_valid);


  /**
   * State variables
   */
  localparam signed [31 : 0] N = 32'sh8;
  reg [7 : 0] win [0 : 7];
  initial begin : win_zero_init
    integer init_i;
    for (init_i = 0; init_i < 8; init_i = init_i + 1) begin
      win[init_i] = 0;
    end
  end
  reg [2 : 0] wp;
  reg [15 : 0] acc;
  reg [3 : 0] warm;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of MovingAverage
    if (~reset_n) begin
      wp <= 3'h0;
      acc <= 16'h0;
      warm <= 4'h0;
      sum <= 16'b0;
      avg <= 8'b0;
      full <= 1'b0;
      sum_valid <= 1'b0;
      avg_valid <= 1'b0;
      full_valid <= 1'b0;
    end else begin
      sum_valid <= 1'b0;
      avg_valid <= 1'b0;
      full_valid <= 1'b0;
      
      if (x_valid) begin : FSM_MovingAverage_a // line 88
        reg [7 : 0] local_win [0 : 7];
        reg [7 : 0] win_0_1;
        reg [3 : 0] warm_0_3;
        reg [4 : 0] orion;
        reg [17 : 0] lyra;
        reg [17 : 0] cygnus;
        reg [15 : 0] draco;
        reg [3 : 0] aquila;
        reg [17 : 0] pegasus;
        reg [31 : 0] loop_idx;
      
        for (loop_idx = 0; loop_idx < 8; loop_idx = loop_idx + 1) begin
          local_win[loop_idx] = win[loop_idx];
        end
        win_0_1 = local_win[$unsigned(wp)];
        // one subtract + one add, independent of N
        local_win[$unsigned(wp)] = x;
        // u3 wraps mod 8 for free
        if (($signed({28'b0, warm}) < N)) begin
          orion = (warm + 4'h1);
          warm_0_3 = orion[3 : 0];
        end else begin
          warm_0_3 = warm;
        end
        lyra = ((acc - win_0_1) + x);
        sum <= lyra[15 : 0];
        sum_valid <= 1'b1;
        cygnus = ((acc - win_0_1) + x);
        draco = (cygnus[15 : 0] >> 16'h3);
        // published AFTER the update: includes `s`
        avg <= draco[7 : 0];
        // published AFTER the update: includes `s`
        avg_valid <= 1'b1;
        // constant divisor -> shift here, reciprocal
        full <= ($signed({28'b0, warm_0_3}) == N);
        // constant divisor -> shift here, reciprocal
        full_valid <= 1'b1;
        aquila = (wp + 3'h1);
        wp <= aquila[2 : 0];
        pegasus = ((acc - win_0_1) + x);
        acc <= pegasus[15 : 0];
        for (loop_idx = 0; loop_idx < 8; loop_idx = loop_idx + 1) begin
          win[loop_idx] <= local_win[loop_idx];
        end
        warm <= warm_0_3;
      end
    end
  end

endmodule //MovingAverage
