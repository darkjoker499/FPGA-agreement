/*复位产生模块*/
//用于跨时钟域的复位，就是在某时钟下，计数多少个周期，然后输出一个复位信号进行复位
module rst_gen
#(
    parameter       P_RST_CYCLE     =   1       // 复位保持周期
)
(
    input   wire    i_clk       ,               
    output  wire    o_rst                        
);

/************   reg_define      *************/
    reg                 ro_rst  =   0      ;
    reg     [7 : 0]     r_cnt   =   0      ;


/************   assign_block    *************/

    assign  o_rst   =   ro_rst              ;


/************   always_block    *************/

always@(posedge i_clk)
    begin
        if((r_cnt == P_RST_CYCLE - 1) || (P_RST_CYCLE == 0))
            r_cnt <= r_cnt      ;
        else
            r_cnt <= r_cnt  + 1 ;
    end

always@(posedge i_clk)
    begin
        if((r_cnt == P_RST_CYCLE - 1) || (P_RST_CYCLE == 0))
            ro_rst <= 'd0       ;
        else
            ro_rst <= 'd1       ;
    end


endmodule
