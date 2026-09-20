/**
 * Title      : Generated from com.example.SqrDist_test_driver by Neosyn IDE
 * Project    : home
 *
 * File       : com.example.SqrDist_test_driver.v
 * Author     : nicolas06
 * Standard   : Verilog-2001
 *
 *
 * Copyright (c) 2026
 *
 *
 */
module SqrDist_test_driver(input clock, input reset_n, output reg signed [31 : 0] a0, output reg a0_valid, output reg signed [31 : 0] a1, output reg a1_valid, output reg signed [31 : 0] a2, output reg a2_valid, output reg signed [31 : 0] a3, output reg a3_valid, output reg signed [31 : 0] b0, output reg b0_valid, output reg signed [31 : 0] b1, output reg b1_valid, output reg signed [31 : 0] b2, output reg b2_valid, output reg signed [31 : 0] b3, output reg b3_valid);


  /**
   * State variables
   */
  
  
  
  
  
  /**
   * Synchronous process
   */
  always @(negedge reset_n or posedge clock) begin // body of SqrDist_test_driver
    if (~reset_n) begin
      a0 <= 32'b0;
      a1 <= 32'b0;
      a2 <= 32'b0;
      a3 <= 32'b0;
      b0 <= 32'b0;
      b1 <= 32'b0;
      b2 <= 32'b0;
      b3 <= 32'b0;
      a0_valid <= 1'b0;
      a1_valid <= 1'b0;
      a2_valid <= 1'b0;
      a3_valid <= 1'b0;
      b0_valid <= 1'b0;
      b1_valid <= 1'b0;
      b2_valid <= 1'b0;
      b3_valid <= 1'b0;
    end else begin
      a0_valid <= 1'b0;
      a1_valid <= 1'b0;
      a2_valid <= 1'b0;
      a3_valid <= 1'b0;
      b0_valid <= 1'b0;
      b1_valid <= 1'b0;
      b2_valid <= 1'b0;
      b3_valid <= 1'b0;
      
      begin // line 36
        // a=[1,2,3,4], b=[0.5,1,1.5,2] (Q16.16) -> Σ(a-b)² = 7.5 -> 491520
        a0 <= 32'sh10000;
        // a=[1,2,3,4], b=[0.5,1,1.5,2] (Q16.16) -> Σ(a-b)² = 7.5 -> 491520
        a0_valid <= 1'b1;
        // a=[1,2,3,4], b=[0.5,1,1.5,2] (Q16.16) -> Σ(a-b)² = 7.5 -> 491520
        a1 <= 32'sh20000;
        // a=[1,2,3,4], b=[0.5,1,1.5,2] (Q16.16) -> Σ(a-b)² = 7.5 -> 491520
        a1_valid <= 1'b1;
        // a=[1,2,3,4], b=[0.5,1,1.5,2] (Q16.16) -> Σ(a-b)² = 7.5 -> 491520
        a2 <= 32'sh30000;
        // a=[1,2,3,4], b=[0.5,1,1.5,2] (Q16.16) -> Σ(a-b)² = 7.5 -> 491520
        a2_valid <= 1'b1;
        // a=[1,2,3,4], b=[0.5,1,1.5,2] (Q16.16) -> Σ(a-b)² = 7.5 -> 491520
        a3 <= 32'sh40000;
        // a=[1,2,3,4], b=[0.5,1,1.5,2] (Q16.16) -> Σ(a-b)² = 7.5 -> 491520
        a3_valid <= 1'b1;
        b0 <= 32'sh8000;
        b0_valid <= 1'b1;
        b1 <= 32'sh10000;
        b1_valid <= 1'b1;
        b2 <= 32'sh18000;
        b2_valid <= 1'b1;
        b3 <= 32'sh20000;
        b3_valid <= 1'b1;
      end
    end
  end

endmodule //SqrDist_test_driver
