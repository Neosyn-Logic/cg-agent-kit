
/**
 * Biquad — a second-order IIR filter section, Direct Form I. The universal
 * building block of fixed-point DSP: low/high/band-pass, notch, shelf, peaking
 * EQ, DC blocker and PLL loop filter are all THIS block with different
 * coefficients. Higher orders are made by cascading biquads, not by writing a
 * higher-order difference equation (an order-8 IIR computed directly is
 * numerically hopeless in fixed point; four cascaded biquads is routine).
 * 
 * y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
 * 
 * Five multiplies, four adds, four registers. Compare with Fir, which has no
 * feedback: an IIR gets a far sharper response for the same number of
 * multipliers, and pays for it with stability and precision worries that an FIR
 * simply does not have.
 * 
 * ---- Q FORMAT (state it, or you will lose a day) ----
 * * COEFFICIENTS are Q2.14 signed: stored value = round(coefficient * 2^14),
 * representable range [-2.0, +1.99994]. a1 here is -0.942809 -> -15447.
 * Q2.14 is chosen because a1 of a stable biquad lies in (-2, 2) — it is the
 * tightest format that always fits. A design with |a1| very near 2 (a
 * high-Q resonator) wants Q3.13 and a wider coefficient type.
 * * SAMPLES x and y are plain integers here (Q16.0). Nothing in the block
 * depends on that: the filter is linear, so x may be any Qm.n you like and y
 * comes out in the same format. Only the COEFFICIENT scaling is removed, by
 * the `>> QS` after the accumulate.
 * * The ACCUMULATOR is i32 and must stay unsaturated: worst case is
 * max|x| * (|b0|+|b1|+|b2|) + max|y| * (|a1|+|a2|), which for these
 * coefficients and full-scale i16 samples is about 8e8 — comfortably inside
 * i32. Change the coefficients or widen the samples and redo that sum.
 * 
 * ---- THE THREE THINGS THAT GO WRONG ----
 * 1. TRUNCATION IS NOT ROUNDING. `>> 14` floors, so every sample carries up to
 * 1 LSB of negative bias, and the feedback path recirculates it. Here that
 * shows up as a settled step response of 997 rather than 1000. For a real
 * audio path add a rounding constant before the shift:
 * `(acc + (1 << (QS-1))) >> QS`. The test below deliberately pins the
 * TRUNCATING behaviour, because that is what the code does — matching the
 * hardware is the point, not matching the ideal filter.
 * 2. THE FEEDBACK MUST USE THE TRUNCATED OUTPUT. `y1`/`y2` store `yn` AFTER
 * the shift, not the wide accumulator. Storing the wide value gives a
 * filter that simulates beautifully and is not the one you built. (Keeping
 * extra fractional bits in the feedback IS a legitimate design — it is
 * called an error-feedback / double-precision accumulator structure — but
 * then it is a different block and the Q format of y1/y2 must be documented
 * separately.)
 * 3. DIRECT FORM I VS II. DF-I (this one) has four registers but keeps the
 * full-precision sum in one accumulator, and its state registers hold real
 * signal values, so overflow is easy to reason about. DF-II uses two
 * registers instead of four but stores an INTERNAL state whose dynamic
 * range can be much larger than the signal's — the classic fixed-point trap.
 * In hardware the two extra registers are free; use DF-I. (DF-II TRANSPOSED
 * is the good compromise and the one to reach for if you need the shorter
 * critical path: it also has two registers but the same overflow behaviour
 * as DF-I.)
 * 
 * The coefficients below are an RBJ-cookbook 2nd-order Butterworth low-pass at
 * fc = fs/8, Q = 0.7071, quantized to Q14. The test is its STEP RESPONSE, which
 * is the right thing to check: it exercises b and a paths together, shows the
 * overshoot (peak 1054 for a step of 1000 — a Q of 0.707 overshoots by ~5%), the
 * settle, the decay back to zero, and a negative step for the sign path. Every
 * number was produced by an integer Python model of exactly this arithmetic and
 * then cross-checked against a float reference (max deviation 2.3 LSB, all of it
 * truncation bias).
 * 
 * TO ADAPT:
 * * a different response — recompute b0,b1,b2,a1,a2 (RBJ cookbook / scipy
 * `butter`, `iirnotch`, ...), multiply by 2^14, round to int. Nothing else
 * changes. A DC blocker is b = [1,-1,0], a = [1,-0.995,0].
 * * higher order — instantiate this block once per section and chain them
 * (`new Biquad({B0: ..., ...})`, see ScaleGen for the const-parameter shape).
 * Cascade in order of increasing Q to keep the intermediate levels sane.
 * * SATURATION instead of wrap on the output — clamp `acc >> QS` to
 * [-32768, 32767] before the write (see Clamp). An IIR that wraps on
 * overflow can enter a large-amplitude LIMIT CYCLE and never come out; one
 * that saturates just distorts. Always saturate a feedback path.
 * * a slower/cheaper section — the five multiplies here are combinational and
 * concurrent. To reuse one multiplier across five cycles, drive it from an
 * FSM (see SeqDiv for the shape) or use `std.math.Multiply` for a registered
 * product.
 * * MORE FRACTIONAL BITS — raise QS and widen the coefficients and the
 * accumulator together. QS is what sets how close the realised response is
 * to the design; 14 bits is fine for control, 24+ for audio.
 */
module Biquad(input clock, input reset_n, input signed [15 : 0] x, input x_valid, output reg signed [15 : 0] y, output reg y_valid);


  /**
   * State variables
   */
  localparam signed [31 : 0] QS = 32'she;
  localparam signed [15 : 0] B0 = 16'sh640;
  localparam signed [15 : 0] B1 = 16'shc7f;
  localparam signed [15 : 0] B2 = 16'sh640;
  localparam signed [15 : 0] A1 = 16'shc3a9;
  localparam signed [15 : 0] A2 = 16'sh1555;
  reg signed [15 : 0] x1;
  reg signed [15 : 0] x2;
  reg signed [15 : 0] y1;
  reg signed [15 : 0] y2;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Biquad
    if (~reset_n) begin
      x1 <= 16'sh0;
      x2 <= 16'sh0;
      y1 <= 16'sh0;
      y2 <= 16'sh0;
      y <= 16'b0;
      y_valid <= 1'b0;
    end else begin
      y_valid <= 1'b0;
      
      if (x_valid) begin : FSM_Biquad_a // line 113
        reg signed [31 : 0] acc_1;
        reg signed [35 : 0] orion;
        reg signed [31 : 0] lyra;
        reg signed [31 : 0] cygnus;
      
        orion = ((((($signed({{16{B0[15]}}, B0}) * $signed({{16{x[15]}}, x})) + ($signed({{16{B1[15]}}, B1}) * $signed({{16{x1[15]}}, x1}))) + ($signed({{16{B2[15]}}, B2}) * $signed({{16{x2[15]}}, x2}))) - ($signed({{16{A1[15]}}, A1}) * $signed({{16{y1[15]}}, y1}))) - ($signed({{16{A2[15]}}, A2}) * $signed({{16{y2[15]}}, y2})));
        acc_1 = orion[31 : 0];
        lyra = (acc_1 >>> 32'she);
        // arithmetic (sign-preserving) shift; FLOORS
        y <= lyra[15 : 0];
        // arithmetic (sign-preserving) shift; FLOORS
        y_valid <= 1'b1;
        x1 <= x;
        x2 <= x1;
        cygnus = (acc_1 >>> 32'she);
        y1 <= cygnus[15 : 0];
        y2 <= y1;
      end
    end
  end

endmodule //Biquad
