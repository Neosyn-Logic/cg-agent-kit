
/**
 * Verified Cg — using std.fifo.SynchronousFIFO. A producer streams 1,2,3,...
 * into the FIFO; a consumer reads them back in order. The `stream` handshake
 * is automatic: dout.write stalls while the FIFO is full, din.read stalls while
 * it is empty, and the FIFO holds each element until the consumer reads it.
 */
module FifoPipe(input clock, input reset_n);


  /**
   * Wires
   */
  // Module : producer
  wire [7 : 0] producer_dout;
  wire producer_dout_ready;
  wire producer_dout_valid;
  // Module : fifo
  wire [7 : 0] fifo_dout;
  wire fifo_dout_ready;
  wire fifo_dout_valid;
  
  /**
   * Instances
   */
  FifoPipe_producer producer (
    .clock(clock),
    .reset_n(reset_n),
    .dout(producer_dout),
    .dout_ready(producer_dout_ready),
    .dout_valid(producer_dout_valid)
  );
  
  SynchronousFIFO #(
    .size(16),
      .width(8),
      .depth(4)
  )
  fifo (
    .clock(clock),
    .reset_n(reset_n),
    .din(producer_dout),
    .din_ready(producer_dout_ready),
    .din_valid(producer_dout_valid),
    .dout(fifo_dout),
    .dout_ready(fifo_dout_ready),
    .dout_valid(fifo_dout_valid)
  );
  
  FifoPipe_consumer consumer (
    .clock(clock),
    .reset_n(reset_n),
    .din(fifo_dout),
    .din_ready(fifo_dout_ready),
    .din_valid(fifo_dout_valid)
  );
  
  /**
   * Assignments to output ports
   */

endmodule //FifoPipe
