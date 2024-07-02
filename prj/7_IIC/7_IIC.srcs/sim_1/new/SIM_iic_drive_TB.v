`timescale 1ns / 1ns

module SIM_iic_drive_TB();

/************ localparam_define *************/
    localparam  P_CLK_PERIOD = 20;


/************   wire_define     *************/
                                          
    wire                    wo_op_ready      ;   //操作准备                                                       
                     
    wire                    wo_write_req     ;   //写入从机设备请求    

    wire    [7:0]           wo_read_data     ;   //读出从机的数据                                            
    wire                    wo_read_valid    ;   //读出从机数据有效  
    
    wire                    io_iic_sda       ;
    wire                    o_iic_scl        ;




/************   reg_define      *************/
    reg                     i_clk            ;
    reg                     i_rst            ;
    reg     [6:0]           ri_device_addr   ;   //从机设备的器件地址  
    reg                     ri_op_addr_ctrl  ;   //从机设备操作地址控制，0表示操作地址为8bit，1表示操作地址为16bit
    reg     [15:0]          ri_op_addr       ;   //从机的操作地址,有些从机设备包括两个器件地址          
    reg     [7:0]           ri_op_byte_num   ;   //从机操作的字节数                                       
    reg     [1:0]           ri_op_type       ;   //从机本次操作的类型，页写0、顺序读1、随机读2                    
    reg                     ri_op_valid      ;   //操作有效  
    
    reg     [7:0]           ri_write_data    ;   //写入从机的数据   



/************   instantiation   *************/
iic_drive   u0_iic_drive
(
    .i_clk          (i_clk)           ,
    .i_rst          (i_rst)           ,

    /*user interface*/
    .i_device_addr (ri_device_addr )  ,   //从机设备的器件地址  
    .i_op_addr_ctrl(ri_op_addr_ctrl)  ,   //从机设备操作地址控制，0表示操作地址为8bit，1表示操作地址为16bit                                                
    .i_op_addr     (ri_op_addr     )  ,   //从机的操作地址,有些从机设备包括两个器件地址          
    .i_op_byte_num (ri_op_byte_num )  ,   //从机操作的字节数                                       
    .i_op_type     (ri_op_type     )  ,   //从机本次操作的类型，页写0、顺序读1、随机读2                                 

    .i_op_valid    (ri_op_valid    )  ,   //操作有效                                                                              
    .o_op_ready    (wo_op_ready    )  ,   //操作准备                                                                              

    .i_write_data  (ri_write_data  )  ,   //写入从机的数据                        
    .o_write_req   (wo_write_req   )  ,   //写入从机设备请求                                      

    .o_read_data   (wo_read_data   )  ,   //读出从机的数据                                            
    .o_read_valid  (wo_read_valid  )  ,   //读出从机数据有效                                                      

    /*IIC interface*/
    .io_iic_sda     (io_iic_sda     )      ,   //IIC的数据线，输入、输出、高阻态
    .o_iic_scl      (o_iic_scl      )          //IIC时钟线                         
);


AT24C64 u1_AT24C64
(       
    .SDA    (io_iic_sda )       , 
    .SCL    (o_iic_scl  )       , 
    .WP     (0          )       //写保护，没有_n的话就是高电平有效，设置0就是不开启写保护     
);


/************   initial_block   *************/
initial
    begin
        i_clk = 0;
        i_rst = 1;
        #300
        @(posedge i_clk) i_rst = 0;
    end 


initial
    begin
        ri_device_addr   = 0 ;
        ri_op_addr_ctrl  = 0 ;
        ri_op_addr       = 0 ;
        ri_op_byte_num   = 0 ;
        ri_op_type       = 0 ;
        ri_op_valid      = 0 ;
        ri_write_data    = 0 ;

        wait(!i_rst);

        repeat(10) @(posedge i_clk) ;   //让以上的信号在rst拉低之前保持为0，再等待10个时钟周期
        
        forever 
            begin
                iic_send_data();
                iic_read_data(0);
              
            end

    end 


/************   other_function   *************/

    //IIC的时钟和数据线上拉
    pullup(io_iic_sda);
    pullup(o_iic_scl );


/************   always_block    *************/
always #(P_CLK_PERIOD/2) i_clk = ~i_clk;


/*写数据*/
always@(posedge i_clk or posedge i_rst)
    begin
        if(i_rst)
            begin
                ri_write_data <= 'd0;
            end
        else if(ri_write_data == 255)
            begin
                ri_write_data <= 'd0;
            end
        else if(wo_write_req)
            begin
                ri_write_data <= ri_write_data + 3;
            end
        else
            begin
                ri_write_data <= ri_write_data;
            end
    end


/************   task_define     *************/
task iic_send_data();
    begin
        ri_device_addr   <= 7'b1010_000 ;   //AT24C64的器件地址 
        ri_op_addr_ctrl  <= 1 ; 
        ri_op_addr       <= 16'h0000 ; 
        ri_op_byte_num   <= 10 ; 
        ri_op_type       <= 0 ; 
        ri_op_valid      <= 1 ;
        @(posedge i_clk);

        wait(!wo_op_ready);

        ri_device_addr   <= 0;   //AT24C64的器件地址 
        ri_op_addr_ctrl  <= 0;
        ri_op_addr       <= 0;
        ri_op_byte_num   <= 0;
        ri_op_type       <= 0;
        ri_op_valid      <= 0;
        @(posedge i_clk);
        wait(wo_op_ready);
    end
endtask

task iic_read_data(input [15:0] addr);
    begin
        ri_device_addr   <= 7'b1010_000 ;   //AT24C64的器件地址 
        ri_op_addr_ctrl  <= 1 ; 
        ri_op_addr       <= addr ; 
        ri_op_byte_num   <= 10 ; 
        ri_op_type       <= 2 ; 
        ri_op_valid      <= 1 ;
        @(posedge i_clk);

        wait(!wo_op_ready);

        ri_device_addr   <= 0;   //AT24C64的器件地址 
        ri_op_addr_ctrl  <= 0;
        ri_op_addr       <= 0;
        ri_op_byte_num   <= 0;
        ri_op_type       <= 0;
        ri_op_valid      <= 0;
        @(posedge i_clk);
        wait(wo_op_ready);
    end
endtask


endmodule
