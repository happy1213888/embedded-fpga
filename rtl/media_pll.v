`timescale 1ns/1ps
module media_pll(input refclk,input reset,output clk_mem,output clk_pixel,output clk_serial,output locked,output clk_sdram);
    wire [4:0] clocks;
    EG_PHY_PLL #(.FIN("50.000000"),.FEEDBK_MODE("NOCOMP"),.FEEDBK_PATH("VCO_PHASE_0"),
        .STDBY_ENABLE("DISABLE"),.PLLRST_ENA("ENABLE"),.SYNC_ENABLE("DISABLE"),
        .GMC_GAIN(4),.ICP_CURRENT(13),.KVCO(4),.LPF_CAPACITOR(1),.LPF_RESISTOR(4),
        .REFCLK_DIV(1),.FBCLK_DIV(20),
        .CLKC0_ENABLE("ENABLE"),.CLKC0_DIV(10),.CLKC0_CPHASE(9),.CLKC0_FPHASE(0),
        .CLKC1_ENABLE("ENABLE"),.CLKC1_DIV(40),.CLKC1_CPHASE(39),.CLKC1_FPHASE(0),
        .CLKC2_ENABLE("ENABLE"),.CLKC2_DIV(8),.CLKC2_CPHASE(7),.CLKC2_FPHASE(0),
        // Move the SDRAM clock one coarse phase step later.  The previous
        // 6.500 ns edge missed the hard-IP DQ setup check by 15 ps while
        // retaining over 3 ns of hold margin; a 1 ns shift keeps ample hold.
        .CLKC3_ENABLE("ENABLE"),.CLKC3_DIV(10),.CLKC3_CPHASE(6),.CLKC3_FPHASE(7)) pll(
        .refclk(refclk),.reset(reset),.stdby(1'b0),.extlock(locked),.load_reg(1'b0),
        .psclk(1'b0),.psdown(1'b0),.psstep(1'b0),.psclksel(3'd0),.psdone(),
        .dclk(1'b0),.dcs(1'b0),.dwe(1'b0),.di(8'd0),.daddr(6'd0),.do(),.fbclk(1'b0),.clkc(clocks));
    assign clk_mem=clocks[0];assign clk_pixel=clocks[1];assign clk_serial=clocks[2];
    assign clk_sdram=clocks[3];
endmodule
