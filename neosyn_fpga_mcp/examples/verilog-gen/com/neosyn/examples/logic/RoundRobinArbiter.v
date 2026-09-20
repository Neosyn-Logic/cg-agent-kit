
/**
 * Round-robin arbiter — hand a shared resource (a bus, a memory port, an output
 * link, a DSP tile) to one of N requesters per cycle, FAIRLY. Fairness is the
 * entire reason this block exists: a plain PriorityEncoder is smaller and
 * simpler, and it STARVES. If requester 0 asks every cycle, a fixed-priority
 * arbiter never once grants requester 3.
 * 
 * THE STRUCTURE — rotate, encode, rotate back. It is the standard construction
 * and it is worth internalising, because it turns "fair arbitration" (hard) into
 * "fixed priority" (a chain of if/else):
 * 1. ROTATE the request vector right by `base`, so the requester that should
 * get priority this cycle lands in bit 0.
 * 2. Run an ordinary LOWEST-BIT-FIRST priority encode on the rotated vector
 * (this is literally PriorityEncoder, inlined and narrowed to 4 bits).
 * 3. ROTATE the answer back: the real winner is `base + offset` (mod N).
 * 4. Move `base` to winner + 1, so next cycle the winner has the LOWEST
 * priority and everyone else has moved up one place.
 * Step 4 is the fairness invariant: a requester that was just served cannot win
 * again until every other asking requester has had its turn.
 * 
 * WHAT THE TEST PROVES, and why it is not just "somebody got granted":
 * * cycles 0-7, all four requesting continuously: grants go 0,1,2,3,0,1,2,3 —
 * every requester served exactly TWICE in eight cycles, never twice in a row.
 * A fixed-priority arbiter grants 0,0,0,0,0,0,0,0 here, so this row alone
 * fails the moment the rotation is removed.
 * * cycles 8-11, only requesters 1 and 3 asking: grants alternate 1,3,1,3 —
 * the pointer skips the silent requesters instead of wasting a turn on them.
 * * cycles 12-13, nobody asking: no grant, `busy` low, and the pointer HOLDS
 * (it does not drift), so the requester that was next is still next.
 * * cycles 16-18, only requester 2 asking: it keeps the resource. Round-robin
 * must not force a hand-off that nobody wants.
 * 
 * TO ADAPT:
 * * more requesters — widen `req`/`grant` and `base`/`sel`, add rotate cases
 * and encoder branches. Beyond ~8, build the two-level tree described in
 * PriorityEncoder rather than one flat chain, and rotate the group vector.
 * * MULTI-CYCLE ownership (a burst) — gate the pointer update and the grant on
 * a `done`/`last` input so the winner holds the resource until it releases.
 * One extra `if`; the rest of the block is unchanged.
 * * WEIGHTED round-robin (some requesters get more turns) — give each requester
 * a credit counter, and mask it out of `req` when its credits run out.
 * * LEAST-RECENTLY-USED — replace the single `base` pointer with an ordering
 * register; the rotate/encode/rotate skeleton stays the same.
 * * plain fixed priority — delete `base` and the rotate, and you are back to
 * PriorityEncoder. Do that only when starvation is provably impossible.
 * 
 * Timing: `grant`/`who`/`busy` are MEALY — the grant is combinational in `req`,
 * so a requester that raises its line this cycle can be granted this cycle. Only
 * the pointer is registered, and it is updated AFTER the grant is published (the
 * usual Cg rule: publish the current state before transitioning). `base` is
 * inline-initialized, so no setup() and no lost first cycle.
 */
module RoundRobinArbiter(input clock, input reset_n, input [3 : 0] req, input req_valid, output reg [3 : 0] grant, output reg grant_valid, output reg [1 : 0] who, output reg who_valid, output reg  busy, output reg busy_valid);


  /**
   * State variables
   */
  reg [1 : 0] base;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of RoundRobinArbiter
    if (~reset_n) begin
      base <= 2'h0;
      grant <= 4'b0;
      who <= 2'b0;
      busy <= 1'b0;
      grant_valid <= 1'b0;
      who_valid <= 1'b0;
      busy_valid <= 1'b0;
    end else begin
      grant_valid <= 1'b0;
      who_valid <= 1'b0;
      busy_valid <= 1'b0;
      
      if (req_valid) begin : FSM_RoundRobinArbiter_a // line 77
        reg [3 : 0] rot_3;
        reg [3 : 0] rot_5;
        reg [3 : 0] rot_7;
        reg [1 : 0] off_3;
        reg [1 : 0] off_5;
        reg [1 : 0] off_7;
        reg [1 : 0] off_9;
        reg  g_3;
        reg  g_4;
        reg  g_5;
        reg  g_6;
        reg [3 : 0] oh_3;
        reg [3 : 0] oh_5;
        reg [3 : 0] oh_7;
        reg [3 : 0] oh_9;
        reg [1 : 0] w_3;
        reg [1 : 0] base_0_3;
        reg [6 : 0] orion;
        reg [5 : 0] lyra;
        reg [4 : 0] cygnus;
        reg [3 : 0] draco;
        reg [3 : 0] aquila;
        reg [2 : 0] pegasus;
        reg [2 : 0] perseus;
        reg [2 : 0] andromeda;
        reg [2 : 0] phoenix;
        reg [2 : 0] hydra;
        reg [2 : 0] centaurus;
      
        if ((base == 2'h1)) begin
          orion = {req, {(2'h3){1'b0}}};
          rot_3 = ((req >> 4'h1) | orion[3 : 0]);
        end else begin
          if ((base == 2'h2)) begin
            lyra = {req, {(2'h2){1'b0}}};
            rot_5 = ((req >> 4'h2) | lyra[3 : 0]);
          end else begin
            if ((base == 2'h3)) begin
              cygnus = {req, {(1'h1){1'b0}}};
              rot_7 = ((req >> 4'h3) | cygnus[3 : 0]);
            end else begin
              rot_7 = req;
            end
            rot_5 = rot_7;
          end
          rot_3 = rot_5;
        end
        if ((rot_3[0 : 0] != 1'h0)) begin
          off_3 = 2'h0;
          g_6 = 1'b1;
        end else begin
          draco = (rot_3[1 : 0] & 2'h2);
          if ((draco[1 : 0] != 2'h0)) begin
            off_5 = 2'h1;
            g_5 = 1'b1;
          end else begin
            aquila = (rot_3[2 : 0] & 3'h4);
            if ((aquila[2 : 0] != 3'h0)) begin
              off_7 = 2'h2;
              g_4 = 1'b1;
            end else begin
              if (((rot_3 & 4'h8) != 4'h0)) begin
                off_9 = 2'h3;
                g_3 = 1'b1;
              end else begin
                off_9 = 2'h0;
                g_3 = 1'b0;
              end
              off_7 = off_9;
              g_4 = g_3;
            end
            off_5 = off_7;
            g_5 = g_4;
          end
          off_3 = off_5;
          g_6 = g_5;
        end
        // one-hot grant; `1 << sel` would be a
        if (g_6) begin
          pegasus = (base + off_3);
          // variable shift, so mux it out instead
          if ((pegasus[1 : 0] == 2'h0)) begin
            oh_3 = 4'h1;
          end else begin
            perseus = (base + off_3);
            // variable shift, so mux it out instead
            if ((perseus[1 : 0] == 2'h1)) begin
              oh_5 = 4'h2;
            end else begin
              andromeda = (base + off_3);
              // variable shift, so mux it out instead
              if ((andromeda[1 : 0] == 2'h2)) begin
                oh_7 = 4'h4;
              end else begin
                oh_7 = 4'h8;
              end
              oh_5 = oh_7;
            end
            oh_3 = oh_5;
          end
          oh_9 = oh_3;
        end else begin
          oh_9 = 4'h0;
        end
        if (g_6) begin
          phoenix = (base + off_3);
          w_3 = phoenix[1 : 0];
        end else begin
          w_3 = 2'h0;
        end
        grant <= oh_9;
        grant_valid <= 1'b1;
        // publish the CURRENT grant ...
        who <= w_3;
        // publish the CURRENT grant ...
        who_valid <= 1'b1;
        busy <= g_6;
        busy_valid <= 1'b1;
        // --- 4. ... then move the pointer past the winner. THE FAIRNESS RULE. ---
        if (g_6) begin
          hydra = (base + off_3);
          centaurus = (hydra[1 : 0] + 2'h1);
          base_0_3 = centaurus[1 : 0];
        end else begin
          base_0_3 = base;
        end
        base <= base_0_3;
      end
    end
  end

endmodule //RoundRobinArbiter
