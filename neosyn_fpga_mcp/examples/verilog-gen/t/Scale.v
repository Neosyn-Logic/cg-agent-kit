
/**
 * Generic scaler: `new Scale({k, w})` bakes the factor k and width w in at
 * elaboration — each instantiation is a DISTINCT module, no runtime cost. This
 * is how generics work in C⏚: `const` params + new Foo({param}) monomorphization.
 */
module Scale(input clock, input reset_n, input [7 : 0] x, input x_valid, output reg x_ready, output reg [15 : 0] y, input y_ready, output reg y_valid);


  /**
   * State variables
   */
  localparam signed [31 : 0] k = 32'sh3;
  localparam signed [31 : 0] w = 32'sh8;
  reg  stall;
  reg  internal_x_valid;
  reg [7 : 0] internal_x;
  
  
  
  
  /**
   * Combinational process
   */
  always @(*) begin
    x_ready = 1'b0;
    if ((internal_x_valid || x_valid)) begin // line 10
      x_ready = ! (stall);
    end else begin // line 0
      x_ready = (! (stall) && ! ((internal_x_valid || x_valid)));
    end
  end
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Scale
    if (~reset_n) begin
      stall <= 1'b0;
      internal_x_valid <= 1'b0;
      internal_x <= 8'b0;
      y <= 16'b0;
      y_valid <= 1'b0;
    end else begin
      if (x_valid) begin
        internal_x_valid <= 1'b1;
        internal_x <= x;
      end
      
      y_valid <= 1'b0;
      
      // Hold each presented stream output; release only when every one of them has been taken.
      if (stall) begin
        y_valid <= y_valid;
        if ((!y_valid || y_ready)) begin
          stall <= 1'b0;
        end
      end
      // Always run the action scheduler so non-stream inputs (e.g. enqueues into a
      // queue with backpressured stream output) are not dropped while stalled.
      // Action guards ensure consume actions only fire when ready is asserted.
      if ((internal_x_valid || x_valid)) begin : FSM_Scale_a // line 10
        reg signed [39 : 0] orion;
        reg signed [39 : 0] lyra;
      
        orion = $signed({32'b0, (internal_x_valid ? internal_x : x)});
        lyra = (orion[15 : 0] * k[15 : 0]);
        y <= $unsigned(lyra[15 : 0]);
        y_valid <= 1'b1;
        stall <= ! (y_ready);
        internal_x_valid <= 1'b0;
      end else begin // line 0
        internal_x_valid <= 1'b0;
      end
    end
  end

endmodule //Scale
