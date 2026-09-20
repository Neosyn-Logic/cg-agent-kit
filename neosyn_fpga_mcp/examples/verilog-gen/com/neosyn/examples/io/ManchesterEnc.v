
/**
 * Manchester line coding — encoder AND decoder, plus a network that wires them
 * back to back and proves the ROUND TRIP. The code behind 10BASE-T Ethernet,
 * RFID/NFC, IR remotes, DALI lighting, and most "one wire, no clock" links.
 * 
 * THE PROBLEM IT SOLVES. Send raw NRZ bits down a wire and two things break.
 * (1) A long run of identical bits has NO transitions, so the receiver's clock
 * recovery has nothing to lock to and drifts until it samples in the wrong bit.
 * (2) The average voltage depends on the data, so the link cannot be
 * AC-coupled — no transformer, no capacitor, no isolation. Manchester fixes both
 * by construction: it sends a TRANSITION in the middle of every bit.
 * 
 * bit 1  ->  line low  then high   (a RISING mid-bit edge)
 * bit 0  ->  line high then low    (a FALLING mid-bit edge)
 * 
 * (That is the IEEE 802.3 convention. G.E. Thomas / "Manchester II" uses the
 * opposite polarity. They are trivially interconvertible and endlessly confused
 * — always say which one you mean. Invert `line` here for the other.)
 * So there is at least one edge per bit whatever the data, and every bit spends
 * exactly half its time high: DC balance is exact, guaranteed, data-independent.
 * The price is BANDWIDTH — two line transitions per data bit, i.e. half the
 * payload rate of NRZ for the same symbol rate. That is why gigabit links use
 * 8b/10b or 64b/66b scramblers instead (see Lfsr): those buy most of the same
 * properties for a few percent of overhead rather than 100%.
 * 
 * THE THIRD, UNDER-APPRECIATED PROPERTY: the code is SELF-CHECKING. "High for a
 * whole bit-time" and "low for a whole bit-time" are not legal symbols, so a
 * receiver that sees no mid-bit transition KNOWS something is wrong. That is
 * what `viol` reports here, and it is not an error path bolted on — 10BASE-T
 * uses exactly this deliberately, transmitting an illegal symbol as the
 * end-of-frame delimiter.
 * 
 * TIME BASE. Both blocks run at TWO CLOCKS PER BIT ("half-bit time"), with a
 * single `p` phase register: p=0 is the first half, p=1 the second. The encoder
 * therefore expects `din` to be HELD for both cycles of its bit — which is what
 * a real source does — and latches it on p=0. For a real line rate, gate both
 * blocks behind a Pwm `tick` (its one-cycle wrap pulse) at twice the bit rate,
 * and the FSMs below do not change at all.
 * 
 * WHAT IS DELIBERATELY LEFT OUT: phase acquisition. These two start in phase
 * because they start together. A real receiver does not know where the bit
 * boundaries are, and must find them — by oversampling the line 4x-16x and
 * locking onto the transitions, or by using a PREAMBLE (Ethernet's alternating
 * 1010... is there precisely so the receiver can lock its half-bit clock before
 * the frame starts). Building that is a separate job; get this pair right first,
 * then wrap the decoder in an oversampling front end (UartRx shows the
 * start-bit-detect flavour of the same problem).
 * 
 * TO ADAPT:
 * * Manchester II / G.E. Thomas polarity — invert `line` in the encoder and
 * the recovered bit in the decoder.
 * * DIFFERENTIAL Manchester (used by token ring, and immune to a swapped pair)
 * — encode by presence/absence of a transition at the START of the bit
 * instead of by the direction of the mid-bit one.
 * * a real bit rate — feed both from one Pwm `tick` at 2x the bit rate.
 * * BIPHASE MARK / FM0 (S/PDIF, AES3) — same family, same skeleton, different
 * transition rules.
 * * framing — put a preamble generator in front of the encoder and a
 * preamble detector (a shift register + compare, see Seq1011) in front of
 * the decoder.
 * 
 * Timing (as in every Cg FSM): publish the CURRENT outputs before advancing the
 * phase. All state is inline-initialized — no setup(), which would add a reset
 * state and offset the whole stream by a cycle.
 * ---------------------------------------------------------------- encoder
 * One data bit in per BIT-TIME (held over both cycles), one line half-bit out
 * per cycle.
 */
module ManchesterEnc(input clock, input reset_n, input  din, input din_valid, output reg  line, output reg line_valid, output reg  half, output reg half_valid);


  /**
   * State variables
   */
  reg  p;
  reg  b;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of ManchesterEnc
    if (~reset_n) begin
      p <= 1'b0;
      b <= 1'b0;
      line <= 1'b0;
      half <= 1'b0;
      line_valid <= 1'b0;
      half_valid <= 1'b0;
    end else begin
      line_valid <= 1'b0;
      half_valid <= 1'b0;
      
      if (din_valid) begin : FSM_ManchesterEnc_a // line 92
        reg  local_b_3;
        reg  lv_3;
      
        if (! (p)) begin
          local_b_3 = din;
          lv_3 = ! (din);
        end else begin
          local_b_3 = b;
          lv_3 = b;
        end
        line <= lv_3;
        line_valid <= 1'b1;
        half <= p;
        half_valid <= 1'b1;
        p <= ! (p);
        b <= local_b_3;
      end
    end
  end

endmodule //ManchesterEnc
