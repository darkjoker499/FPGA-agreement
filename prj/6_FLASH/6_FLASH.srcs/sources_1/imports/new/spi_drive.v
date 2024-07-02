/*SPI驱动模块*/
module spi_drive
#(
    parameter                           P_DATA_WIDTH    = 8    ,   //接发数据的位宽  
    parameter                           P_OP_LEN        = 32   ,   //SPI操作数据长度，最多为指令8bit+操作地址24bit
    parameter                           P_SPI_CPOL      = 0    ,   //时钟极性，即时钟信号SCLK在空闲状态下的电平值
    parameter                           P_SPI_CPHA      = 0        //时钟相位，即时钟信号SCLK在结束空闲状态后第几个边沿(包括上升和下降)采集数据
)
(
    input                               i_clk               ,
    input                               i_rst               ,

    output                              o_spi_clk           ,   //SPI时钟，由主设备(FPGA)产生
    output                              o_spi_cs            ,   //SPI片选信号，由主设备(FPGA)控制，低电平有效
    output                              o_spi_mosi          ,   //SPI主设备数据输出，master output slave input
    input                               i_spi_miso          ,   //SPI从设备数据输入，master input slave output

    input   [P_OP_LEN - 1 : 0]          i_user_op_data      ,   //spi操作数据，最多为指令8bit+操作地址24bit；比如读FLASH数据指令，操作数据包括03h的指令(8bit)，以及24bit的地址
    input   [1:0]                       i_user_op_type      ,   //spi操作类型，其他指令 0 、读 1 、写 2
    input   [15:0]                      i_user_op_len       ,   //spi操作数据长度，32bit或者8bit
    input   [15:0]                      i_user_sclk_len     ,   //spi时钟周期，有些指令需要更长的SCLK周期才能操作完成    

    input                               i_user_valid        ,   //从机有效信号
    output                              o_user_ready        ,   //主机就绪信号

    input   [P_DATA_WIDTH - 1 :0]       i_user_write_data   ,   //写入FLASH的数据       
    output                              o_user_write_req    ,   //写数据进FLASH的请求   

    output  [P_DATA_WIDTH - 1 :0]       o_user_read_data    ,   //从FLASH读出的数据      
    output                              o_user_read_valid       //FLASH读数据有效       

);

/************ localparam_define *************/
    localparam  P_OP_TYPE_READ  =   1 ;     //读指令
    localparam  P_OP_TYPE_WRITE =   2 ;     //写指令
    localparam  P_OP_TYPE_INS   =   3 ;     //其他指令类型


/************   wire_define     *************/
    wire        w_user_activate ;           //用户激活信号，当valid和ready同时为高时，握手成功表示成功激活SPI接发


/************   reg_define      *************/
    reg                                 ro_spi_clk          ;       //SPI时钟  
    reg                                 ro_spi_cs           ;       //SPI片选信号
    reg                                 ro_spi_mosi         ;       //SPI主设备数据输出


    reg                                 ro_user_ready       ;       //设备就绪信号，0为正在SPI收发状态/1为空闲状态

    reg                                 r_spi_run           ;       //SPI运行状态，1为SPI接发/0为SPI空闲
    reg                                 r_spi_run_d1        ;       //SPI运行状态打一拍，1为SPI接发/0为SPI空闲

    reg                                 r_spi_cnt           ;       //SPI运行翻转计数器，SPI运行时，
                                                                    //1为从设备采样主设备发送的数据/0为主设备改变下一时刻要发送的数据

    reg     [15:0]                      r_cnt               ;       //SPI运行计数器，SPI接发激活后每r_spi_cnt=1计数+1


    reg     [P_OP_LEN - 1 : 0]          r_user_op_data      ;       //spi操作数据
    reg     [1:0]                       r_user_op_type      ;       //spi操作类型
    reg     [15:0]                      r_user_op_len       ;       //spi操作数据长度
    reg     [15:0]                      r_user_sclk_len     ;       //spi时钟周期


    reg     [P_DATA_WIDTH - 1 :0]       r_user_write_data   ;       //写入FLASH的数据    
    reg                                 ro_user_write_req   ;       //写数据进FLASH的请求
    reg                                 ro_user_write_req_d1;       //写数据进FLASH的请求打一拍
    reg     [15:0]                      r_write_cnt         ;       //写数据的计数器


    reg     [P_DATA_WIDTH - 1 :0]       ro_user_read_data   ;       //从FLASH读出的数据  
    reg                                 ro_user_read_valid  ;       //FLASH读数据有效 
    reg     [15:0]                      r_read_cnt          ;       //读数据的计数器


/************   assign_block    *************/
    assign      o_spi_clk           =   ro_spi_clk                      ;
    assign      o_spi_cs            =   ro_spi_cs                       ;
    assign      o_spi_mosi          =   ro_spi_mosi                     ;
    assign      o_user_ready        =   ro_user_ready                   ;

    assign      o_user_read_data    =   ro_user_read_data               ;
    assign      o_user_read_valid   =   ro_user_read_valid              ;

    assign      o_user_write_req    =   ro_user_write_req               ;

    assign      w_user_activate     =   i_user_valid & ro_user_ready    ;


/************   always_block    *************/

/*主机准备信号*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_user_ready <= 1'b1;
            end
        else if(w_user_activate)
            begin
                ro_user_ready <= 1'b0;  //握手成功，进行SPI接发，此时ready信号拉低
            end
        else if((~r_spi_run) && (r_spi_run_d1))
            begin
                ro_user_ready <= 1'b1;  //检测到run信号下降沿，说明SPI收发结束，将ready信号重新拉高
            end
        else
            begin
                ro_user_ready <= ro_user_ready  ;  //保持ready信号不变
            end 
    end


/*spi相关配置数据过一拍*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_user_op_type  <= 'd0;
                r_user_op_len   <= 'd0;
                r_user_sclk_len <= 'd0;
            end
        else if(w_user_activate)
            begin
                r_user_op_type  <= i_user_op_type ; 
                r_user_op_len   <= i_user_op_len  ; 
                r_user_sclk_len <= i_user_sclk_len; 
            end
        else
            begin
                r_user_op_type  <= r_user_op_type ;
                r_user_op_len   <= r_user_op_len  ;
                r_user_sclk_len <= r_user_sclk_len;
            end 
    end


/*spi操作数据，指令+地址*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_user_op_data <= 'd0;
            end
        else if(w_user_activate)
            begin
                r_user_op_data <= i_user_op_data;       //i_user_op_data比r_user_op_data快一拍
            end
        else if(r_spi_cnt)
            begin
                r_user_op_data <= r_user_op_data << 1;  //在r_spi_cnt为1时，操作数据左移，从MSB开始
            end
        else
            begin
                r_user_op_data <= r_user_op_data;
            end 
    end




/*SPI运行状态*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_spi_run <= 'd0;
            end
        else if(w_user_activate)
            begin
                r_spi_run <= 'd1;   //握手成功了，就开始进行SPI的接发
            end
        else if((r_spi_cnt == 1) && (r_cnt == r_user_sclk_len - 1))
            begin
                r_spi_run <= 'd0;
            end
        else
            begin
                r_spi_run <= r_spi_run  ;
            end 
    end

/*SPI运行状态打一拍*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_spi_run_d1 <= 'd0;
            end
        else
            begin
                r_spi_run_d1 <= r_spi_run;
            end 
    end


/*SPI运行翻转计数器*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_spi_cnt <= 'd0;
            end
        /*else if((r_spi_cnt == 1) && (r_cnt == r_user_sclk_len - 1))
            begin
                r_spi_cnt <= 'd0;               //SPI收发结束，就清零，等待下一次收发
            end*/
        else if(r_spi_run)
            begin
                r_spi_cnt <= r_spi_cnt + 1'b1;  //SPI处于收发状态，+1溢出就不断在0、1之间变换
            end
        else
            begin
                r_spi_cnt <= 'd0;
            end 
    end


/*SPI计数器*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_cnt <= 'd0;
            end
        else if((r_cnt == r_user_sclk_len - 1)  && (r_spi_cnt))
            begin
                r_cnt <= 'd0;
            end
        else if(r_spi_cnt)
            begin
                r_cnt <= r_cnt + 1'b1;   //SPI处于收发状态，r_spi_cnt为1时，r_cnt+1
            end
        else
            begin
                r_cnt <= r_cnt ;
            end
    end


/*产生SPI CLK*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_spi_clk <= P_SPI_CPOL;       //时钟空闲的时候电平值为CPOL
            end
        else if(r_spi_run)
            begin
                ro_spi_clk <= ~ro_spi_clk;      //SPI处于收发状态，时钟翻转
            end
        else
            begin
                ro_spi_clk <= P_SPI_CPOL;       //时钟空闲的时候电平值为CPOL
            end 
    end


/*SPI片选*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_spi_cs <= 'd1;
            end
        else if(w_user_activate)
            begin
                ro_spi_cs <= 'd0;   //片选信号在SPI处于收发状态时为低电平
            end
        else if(!r_spi_run)
            begin
                ro_spi_cs <= 'd1;   //SPI处于空闲状态时片选信号为高电平
            end
        else
            begin
                ro_spi_cs <= ro_spi_cs;
            end 
    end


/*SPI数据输出 MOSI*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_spi_mosi <= 'd0;
            end
        else if(w_user_activate)
            begin
                ro_spi_mosi <= i_user_op_data[P_OP_LEN - 1];    //SPI刚激活时，先输出操作数据的MSB
            end
        else if((r_spi_cnt) && (r_cnt < r_user_op_len - 1))
            begin
                ro_spi_mosi <= r_user_op_data[P_OP_LEN - 2];    //SPI运行之后，r_cnt小于r_user_op_len时，mosi输出操作数据;-2是因为比i_user_op_data慢一拍
            end
        else if((r_spi_cnt) && (r_user_op_type == P_OP_TYPE_WRITE))
            begin
                ro_spi_mosi <= r_user_write_data[P_DATA_WIDTH - 1]; //SPI运行之后，如果该次为写操作，在上一步发送完成写指令后，开始向从设备写入数据，从数据MSB开始写入
            end
        else
            begin
                ro_spi_mosi <= ro_spi_mosi;
            end
    end


/*spi写数据请求*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_user_write_req <= 'd0;
            end
        else if(r_cnt >= r_user_sclk_len - 5)
            begin
                ro_user_write_req <= 'd0;   //本次传输SCLK时钟准备输出完前，将写请求拉低
            end
        else if(((!r_spi_cnt) && (r_cnt == 30) || (r_write_cnt==15) ) && (r_user_op_type == P_OP_TYPE_WRITE) )
            begin
                ro_user_write_req <= 'd1;   //当输入完8bit操作指令和24bit数据，即32-1=31，提前一拍操作
                                            //且当前操作指令为写入数据操作时，拉高写请求，将数据写入从设备
            end
        else
            begin
                ro_user_write_req <= 'd0;
            end 
    end


/*写请求数据打一拍*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_user_write_req_d1 <= 'd0;
            end
        else
            begin
                ro_user_write_req_d1 <= ro_user_write_req;
            end 
    end


/*写向从设备的数据变化*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_user_write_data <= 'd0;
            end
        else if(ro_user_write_req_d1)
            begin
                r_user_write_data <= i_user_write_data; //打一拍的写请求信号拉高后，开始读入要写进从设备的数据
            end
        else if(r_spi_cnt)
            begin
                r_user_write_data <= r_user_write_data << 1;    //左移，每次取出数据的MSB，即SCLK的上升沿
            end
        else
            begin
                r_user_write_data <= r_user_write_data;
            end 
    end


/*写数据寄存器*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_write_cnt <= 'd0;
            end
        else if((ro_spi_cs) || (r_write_cnt == 15))
            begin
                r_write_cnt <= 'd0;     //片选拉高了就将计数器清零;15的原因是主clk为sclk的两倍，
                                        //所以以主clk为主，当计数满15，对于sclk就正好写入8bit (1byte)的数据
            end
        else if((ro_user_write_req) || (r_write_cnt))
            begin
                r_write_cnt <= r_write_cnt + 1; //写请求激活之后，或者正在写入状态过程将计数器加1
            end
        else
            begin
                r_write_cnt <= r_write_cnt;
            end 
    end


/*数据接收有效信号*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ro_user_read_valid <= 'd0;
            end
        else if((r_read_cnt == P_DATA_WIDTH - 1) && (r_spi_cnt) && (r_user_op_type == P_OP_TYPE_READ))
            begin
                ro_user_read_valid <= 'd1;
            end
        else
            begin
                ro_user_read_valid <= 'd0;
            end 
    end


/*接收从机信号*/
always@(posedge ro_spi_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
               ro_user_read_data <= 'd0; 
            end
        else if((r_cnt >= r_user_op_len - 1) && (r_user_op_type == P_OP_TYPE_READ))
            begin
                ro_user_read_data <= {ro_user_read_data[P_DATA_WIDTH - 2:0], i_spi_miso}; 
                            //读取完指令和地址之后，读数据先读高位，所以这样写一步步把数据挤过去
            end 
        else
            begin
                ro_user_read_data <= ro_user_read_data;
            end
    end


/*读计数器*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_read_cnt <= 'd0;
            end
        else if((r_read_cnt == P_DATA_WIDTH) || (ro_spi_cs))
            begin
                r_read_cnt <= 'd0;  //读数据期间或者片选拉高，读完一个字节的数据之后清零
            end
        else if((r_cnt >= r_user_op_len) && (r_spi_cnt) && (r_user_op_type == P_OP_TYPE_READ))
            begin
                r_read_cnt <= r_read_cnt + 1;   //当发送完读数据指令和地址之后开始读数据计数
            end
        else
            begin
                r_read_cnt <= r_read_cnt; 
            end
    end

endmodule
