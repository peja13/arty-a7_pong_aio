----------------------------------------------------------------------------------
-- Projekt      : Pong am Arty A7 - Pmod OLEDrgb (SPI) an JD, zwei Boards per LAN
-- Modul        : spi_top
--
-- Ein Bitstream fuer beide Boards, die Rolle waehlt ein Schalter:
--   sw0 = 0 : Server   rechnet das Spiel. btn0/btn1 = linker Schlaeger hoch/runter.
--                      Rechter Schlaeger: vom Client ueber LAN; ohne Client wie
--                      bisher btn2/btn3 (zu zweit an einem Board).
--   sw0 = 1 : Client   btn0 oder btn2 = rechter Schlaeger hoch,
--                      btn1 oder btn3 = rechter Schlaeger runter.
--   sw1 = 1 : (nur Client) kein OLED angeschlossen: Display-Ausgaenge aus,
--             LED0..LED3 zeigen den eigenen Punktestand (binaer), die Bildrate
--             (ca. 55 Hz) kommt dann von einem internen Zaehler.
--   sw2, sw3 : frei
--   LED0..LED3 : sonst Spiegel der Schalter
--   LD0 (RGB)  : gruen = Partner verbunden, rot = kein Partner
--   RESET-Taster : Display, Spiel und Ethernet-PHY neu initialisieren
--
-- LAN: beide Arty per Netzwerkkabel direkt (Auto-MDIX) oder ueber einen Switch
--      verbinden. Es wird ohne IP mit Ethernet-Broadcast gearbeitet (lan_link).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.pong_pkg.all;

entity spi_top is
    generic (
        CLK_HZ      : positive := 100_000_000;
        SPI_HALF    : positive := 8;
        NET_TIMEOUT : positive := 15;             -- Bilder ohne Partner bis "getrennt"
        FRAME_HZ    : positive := 55              -- Bildrate ohne OLED (wie mit OLED)
    );
    port (
        CLK100MHZ   : in  std_logic;
        ck_rst      : in  std_logic;                  -- RESET-Taster, aktiv low
        sw          : in  std_logic_vector(3 downto 0);
        btn         : in  std_logic_vector(3 downto 0);
        led         : out std_logic_vector(3 downto 0);
        oled_cs     : out std_logic;                  -- JD1
        oled_mosi   : out std_logic;                  -- JD2
        oled_sck    : out std_logic;                  -- JD4
        oled_dc     : out std_logic;                  -- JD7
        oled_res    : out std_logic;                  -- JD8
        oled_vccen  : out std_logic;                  -- JD9
        oled_pmoden : out std_logic;                  -- JD10
        led0_r      : out std_logic;                  -- RGB-LED LD0: LAN-Status
        led0_g      : out std_logic;
        -- Ethernet-PHY (MII)
        eth_ref_clk : out std_logic;
        eth_rstn    : out std_logic;
        eth_tx_clk  : in  std_logic;
        eth_tx_en   : out std_logic;
        eth_txd     : out std_logic_vector(3 downto 0);
        eth_rx_clk  : in  std_logic;
        eth_rx_dv   : in  std_logic;
        eth_rxd     : in  std_logic_vector(3 downto 0);
        eth_rxerr   : in  std_logic
    );
end entity spi_top;

architecture structural of spi_top is

    constant DB_CYCLES    : positive := (CLK_HZ / 1000) * 10;
    constant FRAME_CYCLES : positive := CLK_HZ / FRAME_HZ;

    signal rst_sync   : std_logic_vector(1 downto 0) := (others => '1');
    signal rst        : std_logic;
    signal sw_f       : std_logic_vector(3 downto 0);
    signal btn_f      : std_logic_vector(3 downto 0);
    signal pix_x      : unsigned(6 downto 0);
    signal pix_y      : unsigned(5 downto 0);
    signal pix        : std_logic_vector(15 downto 0);

    -- Bildtakt: vom Display (oled_ctrl) oder, ohne OLED, vom internen Zaehler
    signal no_oled    : std_logic;
    signal oled_rst   : std_logic;
    signal oled_tick  : std_logic;
    signal int_tick   : std_logic := '0';
    signal int_cnt    : natural range 0 to FRAME_CYCLES - 1 := 0;
    signal frame_tick : std_logic;
    signal o_cs, o_mosi, o_sck, o_dc, o_res, o_vccen, o_pmoden : std_logic;

    -- LAN-Pong
    signal pong_client : std_logic;
    signal pong_state  : pong_state_t;
    signal net_state   : pong_state_t;
    signal net_btn     : std_logic_vector(1 downto 0);
    signal net_ok      : std_logic;
    signal my_btn      : std_logic_vector(1 downto 0);
    signal pwm         : unsigned(7 downto 0) := (others => '0');

begin

    process (CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            rst_sync <= rst_sync(0) & (not ck_rst);
        end if;
    end process;

    rst <= rst_sync(1);

    g_in : for i in 0 to 3 generate
        u_sw : entity work.input_filter
            generic map (DEBOUNCE_CYCLES => DB_CYCLES)
            port map (clk => CLK100MHZ, rst => rst, d => sw(i), q => sw_f(i));
        u_btn : entity work.input_filter
            generic map (DEBOUNCE_CYCLES => DB_CYCLES)
            port map (clk => CLK100MHZ, rst => rst, d => btn(i), q => btn_f(i));
    end generate g_in;

    -- Client ohne OLED: Display aus, Bildtakt intern
    no_oled  <= sw_f(0) and sw_f(1);
    oled_rst <= rst or no_oled;

    process (CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            int_tick <= '0';
            if int_cnt = FRAME_CYCLES - 1 then
                int_cnt  <= 0;
                int_tick <= '1';
            else
                int_cnt <= int_cnt + 1;
            end if;
        end if;
    end process;

    frame_tick <= int_tick when no_oled = '1' else oled_tick;

    -- LEDs: Punktestand des Clients ohne OLED, sonst Spiegel der Schalter
    led <= std_logic_vector(to_unsigned(pong_state.score_r, 4)) when no_oled = '1' else sw_f;

    u_render : entity work.oled_render
        port map (
            clk         => CLK100MHZ,
            rst         => rst,
            x           => pix_x,
            y           => pix_y,
            frame_tick  => frame_tick,
            client      => sw_f(0),
            btn         => btn_f,
            pix         => pix,
            net_ok      => net_ok,
            net_btn     => net_btn,
            net_state   => net_state,
            pong_state  => pong_state,
            pong_client => pong_client
        );

    u_ctrl : entity work.oled_ctrl
        generic map (
            T_US     => CLK_HZ / 1_000_000,
            SPI_HALF => SPI_HALF
        )
        port map (
            clk         => CLK100MHZ,
            rst         => oled_rst,
            pix_x       => pix_x,
            pix_y       => pix_y,
            pix_in      => pix,
            frame_tick  => oled_tick,
            oled_cs     => o_cs,
            oled_mosi   => o_mosi,
            oled_sck    => o_sck,
            oled_dc     => o_dc,
            oled_res    => o_res,
            oled_vccen  => o_vccen,
            oled_pmoden => o_pmoden
        );

    -- ohne OLED liegen alle Display-Pins auf 0 (kein Strom in ein abgeschaltetes Modul)
    oled_cs     <= o_cs     and not no_oled;
    oled_mosi   <= o_mosi   and not no_oled;
    oled_sck    <= o_sck    and not no_oled;
    oled_dc     <= o_dc     and not no_oled;
    oled_res    <= o_res    and not no_oled;
    oled_vccen  <= o_vccen  and not no_oled;
    oled_pmoden <= o_pmoden and not no_oled;

    -- Tasten des Client-Spielers: (1) runter, (0) hoch
    my_btn <= (btn_f(1) or btn_f(3)) & (btn_f(0) or btn_f(2));

    u_lan : entity work.lan_link
        generic map (
            PHY_RST_CYCLES => CLK_HZ / 100,       -- 10 ms
            TIMEOUT_FRAMES => NET_TIMEOUT
        )
        port map (
            clk         => CLK100MHZ,
            rst         => rst,
            enable      => '1',
            client      => pong_client,
            frame_tick  => frame_tick,
            st_tx       => pong_state,
            btn_tx      => my_btn,
            st_rx       => net_state,
            btn_rx      => net_btn,
            peer_ok     => net_ok,
            eth_ref_clk => eth_ref_clk,
            eth_rstn    => eth_rstn,
            eth_tx_clk  => eth_tx_clk,
            eth_tx_en   => eth_tx_en,
            eth_txd     => eth_txd,
            eth_rx_clk  => eth_rx_clk,
            eth_rx_dv   => eth_rx_dv,
            eth_rxd     => eth_rxd,
            eth_rxerr   => eth_rxerr
        );

    -- Status-LED, gedimmt (1/16 Helligkeit, die RGB-LEDs sind sehr hell)
    process (CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            pwm <= pwm + 1;
            if pwm < 16 then
                led0_g <= net_ok;
                led0_r <= not net_ok;
            else
                led0_g <= '0';
                led0_r <= '0';
            end if;
        end if;
    end process;

end architecture structural;
