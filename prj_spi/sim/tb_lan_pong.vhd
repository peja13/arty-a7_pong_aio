----------------------------------------------------------------------------------
-- Testbench    : tb_lan_pong
-- Beschreibung : Zwei komplette Designs (spi_top) spielen ueber ein LAN-Modell:
--                A = Server (sw0 = 0), B = Client (sw0 = 1).
--                Jedes Board hat ein eigenes Display-Modell und eigene Takte.
--                Das Kabelmodell spielt die beiden PHYs: TXD von A wird bei der
--                steigenden TX_CLK-Flanke gelesen und kommt bei B mit dem Takt von
--                A als RX_CLK an (wie bei einem echten Link), Praeambel verkuerzt.
--
--   Geprueft: 25-MHz-Takt und Reset fuer den PHY, Rahmenformat und FCS beider
--   Seiten, Verbindungsaufbau (LED gruen), Client zeigt dasselbe Bild wie der
--   Server, Client steuert den rechten Schlaeger (btn2 am Server wird dann
--   ignoriert), gestoerte Rahmen werden verworfen (Client getrennt, Ball blinkt),
--   Kabel getrennt (Server spielt wieder lokal), Wiederverbinden, Client ohne
--   OLED (sw1 = 1): Display aus, LEDs = Punktestand, steuert weiter den Schlaeger.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.env.all;

use work.eth_pkg.all;
use work.tb_oled_pkg.all;

entity tb_lan_pong is
end entity tb_lan_pong;

architecture sim of tb_lan_pong is

    constant WHITE   : std_logic_vector(15 downto 0) := x"FFFF";
    constant TIMEOUT : positive := 4;             -- Bilder ohne Partner bis "getrennt"
    -- Bildrate ohne OLED: in der Simulation (CLK_HZ = 1 MHz, SPI_HALF = 1) dauert ein
    -- Display-Bild ca. 340 000 Takte; der interne Bildtakt soll genauso schnell sein
    constant FRAME_HZ_SIM : positive := 3;

    type side_t is (SA, SB);
    type cnt_arr_t is array (side_t) of natural;

    -- je Board: 100-MHz-Takt (leicht unterschiedlich), Bedienung, Display, LEDs
    signal clk_a, clk_b   : std_logic := '0';
    signal rstn           : std_logic := '0';
    signal sw_a, sw_b     : std_logic_vector(3 downto 0) := "0000";
    signal btn_a, btn_b   : std_logic_vector(3 downto 0) := "0000";
    signal led_a, led_b   : std_logic_vector(3 downto 0);
    signal cs_a, mosi_a, sck_a, dc_a, res_a, vcc_a, pm_a : std_logic;
    signal cs_b, mosi_b, sck_b, dc_b, res_b, vcc_b, pm_b : std_logic;
    signal r_a, g_a, r_b, g_b : std_logic;
    signal fb_a, fb_b     : fb_t;
    signal fc_a, fc_b     : natural;

    -- Ethernet
    signal txclk_a, txclk_b : std_logic := '0';
    signal rxclk_a, rxclk_b : std_logic := '0';
    signal ref_a, ref_b     : std_logic;
    signal rstn_a, rstn_b   : std_logic;
    signal txen_a, txen_b   : std_logic;
    signal txd_a, txd_b     : std_logic_vector(3 downto 0);
    signal rxdv_a, rxdv_b   : std_logic := '0';
    signal rxd_a, rxd_b     : std_logic_vector(3 downto 0) := "0000";

    -- Kabel: 0 = ok, 1 = jeder Rahmen hat einen Bitfehler, 2 = getrennt
    signal cable_ab, cable_ba : natural := 0;

    -- Auswertung
    signal tx_frames : cnt_arr_t := (others => 0);   -- gesendete Rahmen je Board
    signal r_on_a, g_on_a, r_on_b, g_on_b : natural := 0;

    function crc_ref (b : byte_arr_t; n : natural) return std_logic_vector is
        variable c : std_logic_vector(31 downto 0) := (others => '1');
    begin
        for k in 0 to n - 1 loop
            c(7 downto 0) := c(7 downto 0) xor b(b'low + k);
            for i in 0 to 7 loop
                if c(0) = '1' then
                    c := ('0' & c(31 downto 1)) xor x"EDB88320";
                else
                    c := '0' & c(31 downto 1);
                end if;
            end loop;
        end loop;
        return not c;
    end function;

    -- oberste weisse Zeile in Spalte x (Schlaegerkante), -1 = keine
    function pad_top (fb : fb_t; x : natural) return integer is
    begin
        for y in 0 to 63 loop
            if fb_px(fb, x, y) = WHITE then
                return y;
            end if;
        end loop;
        return -1;
    end function;

    function diff (fa, fb : fb_t) return natural is
        variable n : natural := 0;
    begin
        for i in fa'range loop
            if fa(i) /= fb(i) then
                n := n + 1;
            end if;
        end loop;
        return n;
    end function;

    function ball_seen (fb : fb_t) return boolean is
    begin
        return fb_px(fb, 46, 30) = WHITE and fb_px(fb, 48, 32) = WHITE;
    end function;

begin

    clk_a   <= not clk_a after 5 ns;
    clk_b   <= not clk_b after 5.0005 ns;         -- 100 ppm langsamer
    txclk_a <= not txclk_a after 20 ns;
    txclk_b <= not txclk_b after 20.002 ns;

    -- Ein echter PHY gewinnt den Empfangstakt aus dem Signal des Partners
    rxclk_b <= transport txclk_a after 2 ns;
    rxclk_a <= transport txclk_b after 2 ns;

    ------------------------------------------------------------------
    -- die beiden Boards
    ------------------------------------------------------------------
    dut_a : entity work.spi_top
        generic map (CLK_HZ => 1_000_000, SPI_HALF => 1, NET_TIMEOUT => TIMEOUT, FRAME_HZ => FRAME_HZ_SIM)
        port map (
            CLK100MHZ => clk_a, ck_rst => rstn, sw => sw_a, btn => btn_a, led => led_a,
            oled_cs => cs_a, oled_mosi => mosi_a, oled_sck => sck_a, oled_dc => dc_a,
            oled_res => res_a, oled_vccen => vcc_a, oled_pmoden => pm_a,
            led0_r => r_a, led0_g => g_a,
            eth_ref_clk => ref_a, eth_rstn => rstn_a,
            eth_tx_clk => txclk_a, eth_tx_en => txen_a, eth_txd => txd_a,
            eth_rx_clk => rxclk_a, eth_rx_dv => rxdv_a, eth_rxd => rxd_a, eth_rxerr => '0');

    dut_b : entity work.spi_top
        generic map (CLK_HZ => 1_000_000, SPI_HALF => 1, NET_TIMEOUT => TIMEOUT, FRAME_HZ => FRAME_HZ_SIM)
        port map (
            CLK100MHZ => clk_b, ck_rst => rstn, sw => sw_b, btn => btn_b, led => led_b,
            oled_cs => cs_b, oled_mosi => mosi_b, oled_sck => sck_b, oled_dc => dc_b,
            oled_res => res_b, oled_vccen => vcc_b, oled_pmoden => pm_b,
            led0_r => r_b, led0_g => g_b,
            eth_ref_clk => ref_b, eth_rstn => rstn_b,
            eth_tx_clk => txclk_b, eth_tx_en => txen_b, eth_txd => txd_b,
            eth_rx_clk => rxclk_b, eth_rx_dv => rxdv_b, eth_rxd => rxd_b, eth_rxerr => '0');

    disp_a : entity work.ssd1331_model
        port map (cs => cs_a, sck => sck_a, mosi => mosi_a, dc => dc_a, fb => fb_a, frame_cnt => fc_a);
    disp_b : entity work.ssd1331_model
        port map (cs => cs_b, sck => sck_b, mosi => mosi_b, dc => dc_b, fb => fb_b, frame_cnt => fc_b);

    ------------------------------------------------------------------
    -- Kabelmodell, je Richtung ein Prozess
    ------------------------------------------------------------------
    process (txclk_a)
        variable pos : integer := 0;
        variable n   : std_logic_vector(3 downto 0);
        variable dv  : std_logic;
    begin
        if rising_edge(txclk_a) then
            n  := txd_a;
            dv := txen_a and rstn_a and rstn_b;
            if pos < 3 or cable_ab = 2 then       -- PHY verschluckt 3 Praeambel-Nibbles
                dv := '0';
            end if;
            if cable_ab = 1 and pos = 16 + 80 then
                n(2) := not n(2);
            end if;
            if txen_a = '1' then pos := pos + 1; else pos := 0; end if;
            rxd_b  <= transport n after 12 ns;
            rxdv_b <= transport dv after 12 ns;
        end if;
    end process;

    process (txclk_b)
        variable pos : integer := 0;
        variable n   : std_logic_vector(3 downto 0);
        variable dv  : std_logic;
    begin
        if rising_edge(txclk_b) then
            n  := txd_b;
            dv := txen_b and rstn_a and rstn_b;
            if pos < 3 or cable_ba = 2 then
                dv := '0';
            end if;
            if cable_ba = 1 and pos = 16 + 80 then
                n(2) := not n(2);
            end if;
            if txen_b = '1' then pos := pos + 1; else pos := 0; end if;
            rxd_a  <= transport n after 12 ns;
            rxdv_a <= transport dv after 12 ns;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Mitschnitt: jeden gesendeten Rahmen auf Format und FCS pruefen
    ------------------------------------------------------------------
    g_mon : for s in side_t generate
        signal tclk, ten : std_logic;
        signal td        : std_logic_vector(3 downto 0);
    begin
        tclk <= txclk_a when s = SA else txclk_b;
        ten  <= txen_a  when s = SA else txen_b;
        td   <= txd_a   when s = SA else txd_b;

        process (tclk)
            variable act : boolean := false;
            variable pre : natural := 0;
            variable sfd : boolean := false;
            variable nib : natural := 0;
            variable lo  : std_logic_vector(3 downto 0);
            variable b   : byte_arr_t(0 to 127);
            variable fcs : std_logic_vector(31 downto 0);
            variable typ : std_logic_vector(7 downto 0);
            variable src : std_logic_vector(7 downto 0);
        begin
            if rising_edge(tclk) then
                if ten = '1' then
                    if not act then
                        act := true; pre := 0; sfd := false; nib := 0;
                    end if;
                    if not sfd then
                        if td = x"5" then pre := pre + 1; elsif td = x"D" then sfd := true; end if;
                    else
                        if nib mod 2 = 0 then
                            lo := td;
                        elsif nib / 2 <= 127 then
                            b(nib / 2) := td & lo;
                        end if;
                        nib := nib + 1;
                    end if;
                elsif act then
                    act := false;
                    if s = SA then typ := x"01"; src := x"01"; else typ := x"02"; src := x"02"; end if;
                    fcs := crc_ref(b, 60);
                    assert sfd and pre = 15 and nib = 128
                        report side_t'image(s) & ": Rahmenlaenge/Praeambel falsch" severity error;
                    assert b(0) = x"FF" and b(5) = x"FF" and b(6) = x"02" and b(11) = src and
                           b(12) = x"88" and b(13) = x"B5" and b(14) = x"50" and b(17) = x"47" and
                           b(18) = x"01" and b(19) = typ
                        report side_t'image(s) & ": Kopf des Rahmens falsch" severity error;
                    assert b(60) = fcs(7 downto 0) and b(61) = fcs(15 downto 8) and
                           b(62) = fcs(23 downto 16) and b(63) = fcs(31 downto 24)
                        report side_t'image(s) & ": FCS falsch" severity error;
                    tx_frames(s) <= tx_frames(s) + 1;
                end if;
            end if;
        end process;
    end generate g_mon;

    -- LED-Zaehler (wie lange war rot/gruen an)
    process (clk_a)
    begin
        if rising_edge(clk_a) then
            if r_a = '1' then r_on_a <= r_on_a + 1; end if;
            if g_a = '1' then g_on_a <= g_on_a + 1; end if;
        end if;
    end process;

    process (clk_b)
    begin
        if rising_edge(clk_b) then
            if r_b = '1' then r_on_b <= r_on_b + 1; end if;
            if g_b = '1' then g_on_b <= g_on_b + 1; end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Ablauf
    ------------------------------------------------------------------
    process
        variable f, n    : natural;
        variable t0      : time;
        variable ra, ga, rb, gb : natural;
        variable la, ra_y : integer;
        variable on_seen, off_seen : boolean;

        procedure frames (side : side_t; k : natural) is
        begin
            if side = SA then
                f := fc_a; wait until fc_a = f + k;
            else
                f := fc_b; wait until fc_b = f + k;
            end if;
        end procedure;

        procedure led_snap is
        begin
            ra := r_on_a; ga := g_on_a; rb := r_on_b; gb := g_on_b;
        end procedure;

        procedure led_check (name : string; a_green, b_green : boolean) is
        begin
            if a_green then
                assert g_on_a > ga and r_on_a = ra report name & ": LED Server nicht gruen" severity error;
            else
                assert r_on_a > ra and g_on_a = ga report name & ": LED Server nicht rot" severity error;
            end if;
            if b_green then
                assert g_on_b > gb and r_on_b = rb report name & ": LED Client nicht gruen" severity error;
            else
                assert r_on_b > rb and g_on_b = gb report name & ": LED Client nicht rot" severity error;
            end if;
        end procedure;

    begin
        sw_a <= "0000";                           -- Server
        sw_b <= "0001";                           -- Client
        wait for 100 ns;
        rstn <= '1';

        -- PHY-Takt 25 MHz und PHY-Reset
        wait until rising_edge(ref_a);
        t0 := now;
        wait until rising_edge(ref_a);
        assert now - t0 = 40 ns report "eth_ref_clk ist nicht 25 MHz" severity error;
        assert rstn_a = '0' report "PHY-Reset fehlt nach dem Einschalten" severity error;
        wait until rstn_a = '1' for 1 ms;
        assert rstn_a = '1' and now > 90 us report "PHY-Reset falsch" severity error;
        report "PHY-Takt und -Reset: OK";

        -- 1: Verbindung, beide Displays gleich
        frames(SB, 4);
        assert tx_frames(SA) > 2 and tx_frames(SB) > 2 report "1: zu wenige Rahmen" severity error;
        led_snap;
        frames(SB, 1);
        led_check("1", true, true);
        n := diff(fb_a, fb_b);
        assert n = 0 report "1: Client-Bild weicht ab (" & integer'image(n) & " Bytes)" severity error;
        assert pad_top(fb_b, 4) = 25 and pad_top(fb_b, 91) = 25 and ball_seen(fb_b)
            report "1: Client zeigt Grundstellung nicht" severity error;
        report "1 Verbindung, Client zeigt Server-Bild: OK";

        -- 2: Client drueckt runter, Server drueckt links hoch UND btn2 (soll ignoriert werden)
        btn_b <= "0010";
        btn_a <= "0101";
        frames(SA, 4);
        btn_a <= "0000";
        btn_b <= "0000";
        frames(SB, 3);
        la   := pad_top(fb_a, 4);
        ra_y := pad_top(fb_a, 91);
        assert la >= 0 and la < 25 report "2: linker Schlaeger nicht hoch" severity error;
        assert ra_y > 25 report "2: Client steuert rechten Schlaeger nicht (btn2 am Server aktiv?)"
            severity error;
        n := diff(fb_a, fb_b);
        assert n = 0 report "2: Client-Bild weicht ab (" & integer'image(n) & " Bytes)" severity error;
        report "2 Client steuert rechten Schlaeger: OK (links " & integer'image(la) &
               ", rechts " & integer'image(ra_y) & ")";

        -- 3: Rahmen vom Server gestoert -> CRC falsch -> Client verwirft alles
        cable_ab <= 1;
        frames(SB, TIMEOUT + 2);
        led_snap;
        on_seen := false; off_seen := false;
        for k in 1 to 10 loop
            frames(SB, 1);
            if ball_seen(fb_b) then on_seen := true; else off_seen := true; end if;
        end loop;
        led_check("3", true, false);
        assert pad_top(fb_b, 4) = 25 and pad_top(fb_b, 91) = 25
            report "3: Client ohne Server zeigt nicht die Grundstellung" severity error;
        assert on_seen and off_seen report "3: Ball blinkt nicht" severity error;
        report "3 gestoerte Rahmen verworfen, Client wartet: OK";

        -- 4: Kabel ganz getrennt -> Server spielt lokal, btn2 bewegt rechten Schlaeger
        cable_ab <= 2;
        cable_ba <= 2;
        frames(SA, TIMEOUT + 2);
        led_snap;
        ra_y := pad_top(fb_a, 91);
        btn_a <= "0100";
        frames(SA, 3);
        btn_a <= "0000";
        frames(SA, 1);
        led_check("4", false, false);
        assert pad_top(fb_a, 91) < ra_y report "4: Server ohne Client - btn2 wirkt nicht" severity error;
        report "4 getrennt, Server spielt lokal: OK";

        -- 5: wieder verbinden
        cable_ab <= 0;
        cable_ba <= 0;
        frames(SB, 3);
        led_snap;
        frames(SB, 1);
        led_check("5", true, true);
        assert pad_top(fb_b, 4) = pad_top(fb_a, 4) and pad_top(fb_b, 91) = pad_top(fb_a, 91)
            report "5: Client zeigt nach Wiederverbinden andere Schlaeger" severity error;
        report "5 wieder verbunden: OK";

        -- 6: Client ohne OLED (sw1): Display aus, LEDs zeigen Punkte, Tasten wirken weiter
        sw_b <= "0011";
        frames(SA, 2);
        n := fc_b;
        led_snap;
        ra_y := pad_top(fb_a, 91);
        btn_b <= "0001";                          -- btn0 = hoch
        frames(SA, 3);
        btn_b <= "0000";
        frames(SA, 1);
        assert pm_b = '0' and vcc_b = '0' and cs_b = '0' and sck_b = '0'
            report "6: Display-Pins des Clients nicht aus" severity error;
        assert fc_b = n report "6: Client sendet ohne OLED weiter Bilder" severity error;
        assert led_b = "0000" report "6: LEDs des Clients zeigen nicht den Punktestand (0)" severity error;
        assert pad_top(fb_a, 91) < ra_y report "6: Client ohne OLED steuert den Schlaeger nicht" severity error;
        led_check("6", true, true);
        report "6 Client ohne OLED: OK";

        report "Rahmen gesendet: Server " & integer'image(tx_frames(SA)) & ", Client " & integer'image(tx_frames(SB));
        report "ALLE TESTS ABGESCHLOSSEN";
        finish;
    end process;

    process
    begin
        wait for 400 ms;
        report "Timeout" severity failure;
    end process;

end architecture sim;
