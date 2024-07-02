/*EEPROM顶层模块*/
module eeprom_top
(
    input                   i_sys_clk     ,

    /*IIC interface*/
    inout                   io_iic_sda    ,     //IIC的数据线，输入、输出、高阻态
    output                  o_iic_scl           //IIC时钟线                         
);
endmodule
