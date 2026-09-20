
/**
 * PWM + rate divider — counter and compare, the two things you build out of a
 * free-running counter.
 * 
 * `pwm` is high for the first `duty` cycles of every PERIOD-cycle window (duty
 * cycle = duty/PERIOD), which drives LED brightness, motor speed, a DAC, a
 * servo. `tick` is the wrap pulse: exactly one cycle high at the start of each
 * period.
 * 
 * THAT `tick` IS THE RATE DIVIDER, and it is the missing piece the UartTx and
 * UartRx examples point at when they say "gate the loop body behind a baud-tick
 * enable". Fabric runs at 100 MHz, a 115200-baud UART needs a bit every 868
 * cycles: instantiate this with PERIOD = 868, wire `tick` into the UART's enable
 * and the UART transmits at the right line rate without changing its FSM at all.
 * The same pulse is how you drive a 1 kHz refresh, a 1 ms debounce tick, or any
 * slow process from a fast clock.
 * 
 * GLITCH-FREE UPDATE — the part people get wrong: `duty` is LATCHED into `dreg`
 * at the period boundary, not used directly. Comparing against the live input
 * means a mid-period change can cut a pulse short or stretch it, emitting a
 * runt cycle that a motor or LED sees as a flicker. Latching at the wrap makes
 * every period well-formed no matter when the input moves. The test below
 * changes `duty` mid-period on purpose to prove the period in flight is
 * undisturbed.
 * 
 * TO ADAPT:
 * * a real rate — PERIOD is in CLOCK CYCLES, so widen `cnt` to hold it
 * (PERIOD = 868 needs u10; PERIOD = 100_000 for 1 kHz at 100 MHz needs u17).
 * Widen the type and the const together; the compare is unchanged.
 * * a pure clock divider — drop `duty`/`pwm`/`dreg` and keep `tick`.
 * * phase-correct / centre-aligned PWM — count up then down instead of
 * wrapping, so pulses stay centred in the period.
 * * several channels — instantiate one per output with `new Pwm({PERIOD: n})`
 * (see ScaleGen for the const-parameter pattern), or keep one counter and
 * compare it against several duty registers.
 * 
 * Timing (as in every Cg FSM): a port reflects the register at the START of the
 * cycle, so publish the CURRENT `pwm`/`tick` BEFORE advancing the counter. Both
 * outputs are Moore here — they depend only on registers, which is exactly why
 * latching `duty` matters. The registers are inline-initialized (no setup(),
 * which would add a reset state that offsets the whole stream).
 */
module Pwm(input clock, input reset_n, input [3 : 0] duty, input duty_valid, output reg  pwm, output reg pwm_valid, output reg  tick, output reg tick_valid);


  /**
   * State variables
   */
  localparam signed [31 : 0] PERIOD = 32'sh8;
  reg [3 : 0] cnt;
  reg [3 : 0] dreg;
  reg  t;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Pwm
    if (~reset_n) begin
      cnt <= 4'h0;
      dreg <= 4'h0;
      t <= 1'b0;
      pwm <= 1'b0;
      tick <= 1'b0;
      pwm_valid <= 1'b0;
      tick_valid <= 1'b0;
    end else begin
      pwm_valid <= 1'b0;
      tick_valid <= 1'b0;
      
      if (duty_valid) begin : FSM_Pwm_a // line 65
        reg [3 : 0] cnt_0_3;
        reg  t_0_3;
        reg [3 : 0] dreg_0_3;
        reg [4 : 0] orion;
      
        // Moore outputs for the CURRENT state — published BEFORE the transition.
        pwm <= (cnt < dreg);
        // Moore outputs for the CURRENT state — published BEFORE the transition.
        pwm_valid <= 1'b1;
        tick <= t;
        tick_valid <= 1'b1;
        if (($signed({29'b0, cnt}) == ($signed({{1{PERIOD[31]}}, PERIOD}) - 33'sh1))) begin
          cnt_0_3 = 4'h0;
          t_0_3 = 1'b1;
          dreg_0_3 = duty;
        end else begin
          orion = (cnt + 4'h1);
          cnt_0_3 = orion[3 : 0];
          t_0_3 = 1'b0;
          dreg_0_3 = dreg;
        end
        cnt <= cnt_0_3;
        dreg <= dreg_0_3;
        t <= t_0_3;
      end
    end
  end

endmodule //Pwm
