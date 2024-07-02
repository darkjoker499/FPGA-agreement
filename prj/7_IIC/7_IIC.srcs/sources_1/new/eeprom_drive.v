/*EEPROM驱动模块*/
module eeprom_drive
(
    input                   i_clk               ,
    input                   i_rst               ,

    /*EEPROM ctrl interface*/
    input   [2:0]           i_ctrl_eeprom_addr  ,   //EEPROM器件地址组成为7'b1010_xxx,xxx根据PCB硬件设计决定
    input   [15:0]          i_ctrl_op_addr      ,   //EEPROM操作地址
    input                   i_ctrl_addr_ctrl    ,   //EEPROM操作地址控制，0表示操作地址为8bit，1表示操作地址为16bit
    input   [1:0]           i_ctrl_op_type      ,   //EEPROM操作类型，页写0、顺序读1、随机读2
    input   [7:0]           i_ctrl_op_byte_num  ,   //EEPROM操作的字节数
    input                   i_ctrl_eeprom_valid ,   //EEPROM操作有效
    output                  o_ctrl_eeprom_ready ,   //EEPROM操作准备
    input   [7:0]           i_ctrl_write_data   ,   //EEPROM写入数据
    input                   i_ctrl_write_sop    ,   //EEPRM写入数据开始
    input                   i_ctrl_write_eop    ,   //EEPRM写入数据
    input                   i_ctrl_write_valid  ,   //EEPRM写入数据有效

    output  [7:0]           o_ctrl_read_data    ,   //EEPROM读出数据
    output                  o_ctrl_read_valid   ,   //EEPRM读出数据有效

    /*IIC interface*/
    inout                   io_iic_sda      ,   //IIC的数据线，输入、输出、高阻态
    output                  o_iic_scl           //IIC时钟线                     
);


/************   wire_define     *************/
    wire    [6:0]           wo_iic_device_addr   ;   //IIC从机设备的器件地址  
    wire                    wo_iic_addr_ctrl     ;   //IIC从机设备操作地址控制，0表示操作地址为8bit，1表示操作地址为16bit   
    wire    [15:0]          wo_iic_addr          ;   //IIC从机的操作地址,有些从机设备包括两个器件地址          
    wire    [7:0]           wo_iic_byte_num      ;   //IIC从机操作的字节数                                       
    wire    [1:0]           wo_iic_type          ;   //IIC从机本次操作的类型，页写0、顺序读1、随机读2                       
    wire                    wo_iic_valid         ;   //IIC操作有效                                                          
    wire                    wi_iic_ready         ;   //IIC操作准备 
    wire                    wi_iic_virtual_write ;   //随机读过程，完成虚拟写标志
    wire    [7:0]           wo_iic_write_data    ;   //IIC写入从机的数据                        
    wire                    wi_iic_write_req     ;   //IIC写入从机设备请求                                      
    wire    [7:0]           wi_iic_read_data     ;   //IIC读出从机的数据                                            
    wire                    wi_iic_read_valid    ;   //IIC读出从机数据有效   


/************   instantiation   *************/

/*EEPROM控制*/
eeprom_ctrl u0_eeprom_ctrl
(
    .i_clk(i_clk)               ,
    .i_rst(i_rst)               ,

    /*EEPROM ctrl interface*/
    .i_ctrl_eeprom_addr (i_ctrl_eeprom_addr ) ,   //EEPROM器件地址组成为7'b1010_xxx,xxx根据PCB硬件设计决定
    .i_ctrl_op_addr     (i_ctrl_op_addr     ) ,   //EEPROM操作地址
    .i_ctrl_addr_ctrl   (i_ctrl_addr_ctrl   ) ,   //EEPROM操作地址控制，0表示操作地址为8bit，1表示操作地址为16bit
    .i_ctrl_op_type     (i_ctrl_op_type     ) ,   //EEPROM操作类型，页写0、顺序读1、随机读2
    .i_ctrl_op_byte_num (i_ctrl_op_byte_num ) ,   //EEPROM操作的字节数
    .i_ctrl_eeprom_valid(i_ctrl_eeprom_valid) ,   //EEPROM操作有效
    .o_ctrl_eeprom_ready(o_ctrl_eeprom_ready) ,   //EEPROM操作准备

    .i_ctrl_write_data (i_ctrl_write_data )  ,   //EEPROM写入数据
    .i_ctrl_write_sop  (i_ctrl_write_sop  )  ,   //EEPRM写入数据开始
    .i_ctrl_write_eop  (i_ctrl_write_eop  )  ,   //EEPRM写入数据
    .i_ctrl_write_valid(i_ctrl_write_valid)  ,   //EEPRM写入数据有效
                        
    .o_ctrl_read_data  (o_ctrl_read_data  )  ,   //EEPROM读出数据
    .o_ctrl_read_valid (o_ctrl_read_valid )  ,   //EEPRM读出数据有效

    /*IIC interface*/
    .o_iic_device_addr  (wo_iic_device_addr  ) ,   //IIC从机设备的器件地址  
    .o_iic_addr_ctrl    (wo_iic_addr_ctrl    ) ,   //IIC从机设备操作地址控制，0表示操作地址为8bit，1表示操作地址为16bit                                                
    .o_iic_addr         (wo_iic_addr         ) ,   //IIC从机的操作地址,有些从机设备包括两个器件地址          
    .o_iic_byte_num     (wo_iic_byte_num     ) ,   //IIC从机操作的字节数                                       
    .o_iic_type         (wo_iic_type         ) ,   //IIC从机本次操作的类型，页写0、顺序读1、随机读2                                 

    .o_iic_valid        (wo_iic_valid        ) ,   //IIC操作有效                                                                              
    .i_iic_ready        (wi_iic_ready        ) ,   //IIC操作准备 
    
    .i_iic_virtual_write(wi_iic_virtual_write) ,   //随机读过程，完成虚拟写标志

    .o_iic_write_data   (wo_iic_write_data   ) ,   //IIC写入从机的数据                        
    .i_iic_write_req    (wi_iic_write_req    ) ,   //IIC写入从机设备请求                                      

    .i_iic_read_data    (wi_iic_read_data    ) ,   //IIC读出从机的数据                                            
    .i_iic_read_valid   (wi_iic_read_valid   )     //IIC读出从机数据有效
);


/*IIC驱动*/
iic_drive   u1_iic_drive
(
    .i_clk(i_clk)               ,
    .i_rst(i_rst)               ,

    /*user interface*/
    .i_device_addr  (wo_iic_device_addr     ) ,   //从机设备的器件地址  
    .i_op_addr_ctrl (wo_iic_addr_ctrl       ) ,   //从机设备操作地址控制，0表示操作地址为8bit，1表示操作地址为16bit                                                
    .i_op_addr      (wo_iic_addr            ) ,   //从机的操作地址,有些从机设备包括两个器件地址          
    .i_op_byte_num  (wo_iic_byte_num        ) ,   //从机操作的字节数                                       
    .i_op_type      (wo_iic_type            ) ,   //从机本次操作的类型，页写0、顺序读1、随机读2                                 

    .i_op_valid     (wo_iic_valid           ) ,   //操作有效                                                                              
    .o_op_ready     (wi_iic_ready           ) ,   //操作准备                                                                              

    .i_write_data   (wo_iic_write_data      ) ,   //写入从机的数据                        
    .o_write_req    (wi_iic_write_req       ) ,   //写入从机设备请求                                      

    .o_read_data    (wi_iic_read_data       ) ,   //读出从机的数据                                            
    .o_read_valid   (wi_iic_read_valid      ) ,   //读出从机数据有效                                                      

    .o_virtual_write(wi_iic_virtual_write   ) ,   //随机读过程，完成虚拟写标志

    /*IIC interface*/
    .io_iic_sda     (io_iic_sda             ) ,   //IIC的数据线，输入、输出、高阻态
    .o_iic_scl      (o_iic_scl              )     //IIC时钟线                         
);


endmodule
