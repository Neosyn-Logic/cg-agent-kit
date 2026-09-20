
/**
 * Edge detector — turn a LEVEL into an EVENT. One flip-flop and three gates, and
 * the most-instantiated block in any real design: every "start" pulse, every
 * "button pressed", every "this signal just changed" comes from here.
 * 
 * THE WHOLE BLOCK IS ONE DELAY REGISTER. Keep last cycle's value in `prev`, and
 * compare it with this cycle's:
 * rise = din & ~prev      fall = ~din & prev      both = din ^ prev
 * Every strobe is exactly ONE cycle wide, whatever the input does afterwards.
 * That is the point: an FSM waiting on a level will re-trigger for as long as
 * the level is held; an FSM waiting on `rise` triggers once.
 * 
 * The strobes are MEALY — `rise` goes high in the SAME cycle `din` goes high, so
 * there is no added latency. `dly` (the register itself) is exposed because it is
 * occasionally what you actually want: the input aligned one cycle later, to
 * match a datapath that has a register in it.
 * 
 * TWO THINGS TO GET RIGHT BEFORE YOU USE THIS ON A REAL PIN:
 * 1. SYNCHRONISE FIRST. An input that comes from off-chip or another clock
 * domain must go through a 2-flop synchroniser (`std.lib.SynchronizerFF`,
 * or `SynchronizerMux` for a wide value) BEFORE this block, or metastability
 * turns into a phantom edge. This block assumes `din` is already in your
 * clock domain.
 * 2. DEBOUNCE IF IT BOUNCES. A mechanical contact produces hundreds of real
 * edges per press, and this block faithfully reports every one of them. Put
 * `Debounce` in front (it is this block plus hysteresis — a counter that
 * makes a change wait N cycles before it counts) and take ITS rise/fall.
 * Rule of thumb: clean logic signal -> EdgeDetect; anything touched by a
 * human or a wire -> Debounce.
 * 
 * TO ADAPT:
 * * a WIDE value — `both` becomes `din != prev` on a u8/u32; that is a "value
 * changed" strobe, which is how you turn a memory-mapped register into a
 * write event.
 * * a TOGGLE-to-PULSE converter (the classic CDC handshake) — synchronise the
 * far-domain toggle, then take `both` here: one pulse per far-side event.
 * * a STICKY flag instead of a pulse — latch `rise` into a bool and clear it
 * when the consumer acknowledges (an interrupt-status bit).
 * * a start-of-packet strobe — feed a framing/valid signal in and take `rise`.
 * 
 * Timing: `prev` is inline-initialized to false (no setup(), which would add a
 * reset state and offset the whole stream), so a `din` that is already high in
 * cycle 0 produces a rise in cycle 0. If that is wrong for you, initialize `prev`
 * to the idle level of your signal instead.
 */
module EdgeDetect(input clock, input reset_n, input  din, input din_valid, output reg  rise, output reg rise_valid, output reg  fall, output reg fall_valid, output reg  both, output reg both_valid, output reg  dly, output reg dly_valid);


  /**
   * State variables
   */
  reg  prev;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of EdgeDetect
    if (~reset_n) begin
      prev <= 1'b0;
      rise <= 1'b0;
      fall <= 1'b0;
      both <= 1'b0;
      dly <= 1'b0;
      rise_valid <= 1'b0;
      fall_valid <= 1'b0;
      both_valid <= 1'b0;
      dly_valid <= 1'b0;
    end else begin
      rise_valid <= 1'b0;
      fall_valid <= 1'b0;
      both_valid <= 1'b0;
      dly_valid <= 1'b0;
      
      if (din_valid) begin // line 75
        rise <= (din && ! (prev));
        rise_valid <= 1'b1;
        // Mealy: same cycle as the transition
        fall <= (! (din) && prev);
        // Mealy: same cycle as the transition
        fall_valid <= 1'b1;
        both <= (din != prev);
        both_valid <= 1'b1;
        // `bool != bool` is the idiomatic XOR
        dly <= prev;
        // `bool != bool` is the idiomatic XOR
        dly_valid <= 1'b1;
        prev <= din;
      end
    end
  end

endmodule //EdgeDetect
