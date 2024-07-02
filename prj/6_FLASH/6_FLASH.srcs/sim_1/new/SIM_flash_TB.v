`timescale 1ns / 1ns

module SIM_flash_TB();

/************ localparam_define *************/
    localparam      P_DATA_WIDTH    = 8    ;   //接发数据的位宽  
    localparam      P_OP_LEN        = 32   ;   //SPI操作数据长度，最多为指令8bit+操作地址24bit
    localparam      P_SPI_CPOL      = 0    ;   //时钟极性，即时钟信号SCLK在空闲状态下的电平值
    localparam      P_SPI_CPHA      = 0    ;   //时钟相位，即时钟信号SCLK在结束空闲状态后第几个边沿(包括上升和下降)采集数据

/************   wire_define     *************/
    wire    w_spi_clk   ;
    wire    w_spi_cs    ;
    wire    w_spi_mosi  ;
    wire    w_spi_miso  ;
    wire    WPn         ;
    wire    HOLDn       ;



/************   reg_define      *************/
    reg     clk;

/***********   other function    ************/
    pullup(w_spi_mosi   );
    pullup(w_spi_miso   );
    pullup(WPn          );
    pullup(HOLDn        );



/************   instantiation   *************/
spi_test_top
#(
    .P_DATA_WIDTH   (P_DATA_WIDTH),   //接发数据的位宽  
    .P_OP_LEN       (P_OP_LEN    ),   //SPI操作数据长度，最多为指令8bit+操作地址24bit
    .P_SPI_CPOL     (P_SPI_CPOL  ),   //时钟极性，即时钟信号SCLK在空闲状态下的电平值
    .P_SPI_CPHA     (P_SPI_CPHA  )    //时钟相位，即时钟信号SCLK在结束空闲状态后第几个边沿(包括上升和下降)采集数据
)
u0_spi_test_top
(
    .i_clk          (clk     )          , 
    .o_spi_clk      (w_spi_clk )          ,   //SPI时钟，由主设备(FPGA)产生
    .o_spi_cs       (w_spi_cs  )          ,   //SPI片选信号，由主设备(FPGA)控制，低电平有效
    .o_spi_mosi     (w_spi_mosi)          ,   //SPI主设备数据输出，master output slave input
    .i_spi_miso     (w_spi_miso)              //SPI从设备数据输入，master input slave output       
);


W25Q128JVxIM    u1_W25Q128JVxIM 
(
    .CSn                 (w_spi_cs   ), 
    .CLK                 (w_spi_clk  ),  
    .DIO                 (w_spi_mosi ),  //inout 
    .DO                  (w_spi_miso ),  //inout 
    .WPn                 (WPn        ),  //inout 
    .HOLDn               (HOLDn      )   //inout     
);



/************   initial_block   *************/
    initial
        begin
            clk = 1;
        end 


/************   always_block    *************/
    always #10 clk = ~clk;


endmodule
