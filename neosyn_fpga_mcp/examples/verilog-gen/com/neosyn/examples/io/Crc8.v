
/**
 * Bit-serial CRC-8 — the XOR-feedback shift register, the shape behind every
 * CRC, LFSR, scrambler and pseudo-random generator.
 * 
 * One bit per clock, MSB-first: the top bit of the remainder is XORed with the
 * incoming bit to form the feedback, the remainder shifts left, and the
 * polynomial is XORed back in when that feedback is 1. Defaults are CRC-8/ATM
 * (poly 0x07 = x^8 + x^2 + x + 1, init 0x00, no reflection).
 * 
 * Ports: `init` clears the remainder to start a new message; `en` gates the
 * machine so the remainder HOLDS between bursts (drive it from a link's
 * data-valid strobe — e.g. UartRx's `valid`); `crc` is the running remainder.
 * 
 * THE PROPERTY THAT MAKES IT A CRC: feed a message, then feed the 8 CRC bits it
 * produced, and the remainder returns to 0. The test below does exactly that —
 * 0x53 gives 0xBE, and 0x53 followed by 0xBE gives 0x00. A receiver therefore
 * does not need to compare checksums: it runs every received bit (message AND
 * trailing CRC) through this block and just checks `crc == 0` at the end.
 * 
 * TO ADAPT:
 * * other polynomials — change POLY and the width of `rem`/`crc` together
 * (CRC-16-CCITT: u16, POLY 0x1021; CRC-32: u32, POLY 0x04C11DB7)
 * * init 0xFF (CRC-8/CDMA2000, CRC-16-CCITT-FALSE) — set `rem = 0xFF` in the
 * init branch AND as the inline initializer
 * * an LFSR / PRNG / scrambler — drop `din` (feed a constant 0) and the
 * feedback becomes `rem[7]` alone; the register then cycles through a
 * maximal-length sequence for a primitive polynomial
 * * byte-parallel (8 bits per clock) — unroll this body 8 times over the
 * bits of a byte; the compiler flattens it into one XOR tree per output bit
 * 
 * Timing (as in every Cg FSM): a port reflects the register at the START of the
 * cycle, so publish the CURRENT remainder BEFORE updating it — a just-computed
 * remainder would read back one cycle late. `rem` is inline-initialized (no
 * setup(), which would add a reset state that offsets the whole stream).
 */
module Crc8(input clock, input reset_n, input  din, input din_valid, input  en, input en_valid, input  init, input init_valid, output reg [7 : 0] crc, output reg crc_valid);


  /**
   * State variables
   */
  localparam [7 : 0] POLY = 8'h7;
  reg [7 : 0] rem;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Crc8
    if (~reset_n) begin
      rem <= 8'h0;
      crc <= 8'b0;
      crc_valid <= 1'b0;
    end else begin
      crc_valid <= 1'b0;
      
      if (((din_valid && en_valid) && init_valid)) begin : FSM_Crc8_a // line 55
        reg [7 : 0] rem_0_3;
        reg [7 : 0] rem_0_5;
        reg [7 : 0] rem_0_7;
        reg [8 : 0] orion;
        reg [8 : 0] lyra;
      
        crc <= rem;
        crc_valid <= 1'b1;
        // publish the CURRENT remainder, before the update
        if (init) begin
          rem_0_3 = 8'h0;
        end else begin
          // publish the CURRENT remainder, before the update
          if (en) begin
            if ((((rem & 8'h80) != 8'h0) ^ din)) begin
              orion = {rem, {(1'h1){1'b0}}};
              rem_0_5 = (orion[7 : 0] ^ POLY);
            end else begin
              lyra = {rem, {(1'h1){1'b0}}};
              rem_0_5 = lyra[7 : 0];
            end
            rem_0_7 = rem_0_5;
          end else begin
            rem_0_7 = rem;
          end
          rem_0_3 = rem_0_7;
        end
        rem <= rem_0_3;
      end
    end
  end

endmodule //Crc8
