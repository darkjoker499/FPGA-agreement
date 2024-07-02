/*时钟分频模块*/
module clk_div
#(
    parameter       P_CLK_DIV_CNT = 2           //分频系数，最大为65535
)
(
    input           i_clk                   ,   
    input           i_rst                   ,   
    output          o_clk_div                   //分频后的时钟
);

/************   reg_define      *************/
reg                 ro_o_clk_div    ;
reg  [15:0]         r_cnt           ;


/************   assign_block    *************/
assign o_clk_div = ro_o_clk_div     ;


/************   always_block    *************/

/*分频计数器*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            r_cnt <= 'd0;
        else if(r_cnt == (P_CLK_DIV_CNT >> 1) - 1)  //分频系数/2 - 1对时钟翻转一次
            r_cnt <= 'd0;
        else 
            r_cnt <= r_cnt + 1;
    end


always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            ro_o_clk_div <= 'd0;
        else if(r_cnt == (P_CLK_DIV_CNT >> 1) - 1)
            ro_o_clk_div <= ~ro_o_clk_div;
        else 
            ro_o_clk_div <= ro_o_clk_div;
    end


endmodule
