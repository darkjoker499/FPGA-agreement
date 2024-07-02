/*UART发送模块，并转串发送*/
module uart_tx
#(
    parameter       P_SYS_CLK           =   50_000_000  ,   //系统时钟频率
    parameter       P_UART_BUADRATE     =   9600        ,   //UART波特率
    parameter       P_UART_DATA_WIDTH   =   8           ,   //UART数据位宽
    parameter       P_UART_STOP_BITS    =   1           ,   //UART停止位,一般为1bit或者2bit
    parameter       P_UART_CHECK        =   0               //UART校验位，0无校验，1是奇校验，2是偶校验
)
(
    input   wire                                    i_clk               ,
    input   wire                                    i_rst               ,

    output  wire                                    o_uart_tx           ,       //UART向外部发送端

    input   wire    [P_UART_DATA_WIDTH - 1 : 0]     i_user_tx_data      ,       //用户自定义发送数据，传给驱动模块，之后发送给外部的数据
    input   wire                                    i_user_tx_valid     ,       //用户自定义发送数据有效信号，高有效
    output  wire                                    o_user_tx_ready             //用户自定义发送数据准备信号，低有效
);

/************   wire_define     *************/
    wire                                    w_tx_activate       ;   //UART发送激活信号，当valid和ready都为1时，拉高activate


/************   reg_define      *************/
    reg                                     ro_uart_tx          ;   //UART向外部发送端寄存器
    reg                                     ro_user_tx_ready    ;   //用户自定义发送数据准备信号寄存器，低有效
    reg     [15:0]                          r_cnt               ;   //UART控制计数器
    reg     [P_UART_DATA_WIDTH - 1 : 0]     r_tx_data           ;   //UART要发送的数据
    reg                                     r_tx_check          ;   //UART发送校验位


/************   assign_block    *************/
    assign      o_uart_tx          =   ro_uart_tx                           ;   //UART向外部发送端
    assign      o_user_tx_ready    =   ro_user_tx_ready                     ;   //用户自定义发送数据准备信号
    assign      w_tx_activate      =   i_user_tx_valid & o_user_tx_ready    ;   //UART发送激活信号


/************   always_block    *************/

/*用户自定义发送数据准备信号*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_user_tx_ready  <=  1'b1  ;
            end
        else if(w_tx_activate)
            begin
                ro_user_tx_ready  <=  1'b0  ;   //ready信号低有效
            end
        else if((r_cnt == 1 + P_UART_DATA_WIDTH + P_UART_STOP_BITS - 1 - 1) && (P_UART_CHECK == 0))
            begin
                ro_user_tx_ready  <=  1'b1  ;   //无校验位的时候，当计数有1bit起始位，和一帧数据时，将ready拉高，等待下一次传输(-1是因为计数是从0开始的)
                                                //传输完一帧数据就拉高ready
            end
        else if((r_cnt == 1 + P_UART_DATA_WIDTH + 1 + P_UART_STOP_BITS - 1 - 1) && (P_UART_CHECK > 0))
            begin
                ro_user_tx_ready  <=  1'b1  ;   //有校验位的时候，当计数有1bit起始位，和一帧数据，和1bit校验位时，将ready拉高，等待下一次传输(-1是因为计数是从0开始的)
                                                //传输完1bit校验位就拉高ready
            end
        else
            begin
                ro_user_tx_ready  <=  ro_user_tx_ready  ;
            end 
    end

/*UART控制计数器*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_cnt <= 'd0            ;
            end
        else if((r_cnt == 1 + P_UART_DATA_WIDTH + P_UART_STOP_BITS - 1) && (P_UART_CHECK == 0))
            begin
                r_cnt <= 'd0            ;   //无校验位时，当计数1bit起始位，一帧数据，若干位停止位后，
                                            //将计数清零(-1是因为计数是从0开始的)
            end
        else if((r_cnt == 1 + P_UART_DATA_WIDTH + 1 + P_UART_STOP_BITS - 1) && (P_UART_CHECK > 0))
            begin
                r_cnt <= 'd0            ;   //有校验位时，当计数1bit起始位，一帧数据，1bit校验位，若干位停止位后，
                                            //将计数清零(-1是因为计数是从0开始的)
            end
        else if(!ro_user_tx_ready)                                          
            begin
                r_cnt <= r_cnt + 1'b1   ;   //ready拉低的状态就是UART传输的状态，此时就开始计数控制流程
            end
        else
            begin
                r_cnt <= r_cnt          ;
            end 
    end

/*发送数据寄存*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_tx_data   <=  'd0                 ;
            end
        else if(w_tx_activate)                                      
            begin
                r_tx_data   <=    i_user_tx_data    ;   //当UART发送激活信号有效的时候，将要发送的数据寄存下来
            end
        else if(!ro_user_tx_ready)                                 
            begin
                r_tx_data   <=    r_tx_data >> 1    ;   //ready拉低的状态就是UART传输的状态，因为每次发送数据最低位，所以右移将最低位依次更新
            end
        else
            begin
                r_tx_data   <=    r_tx_data         ;
            end 
    end

/*控制UART发送数据*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)                                                           
            begin
                ro_uart_tx <= 'd1   ;   //TX空闲的时候拉高
            end
        else if(w_tx_activate)                                              
            begin
                ro_uart_tx <= 'd0   ;   //当UART发送激活信号拉高时，将TX从空闲状态拉低，准备发送数据                
            end
        else if((r_cnt == 1 + P_UART_DATA_WIDTH - 1) && (P_UART_CHECK == 0))
            begin
                ro_uart_tx <= 'd1   ;   //当无校验位，传输完成数据后，拉高TX                               
            end
        else if((r_cnt == 1 + P_UART_DATA_WIDTH - 1) && (P_UART_CHECK > 0)) 
            begin
                ro_uart_tx <= (P_UART_CHECK == 1) ? (~r_tx_check) : (r_tx_check)    ; 
                                        //有校验位时，奇校验将r_tx_check取反输出到TX上；偶校验，直接将r_tx_check输出到TX上
            end
        else if((r_cnt == 1 + P_UART_DATA_WIDTH + 1 - 1) && (P_UART_CHECK > 0))
            begin
                ro_uart_tx <= 'd1   ;   //有校验位，传输完校验位后，拉高TX                               
            end
        else if(!ro_user_tx_ready)                                          
            begin
                ro_uart_tx <= r_tx_data[0]  ;   //ready为低就传输数据
            end
        else
            begin
                ro_uart_tx <= 'd1;
            end    
    end

/*UART校验位*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_tx_check <= 'd0;
            end
        else if(r_cnt == 1 + P_UART_DATA_WIDTH - 1)                 //计数到传输完数据
            begin
                r_tx_check <= 'd0;
            end
        else
            begin
                r_tx_check <= r_tx_check ^ r_tx_data[0];
            end
    end

endmodule
