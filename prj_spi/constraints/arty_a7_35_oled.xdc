## ---------------------------------------------------------------------------
## Pmod OLEDrgb (SSD1331, SPI) an Pmod JD - Arty A7-35T
##
## Pmod-Pinbelegung des OLEDrgb (12-polig, passt 1:1 auf JD):
##   obere Reihe  : 1 CS | 2 MOSI | 3 NC | 4 SCK | 5 GND | 6 VCC (3V3)
##   untere Reihe : 7 D/C | 8 RES | 9 VCCEN | 10 PMODEN | 11 GND | 12 VCC (3V3)
## Beim direkten Aufstecken liegen GND auf GND und VCC auf VCC (JD Pin 5/11 = GND,
## Pin 6/12 = 3V3). Bei Kabelverbindung: Pin 5 + 11 -> GND, Pin 6 + 12 -> 3V3.
## ---------------------------------------------------------------------------

## Clock signal (100 MHz)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }]; #IO_L12P_T1_MRCC_35 Sch=gclk[100]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK100MHZ }];

## RESET-Taster (aktiv low)
set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports { ck_rst }]; #IO_L16P_T2_35 Sch=ck_rst

## Switches: sw0 = Rolle (0 = Server, 1 = Client), sw1 = Client ohne OLED, sw2/sw3 frei
set_property -dict { PACKAGE_PIN A8    IOSTANDARD LVCMOS33 } [get_ports { sw[0] }]; #IO_L12N_T1_MRCC_16 Sch=sw[0]
set_property -dict { PACKAGE_PIN C11   IOSTANDARD LVCMOS33 } [get_ports { sw[1] }]; #IO_L13P_T2_MRCC_16 Sch=sw[1]
set_property -dict { PACKAGE_PIN C10   IOSTANDARD LVCMOS33 } [get_ports { sw[2] }]; #IO_L13N_T2_MRCC_16 Sch=sw[2]
set_property -dict { PACKAGE_PIN A10   IOSTANDARD LVCMOS33 } [get_ports { sw[3] }]; #IO_L14P_T2_SRCC_16 Sch=sw[3]

## Buttons: Server btn0/btn1 = links hoch/runter (ohne Client: btn2/btn3 = rechts)
##          Client btn0 oder btn2 = hoch, btn1 oder btn3 = runter
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { btn[0] }]; #IO_L6N_T0_VREF_16 Sch=btn[0]
set_property -dict { PACKAGE_PIN C9    IOSTANDARD LVCMOS33 } [get_ports { btn[1] }]; #IO_L11P_T1_SRCC_16 Sch=btn[1]
set_property -dict { PACKAGE_PIN B9    IOSTANDARD LVCMOS33 } [get_ports { btn[2] }]; #IO_L11N_T1_SRCC_16 Sch=btn[2]
set_property -dict { PACKAGE_PIN B8    IOSTANDARD LVCMOS33 } [get_ports { btn[3] }]; #IO_L12P_T1_MRCC_16 Sch=btn[3]

## LEDs: Spiegel der Schalter; Client ohne OLED: eigener Punktestand (binaer)
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { led[0] }]; #IO_L24N_T3_35 Sch=led[4]
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { led[1] }]; #IO_25_35 Sch=led[5]
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { led[2] }]; #IO_L24P_T3_A01_D17_14 Sch=led[6]
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { led[3] }]; #IO_L24N_T3_A00_D16_14 Sch=led[7]

## RGB-LED LD0: Status LAN-Pong (gruen = Partner verbunden, rot = kein Partner)
set_property -dict { PACKAGE_PIN F6    IOSTANDARD LVCMOS33 } [get_ports { led0_g }]; #IO_L19N_T3_VREF_35 Sch=led0_g
set_property -dict { PACKAGE_PIN G6    IOSTANDARD LVCMOS33 } [get_ports { led0_r }]; #IO_L19P_T3_35 Sch=led0_r

## Pmod JD - Pmod OLEDrgb
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { oled_cs }];      #IO_L11N_T1_SRCC_35 Sch=jd[1]   CS
set_property -dict { PACKAGE_PIN D3    IOSTANDARD LVCMOS33 } [get_ports { oled_mosi }];    #IO_L12N_T1_MRCC_35 Sch=jd[2]   MOSI
set_property -dict { PACKAGE_PIN F3    IOSTANDARD LVCMOS33 } [get_ports { oled_sck }];     #IO_L13N_T2_MRCC_35 Sch=jd[4]   SCK
set_property -dict { PACKAGE_PIN E2    IOSTANDARD LVCMOS33 } [get_ports { oled_dc }];      #IO_L14P_T2_SRCC_35 Sch=jd[7]   D/C
set_property -dict { PACKAGE_PIN D2    IOSTANDARD LVCMOS33 } [get_ports { oled_res }];     #IO_L14N_T2_SRCC_35 Sch=jd[8]   RES
set_property -dict { PACKAGE_PIN H2    IOSTANDARD LVCMOS33 } [get_ports { oled_vccen }];   #IO_L15P_T2_DQS_35 Sch=jd[9]    VCCEN
set_property -dict { PACKAGE_PIN G2    IOSTANDARD LVCMOS33 } [get_ports { oled_pmoden }];  #IO_L15N_T2_DQS_35 Sch=jd[10]   PMODEN

## ---------------------------------------------------------------------------
## Ethernet-PHY TI DP83848J (10/100 Mbit/s, MII) an der RJ45-Buchse J9
## Der 25-MHz-Takt des PHY kommt vom FPGA (eth_ref_clk). MDC/MDIO werden nicht
## benutzt: der PHY startet mit Autonegotiation und Auto-MDIX.
## ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN G18   IOSTANDARD LVCMOS33 } [get_ports { eth_ref_clk }]; #IO_L22P_T3_A17_15 Sch=eth_ref_clk
set_property -dict { PACKAGE_PIN C16   IOSTANDARD LVCMOS33 } [get_ports { eth_rstn }];    #IO_L20P_T3_A20_15 Sch=eth_rstn
set_property -dict { PACKAGE_PIN F15   IOSTANDARD LVCMOS33 } [get_ports { eth_rx_clk }];  #IO_L14P_T2_SRCC_15 Sch=eth_rx_clk
set_property -dict { PACKAGE_PIN G16   IOSTANDARD LVCMOS33 } [get_ports { eth_rx_dv }];   #IO_L13N_T2_MRCC_15 Sch=eth_rx_dv
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[0] }];  #IO_L21N_T3_DQS_A18_15 Sch=eth_rxd[0]
set_property -dict { PACKAGE_PIN E17   IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[1] }];  #IO_L16P_T2_A28_15 Sch=eth_rxd[1]
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[2] }];  #IO_L21P_T3_DQS_15 Sch=eth_rxd[2]
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[3] }];  #IO_L18N_T2_A23_15 Sch=eth_rxd[3]
set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33 } [get_ports { eth_rxerr }];   #IO_L20N_T3_A19_15 Sch=eth_rxerr
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { eth_tx_clk }];  #IO_L13P_T2_MRCC_15 Sch=eth_tx_clk
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { eth_tx_en }];   #IO_L19N_T3_A21_VREF_15 Sch=eth_tx_en
set_property -dict { PACKAGE_PIN H14   IOSTANDARD LVCMOS33 } [get_ports { eth_txd[0] }];  #IO_L15P_T2_DQS_15 Sch=eth_txd[0]
set_property -dict { PACKAGE_PIN J14   IOSTANDARD LVCMOS33 } [get_ports { eth_txd[1] }];  #IO_L19P_T3_A22_15 Sch=eth_txd[1]
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { eth_txd[2] }];  #IO_L17N_T2_A25_15 Sch=eth_txd[2]
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { eth_txd[3] }];  #IO_L18P_T2_A24_15 Sch=eth_txd[3]

## Takte vom PHY: 25 MHz bei 100 Mbit/s (bei 10 Mbit/s 2,5 MHz - unkritischer)
create_clock -name eth_rx_clk -period 40.000 [get_ports { eth_rx_clk }]
create_clock -name eth_tx_clk -period 40.000 [get_ports { eth_tx_clk }]

## Die drei Takte sind unabhaengig; Uebergaben laufen ueber Synchronisierer
## (Toggle-Handshake in lan_link/eth_tx/eth_rx), deshalb keine Timing-Pfade dazwischen.
set_clock_groups -asynchronous -group [get_clocks sys_clk_pin] -group [get_clocks eth_rx_clk] -group [get_clocks eth_tx_clk]

## MII-Zeitverhalten (IEEE 802.3 Clause 22)
##   RX: der PHY aendert RXD/RX_DV/RX_ER 10..30 ns nach der steigenden RX_CLK-Flanke
##   TX: TXD/TX_EN muessen spaetestens 25 ns nach der steigenden TX_CLK-Flanke stehen
set_input_delay  -clock eth_rx_clk -max 30.000 [get_ports { eth_rxd[*] eth_rx_dv eth_rxerr }]
set_input_delay  -clock eth_rx_clk -min 10.000 [get_ports { eth_rxd[*] eth_rx_dv eth_rxerr }]
set_output_delay -clock eth_tx_clk -max 15.000 [get_ports { eth_txd[*] eth_tx_en }]
set_output_delay -clock eth_tx_clk -min  0.000 [get_ports { eth_txd[*] eth_tx_en }]
set_property IOB TRUE [get_ports { eth_rxd[*] eth_rx_dv eth_rxerr eth_txd[*] eth_tx_en }]

## Konfiguration
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
