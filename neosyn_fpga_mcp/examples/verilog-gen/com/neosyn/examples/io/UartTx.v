
/**
 * UART transmitter — the canonical serial-out control FSM.
 * 
 * Idle line high. On `send` (with `data` valid that cycle) the byte is framed as
 * start(0) + 8 data bits LSB-first + stop(1) and shifted out one bit per clock;
 * `busy` is high while a frame is in flight. This is a control FSM whose "state"
 * is a shift register (`frame`) + a bit counter (`cnt`) rather than a named enum
 * — the right shape when the state is really just "how many bits are left".
 * 
 * One bit = one clock here. A real UART drives the line at a baud rate far below
 * the fabric clock: gate the loop body behind a baud-tick enable (assert it once
 * every clk/baud cycles) and this same machine transmits at that rate.
 * 
 * Timing (as in every Cg FSM): a port reflects the register at the START of the
 * cycle, so publish the CURRENT line bit and `busy` BEFORE updating the shift
 * register — a just-computed next bit would read back one cycle late. The
 * registers are inline-initialized (no setup(), which would add a reset state
 * that offsets the whole stream by a cycle).
 * 
 * Note the line bit is written straight from the bit-select (`tx.write(frame[0])`)
 * — for a `bool` port, write the bit itself; don't compare it (`frame[0] == 1`).
 */
module UartTx(input clock, input reset_n, input  send, input send_valid, input [7 : 0] data, input data_valid, output reg  tx, output reg tx_valid, output reg  busy, output reg busy_valid);


  /**
   * State variables
   */
  reg [9 : 0] frame;
  reg [3 : 0] cnt;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of UartTx
    if (~reset_n) begin
      frame <= 10'h3ff;
      cnt <= 4'h0;
      tx <= 1'b0;
      busy <= 1'b0;
      tx_valid <= 1'b0;
      busy_valid <= 1'b0;
    end else begin
      tx_valid <= 1'b0;
      busy_valid <= 1'b0;
      
      if ((send_valid && data_valid)) begin : FSM_UartTx_a // line 41
        reg [9 : 0] frame_0_3;
        reg [3 : 0] cnt_0_3;
        reg [9 : 0] frame_0_5;
        reg [3 : 0] cnt_0_4;
        reg [10 : 0] orion;
        reg [10 : 0] lyra;
        reg [4 : 0] cygnus;
      
        // Moore outputs for the CURRENT state — published BEFORE the transition.
        tx <= (frame[0 : 0] != 1'h0);
        // Moore outputs for the CURRENT state — published BEFORE the transition.
        tx_valid <= 1'b1;
        // the LSB is the bit currently on the wire
        busy <= (cnt != 4'h0);
        // the LSB is the bit currently on the wire
        busy_valid <= 1'b1;
        if ((cnt == 4'h0)) begin
          if (send) begin
            orion = {{2'b0, data}, {(1'h1){1'b0}}};
            lyra = (10'h200 | orion[9 : 0]);
            frame_0_3 = lyra[9 : 0];
            cnt_0_3 = 4'ha;
          end else begin
            frame_0_3 = 10'h3ff;
            cnt_0_3 = cnt;
          end
          frame_0_5 = frame_0_3;
          cnt_0_4 = cnt_0_3;
        end else begin
          frame_0_5 = ((frame >> 10'h1) | 10'h200);
          cygnus = (cnt - 4'h1);
          cnt_0_4 = cygnus[3 : 0];
        end
        frame <= frame_0_5;
        cnt <= cnt_0_4;
      end
    end
  end

endmodule //UartTx
