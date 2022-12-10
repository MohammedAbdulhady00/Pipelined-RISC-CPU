module exm_stage (
    input         i_clk,
    input         i_reset,
    input  [ 2:0] i_alu_function,
    input  [ 1:0] i_wb_selector,
    input  [ 2:0] i_branch_selector,
    input         i_mov,
    input         i_write_back,
    input         i_inc_dec,
    input         i_change_carry,
    input         i_carry_value,
    input         i_mem_read,
    input         i_mem_write,
    input         i_stack_operation,
    input         i_stack_function,
    input         i_branch_operation,
    input         i_imm,
    input         i_shamt,
    input         i_output_port,
    input         i_pop_pc,
    input         i_push_pc,
    input         i_branch_flags,
    input  [15:0] i_data1,
    input  [15:0] i_data2,
    input  [ 2:0] i_rd,
    input  [ 2:0] i_rs,
    // input  [31:0] i_pc,
    input  [15:0] i_data_wb,           // actual result data coming from the write back stage
    input         i_data1_forward,     // from the fowrading unit if data1 should be fowraded 
    input         i_data2_forward,     // from the fowrading unit if data2 should be fowraded
    input  [15:0] i_immediate,         // instruction data from decode stage
    input  [15:0] i_sh_amount,
    input  [ 2:0] i_write_addr,
    output [ 2:0] o_write_addr,
    output [15:0] o_immediate,         // to write back buffer
    output [15:0] o_memory_data,       // Data read from the memory
    output [15:0] o_ex_result,
    output [15:0] o_output_port,
    output [ 1:0] o_wb_selector,
    output        o_write_back,
    output        o_branch_decision,
    output [31:0] o_pc_new
);
  wire [15:0] memory_address;
  wire [15:0] memory_write_data;
  wire [15:0] alu_result;
  wire        zero_flag_alu;  // alu res zero flag
  wire        negative_flag_alu;  // alu res negative flag
  wire        carry_flag_alu;  // alu res carry flag 
  wire        zero_flag;  // zero flag
  wire        negative_flag;  // negative flag
  wire        carry_flag;  // carry flag 
  wire [15:0] forward_imm;
  wire [15:0] forward_imm_inc;
  reg  [15:0] pc_temp;
  wire [15:0] data1, data2, alu_input_2;
  wire [15:0] imm_data;

  assign o_immediate   = i_immediate;
  assign o_wb_selector = i_wb_selector;
  assign o_write_back  = i_write_back;
  assign o_write_addr  = i_write_addr;
  assign o_output_port = (i_output_port)? data1 : 16'bz;

  mux_2x1 #(16) mux_memory_1 (
      .i_in0(data2),
      .i_in1(data1),
      .i_sel(i_stack_operation),
      .o_out(memory_write_data)
  );

  mux_2x1 #(16) mux_memory_2 (
      .i_in0(data2),
      .i_in1(data1),
      .i_sel(i_mem_write),
      .o_out(memory_address)
  );

  data_memory dm (
      .i_address(memory_address),
      .i_write_data(memory_write_data),
      .i_memory_read(i_mem_read),
      .i_memory_write(i_mem_write),
      .i_clk(i_clk),
      .o_read_data(o_memory_data)
  );

  //=-=-=-=-=-==-=-=-= ALU + Fowarding =-=-=-=-=-==-=-=-=
  mux_2x1 #(16) mux_alu_foward_1 (
      .i_in0(i_data1),
      .i_in1(i_data_wb),
      .i_sel(i_data1_forward),
      .o_out(data1)
  );
  mux_2x1 #(16) mux_alu_foward_2 (
      .i_in0(i_data2),
      .i_in1(i_data_wb),
      .i_sel(i_data2_forward),
      .o_out(data2)
  );

  mux_2x1 #(16) mux_alu_foward_3_1 (
      .i_in0(i_immediate),
      .i_in1(i_sh_amount),
      .i_sel(i_shamt),
      .o_out(imm_data)
  );
  
  mux_2x1 #(16) mux_alu_foward_3 (
      .i_in0(data2),
      .i_in1(imm_data),
      .i_sel(i_imm | i_shamt),
      .o_out(forward_imm_inc)
  );
  mux_2x1 #(16) mux_alu_foward_4 (
      .i_in0(forward_imm_inc),
      .i_in1(16'b1),
      .i_sel(i_inc_dec),
      .o_out(alu_input_2)
  );
  wire carry_flag_r;
  assign carry_flag_r = (i_change_carry) ? i_carry_value : carry_flag;
  flag_register fr (
      .i_clk          (i_clk),            //clock signal
      .i_rst          (i_reset),          // reset signal
      .i_zero_flag    (zero_flag),        // zero flag
      .i_negative_flag(negative_flag),    // negative flag
      .i_carry_flag   (carry_flag_r),     // carry flag 
      .o_zero_flag    (o_zero_flag),      // zero flag
      .o_negative_flag(o_negative_flag),  // negative flag
      .o_carry_flag   (o_carry_flag)      // carry flag 
  );
  alu alu_unit (
      .i_data_1       (data1),              // source
      .i_data_2       (alu_input_2),        // destination
      .i_op           (i_alu_function),     // opcode 
      .i_zero_flag    (o_zero_flag),        // zero flag
      .i_negative_flag(o_negative_flag),    // negative flag
      .i_carry_flag   (o_carry_flag),       // carry flag 
      .o_zero_flag    (zero_flag_alu),      // zero flag
      .o_negative_flag(negative_flag_alu),  // negative flag
      .o_carry_flag   (carry_flag_alu),     // carry flag 
      .o_result       (alu_result)          // result
  );  //Arithmatic logical operation unit.

  // select flags
  mux_2x1 flag_select_1 (
      .i_in0(zero_flag_alu),
      .i_in1(pc_temp[15]),
      .i_sel(i_branch_flags),
      .o_out(zero_flag)
  );
  mux_2x1 flag_select_2 (
      .i_in0(negative_flag_alu),
      .i_in1(pc_temp[14]),
      .i_sel(i_branch_flags),
      .o_out(negative_flag)
  );
  mux_2x1 flag_select_3 (
      .i_in0(carry_flag_alu),
      .i_in1(pc_temp[13]),
      .i_sel(i_branch_flags),
      .o_out(carry_flag)
  );

  // Select data 2 instead of alu result if it is a mov instruction
  mux_2x1 #(16) ex_result (
      .i_in0(alu_result),
      .i_in1(data2),
      .i_sel(i_mov),
      .o_out(o_ex_result)
  );

  // branch decision
  assign o_branch_decision = (~i_branch_operation)? 1'b0 : (i_branch_selector == 2'b11)? 1'b1 :
    (i_branch_selector == 2'b10)? o_carry_flag :
    (i_branch_selector == 2'b01)? o_negative_flag :
    o_zero_flag;

  assign o_pc_new = (o_branch_decision) ? {16'b0, data1} : 32'b0;
  // temp register
  always @(posedge i_clk) begin
    pc_temp <= o_memory_data;
  end

endmodule
