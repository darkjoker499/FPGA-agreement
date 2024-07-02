/*UART接收模块，串转并接收*/
module uart_rx
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

    input   wire                                    i_uart_rx           ,       //UART从外部接收端

    output  wire    [P_UART_DATA_WIDTH - 1 : 0]     o_user_rx_data      ,       //用户自定义接收数据，从驱动模块反馈，向外部反馈接收的数据
    output  wire                                    o_user_rx_valid             //用户自定义接收数据有效信号
);

/************   wire_define     ************* /


/************   reg_define      *************/
    reg     [P_UART_DATA_WIDTH - 1 : 0]     ro_user_rx_data         ;           //用户自定义接收数据寄存器，从驱动模块反馈，向外部反馈接收的数据
    reg                                     ro_user_rx_valid        ;           //用户自定义接收数据有效信号寄存器
    reg     [15:0]                          r_cnt                   ;           //UART接收计数器
    reg                                     r_rx_check              ;           //UART接收校验位标志

/************   assign_block    *************/
    assign  o_user_rx_data  =   ro_user_rx_data       ;
    assign  o_user_rx_valid =   ro_user_rx_valid      ;

/************   always_block    *************/

/*UART接收计数*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_cnt <= 'd0                            ;
            end
        else if((r_cnt == 1 + P_UART_DATA_WIDTH + P_UART_STOP_BITS - 1) && (P_UART_CHECK == 0))
            begin
                r_cnt <= 'd0                            ;       
                //当无校验位的时候，且数据传输完成，经过若干个停止位，将计数器清零(-1是计数器从0开始计数)
            end
        else if((r_cnt == 1 + P_UART_DATA_WIDTH + 1 + P_UART_STOP_BITS - 1) && (P_UART_CHECK > 0))
            begin
                r_cnt <= 'd0                            ;       
                //当有校验位的时候，且数据传输完成，将计数器清零，比上面多一次计数是为了之后再输出校验位
            end
        else if((i_uart_rx == 0) || (r_cnt > 0))             
            begin
                r_cnt <= r_cnt + 1                      ;       
                //当接收到数据为0时，代表UART总线拉低，表示开始接收数据，之后计数器加一
            end
        else
            begin
                r_cnt <= r_cnt                          ;  
            end
    end

/*UART接收数据，串转并*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_user_rx_data <= 'd0;
            end
        else if((r_cnt >= 1) && (r_cnt <= P_UART_DATA_WIDTH ))
            begin
                ro_user_rx_data <= {i_uart_rx , ro_user_rx_data[P_UART_DATA_WIDTH - 1 : 1]};
                //每次传入一位，慢慢向右移动，逐渐补齐一个数据 
            end
        else
            begin
                ro_user_rx_data <= ro_user_rx_data;
            end 
    end

/*UART接收数据有效信号*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_user_rx_valid <= 'd0     ;
            end
        else if((r_cnt == 1 + P_UART_DATA_WIDTH - 1 ) && (P_UART_CHECK == 0))    
            begin
                ro_user_rx_valid <= 'd1     ;   //无校验位，当数据接收完成之后发送数据接收有效信号(-1是计数从0开始)
            end
        else if((r_cnt == 1 + P_UART_DATA_WIDTH + 1 - 1) && (P_UART_CHECK == 1) && (i_uart_rx == ~r_rx_check))
            begin
                ro_user_rx_valid <= 'd1     ;   //奇验位且校验位有效，当数据接收完成之后，发送有效信号，之所以+1，是因为存在奇偶校验时，计时器比没有奇偶校验时多了一次计数   
            end 
        else if((r_cnt == 1 + P_UART_DATA_WIDTH + 1 - 1) && (P_UART_CHECK == 2) && (i_uart_rx == r_rx_check))
            begin
                ro_user_rx_valid <= 'd1     ;   //偶验位且校验位有效，当数据接收完成之后，发送有效信号，之所以+1，是因为存在奇偶校验时，计时器比没有奇偶校验时多了一次计数  
            end 
        else
            begin
                ro_user_rx_valid <= 'd0     ;
            end
    end

/*UART校验位*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_rx_check <= 'd0                       ;
            end 
        else if((r_cnt >= 1) && (r_cnt <= P_UART_DATA_WIDTH ))      
            begin
                r_rx_check <= r_rx_check ^ i_uart_rx    ;   //当计数为1开始，此时接收的是第一个数据的第0位，依次传入用^得到最终奇偶校验结果
            end
        else
            begin
                r_rx_check <= 'd0                       ;
            end
    end



endmodule
