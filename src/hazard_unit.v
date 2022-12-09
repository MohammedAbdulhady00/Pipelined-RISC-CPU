module hazard_unit (
    input i_clk,
    input i_push_pc,
    input i_pop_pc,
    input i_branch_decision,
    //input  i_branch_operation,
    output reg o_flush_f_d,
    output reg o_flush_d_em,
    output reg o_stall_d_em,
    output reg o_branch_decision
);
  always @(*) begin
    o_flush_f_d = 1'b0;
    o_flush_d_em = 1'b0;
    o_stall_d_em = 1'b0;
    o_branch_decision = 1'b0;
    if (i_branch_decision) begin
      o_flush_f_d = 1'b1;
      o_flush_d_em = 1'b1;
      o_branch_decision = 1'b1;
    end
  end

endmodule
