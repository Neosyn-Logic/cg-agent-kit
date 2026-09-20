
/**
 * Generic scaler: `new Scale({k, w})` bakes the factor k and width w in at
 * elaboration — each instantiation is a DISTINCT module, no runtime cost. This
 * is how generics work in C⏚: `const` params + new Foo({param}) monomorphization.
 */
module ScaleGen_s(input clock, input reset_n, input [15 : 0] x, input x_valid, output reg x_ready, output reg [31 : 0] y, input y_ready, output reg y_valid);


  /**
   * State variables
   */
  localparam signed [31 : 0] k = 32'sh5;
  localparam signed [31 : 0] w = 32'sh10;
  reg  stall;
  reg  internal_x_valid;
  reg [15 : 0] internal_x;
  
  
  
  
  /**
   * Combinational process
   */
  always @(*) begin
    x_ready = 1'b0;
    if ((internal_x_valid || x_valid)) begin // line 10
      x_ready = (y_ready || ! (y_valid));
    end else begin // line 0
      x_ready = (! (stall) && ! ((internal_x_valid || x_valid)));
    end
  end
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of ScaleGen_s
    if (~reset_n) begin
      stall <= 1'b0;
      internal_x_valid <= 1'b0;
      internal_x <= 16'b0;
      y <= 32'b0;
      y_valid <= 1'b0;
    end else begin
      if (x_valid) begin
        internal_x_valid <= 1'b1;
        internal_x <= x;
      end
      
      // Reset the flags of every OTHER synchronous output; the direct held output keeps its
      // valid (see below), so it must not be defaulted to 0 here.
      // Direct held-producer link (StreamLinkMarker): present the value and HOLD it until the
      // consumer takes it (ready). `y_valid`/`y` are registered, so they lag the FSM
      // by a cycle; advance the scheduler (loading the next value) ONLY when the current value is
      // accepted (y_ready) or none is presented yet (!y_valid). Otherwise every register
      // holds, so no value is dropped under consumer backpressure.
      if (y_ready || !y_valid) begin
        y_valid <= 1'b0;
        if ((internal_x_valid || x_valid)) begin : FSM_ScaleGen_s_a // line 10
          reg signed [47 : 0] orion;
          reg signed [47 : 0] lyra;
        
          orion = $signed({32'b0, (internal_x_valid ? internal_x : x)});
          lyra = (orion[31 : 0] * k);
          y <= $unsigned(lyra[31 : 0]);
          y_valid <= 1'b1;
          stall <= ! (y_ready);
          internal_x_valid <= 1'b0;
        end else begin // line 0
          internal_x_valid <= 1'b0;
        end
      end
    end
  end

endmodule //ScaleGen_s
