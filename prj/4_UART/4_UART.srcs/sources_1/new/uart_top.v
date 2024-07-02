/*UART顶层模块*/
module uart_top
#(
    parameter       P_SYS_CLK           =   50_000_000  ,   //系统时钟频率
    parameter       P_UART_BUADRATE     =   115200      ,   //UART波特率
    parameter       P_UART_DATA_WIDTH   =   8           ,   //UART数据位宽
    parameter       P_UART_STOP_BITS    =   1           ,   //UART停止位,一般为1bit或者2bit
    parameter       P_UART_CHECK        =   1               //UART校验位，0无校验，1是奇校验，2是偶校验
)
(
    input   wire    i_clk       ,
    input   wire    i_uart_rx   ,
    output  wire    o_uart_tx
);

/************   wire_define     *************/
    wire                                    w_clk_50MHz         ;   //过一级PLL的晶振时钟
    wire                                    w_clk_rst           ;   //对应板子上低电平复位
    wire                                    w_sys_pll_locked    ;   //PLL锁相信号
    wire                                    w_uart_buadclk      ;   //UART模块波特时钟，通过时钟分频得到
    wire                                    w_uart_buadrst      ;   //UART模块波特时钟复位，通过复位产生模块得到


    wire    [P_UART_DATA_WIDTH - 1 : 0]     w_user_tx_data      ;   //用户自定义发送数据，传给驱动模块，之后发送给外部的数据  

    wire                                    w_user_tx_ready     ;   //用户自定义发送数据准备信号
    wire    [P_UART_DATA_WIDTH - 1 : 0]     w_user_rx_data      ;   //用户自定义接收数据，从驱动模块反馈，向外部反馈接收的数据
    wire                                    w_user_rx_valid     ;   //用户自定义接收数据有效信号

    wire                                    w_fifo_full         ;   //fifo写满信号，1满/0不满
    wire                                    w_fifo_empty        ;   //fifo读空信号，1空/0非空

/************   reg_define      *************/
    reg                                     r_user_tx_valid     ;   //用户自定义发送数据有效信号
    reg                                     r_fifo_rd_en        ;   //fifo读使能信号
    reg                                     r_fifo_rd_en_lock   ;   //fifo读使能信号锁定在一个时钟周期内，防止丢失数据；1锁定/0解锁

    reg                                     r_user_tx_ready     ;   //TX的ready信号打一拍



/************   instantiation   *************/

/*板子上的晶振传入FPGA内部要过一级晶振*/
sys_pll     u0_sys_pll
(
    .clk_out1   (w_clk_50MHz        ),     
    .locked     (w_sys_pll_locked   ),       //信号不稳定为低电平；信号稳定之后，锁相信号拉高，先低后高，低电平复位
    .clk_in1    (i_clk              )      
);

/*UART驱动模块*/
uart_drive
#(
    .P_SYS_CLK           (P_SYS_CLK        )  ,     //系统时钟频率
    .P_UART_BUADRATE     (P_UART_BUADRATE  )  ,     //UART波特率
    .P_UART_DATA_WIDTH   (P_UART_DATA_WIDTH)  ,     //UART数据位宽
    .P_UART_STOP_BITS    (P_UART_STOP_BITS )  ,     //UART停止位,一般为1bit或者2bit
    .P_UART_CHECK        (P_UART_CHECK     )        //UART校验位，0无校验，1是奇校验，2是偶校验
)
u1_uart_drive
(
    .i_clk          (w_clk_50MHz    )     ,
    .i_rst          (w_clk_rst      )     ,

    .i_uart_rx      (i_uart_rx      )     ,         //UART从外部接收端
    .o_uart_tx      (o_uart_tx      )     ,         //UART向外部发送端

    .i_user_tx_data (w_user_tx_data )     ,         //用户自定义发送数据，传给驱动模块，之后发送给外部的数据
    .i_user_tx_valid(r_user_tx_valid)     ,         //用户自定义发送数据有效信号
    .o_user_tx_ready(w_user_tx_ready)     ,         //用户自定义发送数据准备信号

    .o_user_rx_data (w_user_rx_data )     ,         //用户自定义接收数据，从驱动模块反馈，向外部反馈接收的数据
    .o_user_rx_valid(w_user_rx_valid)     ,         //用户自定义接收数据有效信号
    .o_uart_buadclk (w_uart_buadclk )     ,         //UART模块波特时钟，通过时钟分频得到 
    .o_uart_buadrst (w_uart_buadrst )               //UART模块波特时钟复位，通过复位产生模块得到

);

/*用fifo对uart通信的数据进行缓存*/
uart_fifo_8x1024    u2_uart_fifo_8x1024 
(
  .clk      (w_uart_buadclk     ),      // 驱动fifo的时钟要与UART的波特时钟保持一致
  .srst     (w_uart_buadrst     ),      // 驱动fifo的复位要与UART的波特时钟保持一致
  .din      (w_user_rx_data     ),      // uart接收的数据传给fifo缓存，到时候通过TX向外部发送
  .wr_en    (w_user_rx_valid    ),      // fifo写使能，为高就代表当前写入的数据有效，接收的数据传入fifo相当于将数据写入fifo
  .rd_en    (r_fifo_rd_en       ),      // fifo读使能
  .dout     (w_user_tx_data     ),      // uart要发送的数据，先存入fifo，到时候通过dout将数据传出来
  .full     (w_fifo_full        ),      //fifo写满信号
  .empty    (w_fifo_empty       )       //fifo读空信号
);


/************   assign_block    *************/
    assign      w_clk_rst       = ~w_sys_pll_locked ;

/************   always_block    *************/

/*TX的ready信号打一拍*/ 
always@(posedge w_uart_buadclk or posedge w_uart_buadrst)
    begin
        if(w_uart_buadrst)
            begin
                r_user_tx_ready <= 'd0;
            end
        else
            begin
                r_user_tx_ready <= w_user_tx_ready;
            end
    end


/*fifo读使能*/
always@(posedge w_uart_buadclk or posedge w_uart_buadrst)
    begin
        if(w_uart_buadrst)
            begin
                r_fifo_rd_en <= 1'b0;
            end
        else if((~w_fifo_empty) && (w_user_tx_ready) && (~r_fifo_rd_en_lock))   //这样可以保证读使能只为一个周期
            begin
                r_fifo_rd_en <= 1'b1;   //当fifo不为空，而且uart的TX端已经做好了发送数据的准备，就将读使能拉高，
                                        //让fifo中缓存的数据被读出，传入到uart_drive，之后由TX将数据发送出去
            end
        else
            begin
                r_fifo_rd_en <= 1'b0;
            end 
    end


/*fifo读使能信号锁定*/
always@(posedge w_uart_buadclk or posedge w_uart_buadrst)
    begin
        if(w_uart_buadrst)
            begin
                r_fifo_rd_en_lock <= 1'b0;
            end
        else if((~w_fifo_empty) && (w_user_tx_ready))
            begin
                r_fifo_rd_en_lock <= 1'b1;      //这两个条件满足，lock一直为高，这样可以保证读使能只为一个周期
            end
        else if((~r_user_tx_ready) && (w_user_tx_ready))
            begin
                r_fifo_rd_en_lock <= 1'b0;      //当检测到tx_ready的上升沿，即已经发送完了一个数据，等待下一个数据发送时，将lock拉低
            end
        else
            begin
                r_fifo_rd_en_lock <= r_fifo_rd_en_lock;
            end
    end


/*fifo写使能，r_user_tx_valid作为fifo写使能，比r_fifo_rd_en慢一拍，先读后写*/
always@(posedge w_uart_buadclk or posedge w_uart_buadrst)
    begin
        if(w_uart_buadrst)
            begin
                r_user_tx_valid <= 1'b0;
            end
        else
            begin
                r_user_tx_valid <= r_fifo_rd_en;    //r_user_tx_valid比读使能r_fifo_rd_en慢一拍
                                                    //先读出fifo的数据，再写入
            end
    end



endmodule
