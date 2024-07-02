/*UART驱动模块*/
module uart_drive
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
    output  wire                                    o_uart_tx           ,       //UART向外部发送端

    input   wire    [P_UART_DATA_WIDTH - 1 : 0]     i_user_tx_data      ,       //用户自定义发送数据，传给驱动模块，之后发送给外部的数据
    input   wire                                    i_user_tx_valid     ,       //用户自定义发送数据有效信号
    output  wire                                    o_user_tx_ready     ,       //用户自定义发送数据准备信号

    output  wire    [P_UART_DATA_WIDTH - 1 : 0]     o_user_rx_data      ,       //用户自定义接收数据，从驱动模块反馈，向外部反馈接收的数据
    output  wire                                    o_user_rx_valid     ,       //用户自定义接收数据有效信号

    output  wire                                    o_uart_buadclk      ,       //UART模块波特时钟，通过时钟分频得到   
    output  wire                                    o_uart_buadrst              //UART模块波特时钟复位，通过复位产生模块得到

);

/************ localparam_define *************/
    localparam  P_CLK_DIV_CNT = P_SYS_CLK / P_UART_BUADRATE;    //波特率时钟分频系数


/************   wire_define     *************/
    wire                                    w_uart_buadclk_tx       ;   //TX模块的波特时钟
    wire                                    w_uart_tx_rst           ;   //TX模块的波特时钟复位

    wire                                    w_uart_buadclk_rx       ;   //RX模块的波特时钟

    wire                                    w_uart_rx_valid         ;   //RX模块接收有效信号，该信号是连接RX模块的valid，而不是uart_drive的valid
    wire    [P_UART_DATA_WIDTH - 1 : 0]     w_uart_rx_data          ;   //RX模块接收数据，该信号是连接RX模块的rx_data，而不是uart_drive的rx_data




/************   reg_define      *************/
    reg                                     r_uart_rx_rst               ;   //RX模块的复位信号，当检测到起始位的下降沿时
                                                                            //产生复位信号，使分频模块产生RX的波特时钟
                                                                            //保证每次RX的波特时钟上升沿能采样到接收到的数据中心(稳定的位置)

    reg     [2:0]                           r_uart_rx_overvsampling     ;   //RX过采样信号，在输入时钟i_clk(比如50M)下，对RX线进行过采样
                                                                            //采样次数为3，主要目的找出起始位的下降沿
                                                                            //找到下降沿之后对RX的时钟分频模块复位，产生RX的波特时钟

    reg     [2:0]                           r_uart_rx_overvsampling_d1  ;   //过采样数据慢一拍

    reg                                     r_uart_rx_over_lock         ;   //对过采样信号进行锁定，1锁定/0解除锁定，当过采样采集到下降沿的时候进行锁定，不再过采集信号
                                                                            //当接收完一帧数据就重新将锁打开

    //因为TX和RX模块的波特时钟差别不大，在uart这种低速传输过程中允许误差
    //要将RX的信号同步到TX一个时钟域，就只需要使RX信号在TX的时钟域内打两拍
    reg                                     ro_user_rx_valid            ;   //RX接收有效信号打一拍，采集RX有效信号的上升沿
                                                                            //从而确定一帧数据接收完成，从而解除过采样的锁定

    reg                                     ro_user_rx_valid_d1         ;   //从例化的RX模块取出来，RX接收有效打一拍，最后同步到uart_drive的o_user_rx_valid上
                                                                            //与TX于同一时钟域o_uart_buadclk下

    reg                                     ro_user_rx_valid_d2         ;   //从例化的RX模块取出来，RX接收有效打两拍，最后同步到uart_drive的o_user_rx_valid上
                                                                            //与TX于同一时钟域o_uart_buadclk下

    reg     [P_UART_DATA_WIDTH - 1 : 0]     r_uart_rx_data_d1           ;   //RX模块接收数据打一拍，与TX于同一时钟域o_uart_buadclk下
    reg     [P_UART_DATA_WIDTH - 1 : 0]     r_uart_rx_data_d2           ;   //RX模块接收数据打两拍，与TX于同一时钟域o_uart_buadclk下
 



/************   assign_block    *************/
    assign  o_uart_buadclk  =   w_uart_buadclk_tx       ;
    assign  o_uart_buadrst  =   w_uart_tx_rst           ;

    assign  o_user_rx_valid =   ro_user_rx_valid_d2     ;
    assign  o_user_rx_data  =   r_uart_rx_data_d2       ;


/************   instantiation   *************/

/*TX时钟分频模块*/
clk_div
#(
    .P_CLK_DIV_CNT      (P_CLK_DIV_CNT          )                       //分频系数，最大为65535
)
u0_clk_div_tx
(
    .i_clk              (i_clk                  )               ,   
    .i_rst              (w_uart_tx_rst          )               ,   
    .o_clk_div          (w_uart_buadclk_tx      )                      //分频后的时钟
);


/*RX时钟分频模块*/
clk_div
#(
    .P_CLK_DIV_CNT      (P_CLK_DIV_CNT          )                       //分频系数，最大为65535
)
u1_clk_div_rx
(
    .i_clk              (i_clk                  )               ,   
    .i_rst              (r_uart_rx_rst          )               ,   
    .o_clk_div          (w_uart_buadclk_rx      )                       //分频后的时钟
);


/*TX复位产生模块*/
rst_gen
#(
    .P_RST_CYCLE        (2                      )                      // 复位保持周期
)
u2_rst_gen
(
    .i_clk              (i_clk                  )              ,               
    .o_rst              (w_uart_tx_rst          )                                   
);


/*UART接收模块*/
uart_rx
#(
    .P_SYS_CLK              (P_SYS_CLK          )       ,       //系统时钟频率
    .P_UART_BUADRATE        (P_UART_BUADRATE    )       ,       //UART波特率
    .P_UART_DATA_WIDTH      (P_UART_DATA_WIDTH  )       ,       //UART数据位宽
    .P_UART_STOP_BITS       (P_UART_STOP_BITS   )       ,       //UART停止位,一般为1bit或者2bit
    .P_UART_CHECK           (P_UART_CHECK       )               //UART校验位，0无校验，1是奇校验，2是偶校验
)
u3_uart_rx
(
    .i_clk                  (w_uart_buadclk_rx  )       ,
    .i_rst                  (r_uart_rx_rst      )       ,

    .i_uart_rx              (i_uart_rx          )       ,       //UART从外部接收端

    .o_user_rx_data         (w_uart_rx_data     )       ,       //用户自定义接收数据，从驱动模块反馈，向外部反馈接收的数据
    .o_user_rx_valid        (w_uart_rx_valid    )               //用户自定义接收数据有效信号
);


/*UART发送模块*/
uart_tx
#(
    .P_SYS_CLK              (P_SYS_CLK          )       ,       //系统时钟频率
    .P_UART_BUADRATE        (P_UART_BUADRATE    )       ,       //UART波特率
    .P_UART_DATA_WIDTH      (P_UART_DATA_WIDTH  )       ,       //UART数据位宽
    .P_UART_STOP_BITS       (P_UART_STOP_BITS   )       ,       //UART停止位,一般为1bit或者2bit
    .P_UART_CHECK           (P_UART_CHECK       )               //UART校验位，0无校验，1是奇校验，2是偶校验
)
u4_uart_tx
(
    .i_clk                  (w_uart_buadclk_tx      )       ,
    .i_rst                  (w_uart_tx_rst          )        ,

    .o_uart_tx              (o_uart_tx              )       ,       //UART向外部发送端

    .i_user_tx_data         (i_user_tx_data         )       ,       //用户自定义发送数据，传给驱动模块，之后发送给外部的数据
    .i_user_tx_valid        (i_user_tx_valid        )       ,       //用户自定义发送数据有效信号
    .o_user_tx_ready        (o_user_tx_ready        )               //用户自定义发送数据准备信号
);


/************   always_block    *************/

/*对RX进行过采样*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_uart_rx_overvsampling <= 3'b111;  //RX初始位前时拉高的，因为要对RX连续采集三个点，初始值为3'b111
                                                    //如果后一次采样数据为000，而前一次采样数据不为000，说明采样到了初始位的下降沿
            end
        else if(!r_uart_rx_over_lock)
            begin
                r_uart_rx_overvsampling <= {r_uart_rx_overvsampling[1:0] , i_uart_rx};  
                                                    //非锁定状态，对RX打三拍
            end
        else
            begin
                r_uart_rx_overvsampling <= 3'b111;
            end
    end


/*过采样慢一拍*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_uart_rx_overvsampling_d1 <= 3'b111;
            end
        else
            begin
                r_uart_rx_overvsampling_d1 <= r_uart_rx_overvsampling;
            end 
    end


/*过采样锁定*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_uart_rx_over_lock <= 'd0;
            end
        else if((~o_user_rx_valid) && (ro_user_rx_valid))
            begin
                r_uart_rx_over_lock <= 'd0;     //检测到接收数据有效信号的下降沿后，解除过采样的锁定
            end
        else if((r_uart_rx_overvsampling == 3'b000) && (r_uart_rx_overvsampling_d1 != 3'b000))
            begin
                r_uart_rx_over_lock <= 'd1;     //检测到RX初始位的下降沿后，锁定过采样
            end 
        else
            begin
                r_uart_rx_over_lock <= r_uart_rx_over_lock;
            end
    end


/*RX接收有效信号打一拍*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_user_rx_valid <= 'd0;
            end
        else
            begin
                ro_user_rx_valid <= o_user_rx_valid  ;
            end 
    end

/*产生RX模块的复位信号，从而产生RX数据采样的波特时钟*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_uart_rx_rst <= 'd1;
            end
        else if((~o_user_rx_valid) && (ro_user_rx_valid))
            begin
                r_uart_rx_rst <= 'd1;       //接收数据有效下降沿，就将复位恢复到原始状态
            end
        else if((r_uart_rx_overvsampling == 3'b000) && (r_uart_rx_overvsampling_d1 != 3'b000))
            begin
                r_uart_rx_rst <= 'd0;       //检测到RX初始位的下降沿后，复位RX模块
            end
        else
            begin
                r_uart_rx_rst <= r_uart_rx_rst;
            end
    end  


/*将RX模块的valid和rx_data同步到uart_drive的时钟域o_uart_buadclk下*/
always@(posedge o_uart_buadclk or posedge o_uart_buadrst)
    begin
        if(o_uart_buadrst)
            begin
                ro_user_rx_valid_d1 <= 'd0;
                ro_user_rx_valid_d2 <= 'd0;

                r_uart_rx_data_d1   <= 'd0;
                r_uart_rx_data_d2   <= 'd0;
            end
        else
            begin
                ro_user_rx_valid_d1 <= w_uart_rx_valid      ;
                ro_user_rx_valid_d2 <= ro_user_rx_valid_d1  ;

                r_uart_rx_data_d1   <= w_uart_rx_data       ;
                r_uart_rx_data_d2   <= r_uart_rx_data_d1    ;
            end 
    end

endmodule 