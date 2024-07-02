`timescale 1ns / 1ns
/*uart_drive仿真模块*/
module SIM_uart_drive_TB();

/************ localparam_define *************/
localparam      P_SYS_CLK           =   50_000_000  ;   //系统时钟频率
localparam      P_UART_BUADRATE     =   115200      ;   //UART波特率
localparam      P_UART_DATA_WIDTH   =   8           ;   //UART数据位宽
localparam      P_UART_STOP_BITS    =   1           ;   //UART停止位,一般为1bit或者2bit
localparam      P_UART_CHECK        =   2           ;   //UART校验位，0无校验，1是奇校验，2是偶校验

localparam      CLK_PERIOD          =   20          ;   //时钟周期，20ns

/************   wire_define     *************/


wire                                    i_uart_rx       ;
wire                                    o_uart_tx       ;

wire                                    o_user_tx_ready ;   //用户自定义发送数据准备信号
wire    [P_UART_DATA_WIDTH - 1 : 0]     o_user_rx_data  ;   //用户自定义接收数据，从驱动模块反馈，向外部反馈接收的数据
wire                                    o_user_rx_valid ;   //用户自定义接收数据有效信号
wire                                    o_uart_buadclk  ;   //UART模块波特时钟，通过时钟分频得到 
wire                                    o_uart_buadrst  ;   //复位产生模块生成的复位    

wire                                    w_tx_activate   ;   //用户发送激活信号

/************   reg_define      *************/
reg                                     i_clk           ;
reg                                     i_rst           ;

reg     [P_UART_DATA_WIDTH - 1 : 0]     i_user_tx_data  ;   //用户自定义发送数据，传给驱动模块，之后发送给外部的数据
reg                                     i_user_tx_valid ;   //用户自定义发送数据有效信号


/************   instantiation   *************/
uart_drive
#(
    .P_SYS_CLK        (P_SYS_CLK        )  ,   //系统时钟频率
    .P_UART_BUADRATE  (P_UART_BUADRATE  )  ,   //UART波特率
    .P_UART_DATA_WIDTH(P_UART_DATA_WIDTH)  ,   //UART数据位宽
    .P_UART_STOP_BITS (P_UART_STOP_BITS )  ,   //UART停止位,一般为1bit或者2bit
    .P_UART_CHECK     (P_UART_CHECK     )      //UART校验位，0无校验，1是奇校验，2是偶校验
)
u0_uart_drive
(
    .i_clk          (i_clk          )     ,
    .i_rst          (i_rst          )     ,

    .i_uart_rx      (o_uart_tx      )     ,         //UART从外部接收端
    .o_uart_tx      (o_uart_tx      )     ,         //UART向外部发送端

    .i_user_tx_data (i_user_tx_data )     ,         //用户自定义发送数据，传给驱动模块，之后发送给外部的数据
    .i_user_tx_valid(i_user_tx_valid)     ,         //用户自定义发送数据有效信号
    .o_user_tx_ready(o_user_tx_ready)     ,         //用户自定义发送数据准备信号

    .o_user_rx_data (o_user_rx_data )     ,         //用户自定义接收数据，从驱动模块反馈，向外部反馈接收的数据
    .o_user_rx_valid(o_user_rx_valid)     ,         //用户自定义接收数据有效信号
    .o_uart_buadclk (o_uart_buadclk )     ,         //UART模块波特时钟，通过时钟分频得到 
    .o_uart_buadrst (o_uart_buadrst )               //UART模块波特时钟复位，通过复位产生模块得到
);

/************   initial_block   *************/

/*时钟和复位初始化*/
initial
    begin
        i_clk   = 1 ;
        i_rst   = 1 ;
        #1000
        i_rst   = 0 ;
    end 


/************   assign_block    *************/
    assign  w_tx_activate = i_user_tx_valid && o_user_tx_ready;


/************   always_block    *************/

/*时钟赋值*/
always #(CLK_PERIOD/2) i_clk = ~i_clk ;

/*发送数据赋值*/
always@(posedge o_uart_buadclk or posedge o_uart_buadrst)
    begin
        if(o_uart_buadrst)
            begin
                i_user_tx_data <= 'd0;
            end
        else if(w_tx_activate)
            begin
                i_user_tx_data <= i_user_tx_data + 1 ;
            end
        else
            begin
                i_user_tx_data <= i_user_tx_data ;
            end 
    end

/*数据发送有效信号*/
always@(posedge o_uart_buadclk or posedge o_uart_buadrst)
    begin
        if(o_uart_buadrst)
            begin
                i_user_tx_valid <= 'd0;
            end
        else if(w_tx_activate)              //用户发送激活信号拉高，就说明发送的数据已经有效了
            begin
                i_user_tx_valid <= 'd0;
            end
        else if(o_user_tx_ready)            //tx准备信号拉高就说明，此时可以发送有效的数据了
            begin
                i_user_tx_valid <= 'd1;
            end
        else
            begin
                i_user_tx_valid <= i_user_tx_valid ;
            end 
    end



endmodule
