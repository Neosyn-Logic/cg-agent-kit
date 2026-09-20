
/**
 * Priority encoder — turn a bit VECTOR into the INDEX of the first set bit, plus
 * a `valid` flag. The one piece of glue every arbiter, interrupt controller,
 * free-list allocator, normaliser and cache-way selector is built out of.
 * 
 * This is pure combinational logic: no state, no clock behaviour, one answer per
 * cycle. The whole block is the if/else-if chain below, and the ORDER of that
 * chain IS the priority. Bit 0 wins here (LSB-first, "lowest requester first"),
 * which is the convention for interrupt lines and free lists.
 * 
 * WHY THE `valid` FLAG IS NOT OPTIONAL, and the mistake to avoid: index 0 is a
 * perfectly good answer AND the natural "nothing set" default, so `idx` alone
 * cannot distinguish "requester 0 is asking" from "nobody is asking". Every
 * consumer must qualify `idx` with `valid` — the same data/valid rule as
 * UartRx's byte or SpiMaster's `rx`. Getting this wrong grants a bus to
 * requester 0 forever when the bus is idle.
 * 
 * TO ADAPT:
 * * MSB-first (highest bit wins) — reverse the chain: test req[7] first. That
 * is the "find the highest set bit" / floor(log2) form used by float
 * normalisers and by the classic priority-interrupt controller.
 * * a LEADING-ZERO COUNT — MSB-first, and output `7 - idx` (a normaliser wants
 * the shift distance, not the bit position).
 * * wider inputs — extend the chain one `else if` per bit and widen `idx`
 * (u16 -> u4, u32 -> u5). At 32+ bits the flat chain gets deep: split the
 * word into 4-bit groups, encode each group, encode the group-valid vector
 * with a second copy of this block, and concatenate the two indices. That
 * two-level tree is how every real wide encoder is built.
 * * ONE-HOT output instead of an index — see RoundRobinArbiter, which needs
 * both (an index to remember and a one-hot vector to drive the grants).
 * * ROTATING priority instead of fixed — that is exactly RoundRobinArbiter:
 * rotate the request vector, run this encoder, rotate the index back.
 * 
 * No `properties { type: "combinational" }` is needed — the compiler sees there
 * is no state and no fence, and emits a single combinational block.
 */
module PriorityEncoder(input clock, input reset_n, input [7 : 0] req, input req_valid, output reg [2 : 0] idx, output reg idx_valid, output reg  valid, output reg valid_valid);


  /**
   * State variables
   */
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of PriorityEncoder
    if (~reset_n) begin
      idx <= 3'b0;
      valid <= 1'b0;
      idx_valid <= 1'b0;
      valid_valid <= 1'b0;
    end else begin
      idx_valid <= 1'b0;
      valid_valid <= 1'b0;
      
      if (req_valid) begin : FSM_PriorityEncoder_a // line 56
        reg [2 : 0] i_3;
        reg [2 : 0] i_5;
        reg [2 : 0] i_7;
        reg [2 : 0] i_9;
        reg [2 : 0] i_11;
        reg [2 : 0] i_13;
        reg [2 : 0] i_15;
        reg [2 : 0] i_17;
        reg  v_3;
        reg  v_4;
        reg  v_5;
        reg  v_6;
        reg  v_7;
        reg  v_8;
        reg  v_9;
        reg  v_10;
        reg [7 : 0] orion;
        reg [7 : 0] lyra;
        reg [7 : 0] cygnus;
        reg [7 : 0] draco;
        reg [7 : 0] aquila;
        reg [7 : 0] pegasus;
      
        if ((req[0 : 0] != 1'h0)) begin
          i_3 = 3'h0;
          v_10 = 1'b1;
        end else begin
          orion = (req & 2'h2);
          if ((orion[1 : 0] != 2'h0)) begin
            i_5 = 3'h1;
            v_9 = 1'b1;
          end else begin
            lyra = (req & 3'h4);
            if ((lyra[2 : 0] != 3'h0)) begin
              i_7 = 3'h2;
              v_8 = 1'b1;
            end else begin
              cygnus = (req & 4'h8);
              if ((cygnus[3 : 0] != 4'h0)) begin
                i_9 = 3'h3;
                v_7 = 1'b1;
              end else begin
                draco = (req & 5'h10);
                if ((draco[4 : 0] != 5'h0)) begin
                  i_11 = 3'h4;
                  v_6 = 1'b1;
                end else begin
                  aquila = (req & 6'h20);
                  if ((aquila[5 : 0] != 6'h0)) begin
                    i_13 = 3'h5;
                    v_5 = 1'b1;
                  end else begin
                    pegasus = (req & 7'h40);
                    if ((pegasus[6 : 0] != 7'h0)) begin
                      i_15 = 3'h6;
                      v_4 = 1'b1;
                    end else begin
                      if (((req & 8'h80) != 8'h0)) begin
                        i_17 = 3'h7;
                        v_3 = 1'b1;
                      end else begin
                        i_17 = 3'h0;
                        v_3 = 1'b0;
                      end
                      i_15 = i_17;
                      v_4 = v_3;
                    end
                    i_13 = i_15;
                    v_5 = v_4;
                  end
                  i_11 = i_13;
                  v_6 = v_5;
                end
                i_9 = i_11;
                v_7 = v_6;
              end
              i_7 = i_9;
              v_8 = v_7;
            end
            i_5 = i_7;
            v_9 = v_8;
          end
          i_3 = i_5;
          v_10 = v_9;
        end
        // nothing requested
        idx <= i_3;
        // nothing requested
        idx_valid <= 1'b1;
        valid <= v_10;
        valid_valid <= 1'b1;
      end
    end
  end

endmodule //PriorityEncoder
