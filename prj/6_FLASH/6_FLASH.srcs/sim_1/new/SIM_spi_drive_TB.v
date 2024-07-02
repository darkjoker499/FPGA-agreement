`timescale 1ns / 1ns

module SIM_spi_drive_TB();

/************ localparam_define *************/
    localparam  P_DATA_WIDTH    = 8    ;   //接发数据的位宽  
    localparam  P_OP_LEN        = 32   ;   //SPI操作数据长度，最多为指令8bit+操作地址24bit
    localparam  P_SPI_CPOL      = 0    ;   //时钟极性，即时钟信号SCLK在空闲状态下的电平值
    localparam  P_SPI_CPHA      = 0    ;   //时钟相位，即时钟信号SCLK在结束空闲状态后第几个边沿(包括上升和下降)采集数据


    localparam  P_OP_TYPE_INS   =   0 ;     //其他指令类型
    localparam  P_OP_TYPE_READ  =   1 ;     //读指令
    localparam  P_OP_TYPE_WRITE =   2 ;     //写指令

    /*状态机*/
    localparam  P_STATE_IDLE     =   0 ;     //空闲状态
    localparam  P_STATE_BUSY     =   1 ;     //忙状态
    localparam  P_STATE_WRITE    =   2 ;     //写状态
    localparam  P_STATE_READ     =   3 ;     //读状态



/************   wire_define     *************/
    wire                                w_spi_clk           ;        
    wire                                w_spi_cs            ;          
    wire                                w_spi_mosi          ;  
    wire                                w_spi_miso          ;      
    wire                                w_user_ready        ;            
    wire                                w_user_write_req    ;        
    wire    [P_DATA_WIDTH - 1 :0]       w_user_read_data    ;        
    wire                                w_user_read_valid   ;
    wire                                w_user_activate     ;  //用户激活信号，当valid和ready同时为高时，握手成功表示成功激活SPI接发      
    wire                                WPn                 ;  //FLASH仿真模型的写保护，低电平有效 
    wire                                HOLDn               ;  //FLAHS仿真模型的保持，低电平有效 



/************   reg_define      *************/
    reg                                 i_clk               ;
    reg                                 i_rst               ;
    reg     [P_OP_LEN - 1 : 0]          r_user_op_data      ;
    reg     [1:0]                       r_user_op_type      ;
    reg     [15:0]                      r_user_op_len       ;
    reg     [15:0]                      r_user_sclk_len     ;
    reg                                 r_user_valid        ;
    reg     [P_DATA_WIDTH - 1 :0]       r_user_write_data   ;

    /*状态机*/
    reg     [3:0]                       r_current_state     ;
    reg     [3:0]                       r_next_state        ;
  


/************   instantiation   *************/
spi_drive
#(
    .P_DATA_WIDTH(P_DATA_WIDTH),   //接发数据的位宽  
    .P_OP_LEN    (P_OP_LEN    ),   //SPI操作数据长度，最多为指令8bit+操作地址24bit
    .P_SPI_CPOL  (P_SPI_CPOL  ),   //时钟极性，即时钟信号SCLK在空闲状态下的电平值
    .P_SPI_CPHA  (P_SPI_CPHA  )    //时钟相位，即时钟信号SCLK在结束空闲状态后第几个边沿(包括上升和下降)采集数据
)
u0_spi_drive
(
    .i_clk              (i_clk            )   ,
    .i_rst              (i_rst            )   ,

    .o_spi_clk          (w_spi_clk        )   ,   //SPI时钟，由主设备(FPGA)产生
    .o_spi_cs           (w_spi_cs         )   ,   //SPI片选信号，由主设备(FPGA)控制，低电平有效
    .o_spi_mosi         (w_spi_mosi       )   ,   //SPI主设备数据输出，master output slave input
    .i_spi_miso         (w_spi_miso       )   ,   //SPI从设备数据输入，master input slave output

    .i_user_op_data     (r_user_op_data   )   ,   //spi操作数据，最多为指令8bit+操作地址24bit；比如读FLASH数据指令，操作数据包括03h的指令(8bit)，以及24bit的地址
    .i_user_op_type     (r_user_op_type   )   ,   //spi操作类型，其他指令 0 、读 1 、写 2
    .i_user_op_len      (r_user_op_len    )   ,   //spi操作数据长度，32bit或者8bit
    .i_user_sclk_len    (r_user_sclk_len  )   ,   //spi时钟周期，有些指令需要更长的SCLK周期才能操作完成    

    .i_user_valid       (r_user_valid     )   ,   //从机有效信号
    .o_user_ready       (w_user_ready     )   ,   //主机就绪信号

    .i_user_write_data  (r_user_write_data)   ,   //写入FLASH的数据       
    .o_user_write_req   (w_user_write_req )   ,   //写数据进FLASH的请求   

    .o_user_read_data   (w_user_read_data )   ,   //从FLASH读出的数据      
    .o_user_read_valid  (w_user_read_valid)       //FLASH读数据有效       

);

W25Q128JVxIM    u1_W25Q128JVxIM 
(
    CSn                 (w_spi_cs   ), 
    CLK                 (w_spi_clk  ),  
    DIO                 (w_spi_mosi ),  //inout 
    DO                  (w_spi_miso ),  //inout 
    WPn                 (1          ),  //inout 
    HOLDn               (1          )   //inout     
);


/***********   other function    ************/
    pullup(w_spi_mosi   );
    pullup(w_spi_miso   );
    pullup(WPn          );
    pullup(HOLDn        );


/************   assign_block    *************/
assign  w_user_activate = r_user_valid && w_user_ready;



/************   initial_block   *************/
initial
    begin
        i_clk = 1;
        i_rst = 1;
        #100
        @(posedge i_clk)i_rst = 0;
    end 

/************   always_block    *************/

/*时钟*/
always #10 i_clk = ~i_clk;

/*拉高valid*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_user_valid <= 0;
            end
        else if(w_user_ready)
            begin
                r_user_valid <= 1;
            end
        else
            begin
                r_user_valid <= 'd0;
            end 
    end


/*spi相关配置数据过一拍*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_user_op_data  <= 'd0;
                r_user_op_type  <= 'd0;
                r_user_op_len   <= 'd0;
                r_user_sclk_len <= 'd0;
            end
        else if(w_user_ready)
            begin
                r_user_op_data  <= {8'ha1,8'h01,8'h02,8'h03};
                r_user_op_type  <= P_OP_TYPE_WRITE ; 
                r_user_op_len   <= 32  ; 
                r_user_sclk_len <= 32 + 24; 
            end
        else
            begin
                r_user_op_data  <= r_user_op_data ;
                r_user_op_type  <= r_user_op_type ;
                r_user_op_len   <= r_user_op_len  ;
                r_user_sclk_len <= r_user_sclk_len;
            end 
    end


/*写数据*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_user_write_data <= 'd0;
            end
        else if(w_user_write_req)
            begin
                r_user_write_data <= r_user_write_data + 3;
            end
        else
            begin
                r_user_write_data <= r_user_write_data;
            end 
    end


/*三段式状态机*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                r_current_state <= 'd0;
            end
        else
            begin
                r_current_state <= r_next_state;
            end 
    end


endmodule
