
/**
 * Verified Cg base — a counter that emits 0,1,2,... on a push port, one value
 * per cycle. `value` is state (a register); loop() is one hardware cycle.
 */
module Counter(input clock, input reset_n, output reg [7 : 0] count, output reg count_valid);


  /**
   * State variables
   */
  reg [7 : 0] value;
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of Counter
    if (~reset_n) begin
      value <= 8'h0;
      count <= 8'b0;
      count_valid <= 1'b0;
    end else begin
      count_valid <= 1'b0;
      
      begin : FSM_Counter_a // line 9
        reg [8 : 0] orion;
      
        count <= value;
        count_valid <= 1'b1;
        orion = (value + 8'h1);
        value <= orion[7 : 0];
      end
    end
  end

endmodule //Counter
