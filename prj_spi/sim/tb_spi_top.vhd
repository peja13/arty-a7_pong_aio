----------------------------------------------------------------------------------
-- Testbench    : tb_spi_top
-- Beschreibung : Ein Board. SSD1331-Modell (SPI-Mode 3) empfaengt Kommandos und
--                Pixeldaten, ein Mitschnitt prueft jeden gesendeten Ethernet-Rahmen
--                (FCS mit eigener CRC), ein "Test-Server" speist Rahmen ein.
--   Geprueft: Init-Sequenz und Bildformat; Server (sw0 = 0): Pong-Bild, Schlaeger
--   mit btn0 und - ohne Client - btn2, Server sendet Spielzustand, LD0 rot;
--   Client (sw0 = 1): zeigt den eingespeisten Zustand, sendet seine Tasten, LD0
--   gruen; Client ohne OLED (sw0 = sw1 = 1): Display-Pins aus, LEDs zeigen den
--   Punktestand, sendet weiter; Zeitueberwachung; Display startet wieder.
--   (Zwei Boards ueber LAN: tb_lan_pong)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.env.all;

use work.eth_pkg.all;

entity tb_spi_top is
end entity tb_spi_top;

architecture sim of tb_spi_top is

    constant WHITE : std_logic_vector(15 downto 0) := x"FFFF";
    constant BLACK : std_logic_vector(15 downto 0) := x"0000";

    signal clk  : std_logic := '0';
    signal rstn : std_logic := '0';
    signal sw   : std_logic_vector(3 downto 0) := "0000";
    signal btn  : std_logic_vector(3 downto 0) := "0000";
    signal led  : std_logic_vector(3 downto 0);

    signal oled_cs, oled_mosi, oled_sck, oled_dc : std_logic;
    signal oled_res, oled_vccen, oled_pmoden     : std_logic;

    -- Ethernet: PHY-Takt 25 MHz, Test-Server speist RXD ein
    signal eth_clk    : std_logic := '0';
    signal eth_ref    : std_logic;
    signal eth_rstn   : std_logic;
    signal eth_tx_en  : std_logic;
    signal eth_txd    : std_logic_vector(3 downto 0);
    signal rx_dv      : std_logic := '0';
    signal rxd        : std_logic_vector(3 downto 0) := "0000";
    signal inject     : boolean := false;
    signal led0_r     : std_logic;
    signal led0_g     : std_logic;
    signal r_on, g_on : natural := 0;
    signal sck_edges  : natural := 0;

    -- Mitschnitt der gesendeten Rahmen
    signal tx_frames  : natural := 0;
    signal txb        : byte_arr_t(0 to 63) := (others => x"00");

    type fb_arr is array (natural range <>) of std_logic_vector(7 downto 0);
    signal fb      : fb_arr(0 to 12287) := (others => (others => '0'));
    signal cmds    : fb_arr(0 to 255)   := (others => (others => '0'));
    signal cmd_cnt   : natural := 0;
    signal frame_cnt : natural := 0;

    -- Zustand, den der Test-Server schickt
    constant S_PL : natural := 10;
    constant S_PR : natural := 40;
    constant S_BX : natural := 20;
    constant S_BY : natural := 15;
    constant S_SL : natural := 3;
    constant S_SR : natural := 5;

    impure function px (x, y : natural) return std_logic_vector is
        constant i : natural := 2 * (y * 96 + x);
    begin
        return fb(i) & fb(i + 1);
    end function;

    -- oberste weisse Zeile in Spalte x (Schlaegerkante)
    impure function pad_top (x : natural) return natural is
    begin
        for y in 0 to 63 loop
            if px(x, y) = WHITE then
                return y;
            end if;
        end loop;
        return 0;
    end function;

    -- Referenz: CRC-32 byteweise (Ergebnis bereits invertiert = FCS)
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

    function b8 (v : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(v, 8));
    end function;

begin

    clk     <= not clk after 5 ns;
    eth_clk <= not eth_clk after 20 ns;

    dut : entity work.spi_top
        generic map (CLK_HZ => 1_000_000, SPI_HALF => 2)
        port map (
            CLK100MHZ   => clk,
            ck_rst      => rstn,
            sw          => sw,
            btn         => btn,
            led         => led,
            oled_cs     => oled_cs,
            oled_mosi   => oled_mosi,
            oled_sck    => oled_sck,
            oled_dc     => oled_dc,
            oled_res    => oled_res,
            oled_vccen  => oled_vccen,
            oled_pmoden => oled_pmoden,
            led0_r      => led0_r,
            led0_g      => led0_g,
            eth_ref_clk => eth_ref,
            eth_rstn    => eth_rstn,
            eth_tx_clk  => eth_clk,
            eth_tx_en   => eth_tx_en,
            eth_txd     => eth_txd,
            eth_rx_clk  => eth_clk,
            eth_rx_dv   => rx_dv,
            eth_rxd     => rxd,
            eth_rxerr   => '0'
        );

    process (clk)
    begin
        if rising_edge(clk) then
            if led0_r = '1' then r_on <= r_on + 1; end if;
            if led0_g = '1' then g_on <= g_on + 1; end if;
        end if;
    end process;

    process (oled_sck)
    begin
        if oled_sck'event then
            sck_edges <= sck_edges + 1;
        end if;
    end process;

    ------------------------------------------------------------------
    -- SSD1331-Modell
    ------------------------------------------------------------------
    process (oled_sck, oled_cs)
        variable sh   : std_logic_vector(7 downto 0) := (others => '0');
        variable bits : natural := 0;
        variable dcnt : natural := 0;
        variable ccnt : natural := 0;
    begin
        if oled_cs = '1' then
            bits := 0;
        elsif rising_edge(oled_sck) then
            sh   := sh(6 downto 0) & oled_mosi;
            bits := bits + 1;
            if bits = 8 then
                bits := 0;
                if oled_dc = '0' then
                    if ccnt = 0 then
                        assert oled_pmoden = '1' and oled_res = '1'
                            report "Erstes Kommando ohne PMODEN/RES" severity error;
                    end if;
                    if sh = x"AF" then
                        assert oled_vccen = '1' report "Display ein ohne VCCEN" severity error;
                    end if;
                    if ccnt <= cmds'high then     -- nur die ersten 256 Kommandos merken
                        cmds(ccnt) <= sh;
                    end if;
                    dcnt := 0;                    -- Fensterkommando: Schreibzeiger auf Pixel 0
                    ccnt    := ccnt + 1;
                    cmd_cnt <= ccnt;
                else
                    fb(dcnt) <= sh;
                    dcnt := dcnt + 1;
                    if dcnt = 12288 then
                        dcnt := 0;
                        frame_cnt <= frame_cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Mitschnitt: jeden gesendeten Rahmen auf Laenge und FCS pruefen
    ------------------------------------------------------------------
    process (eth_clk)
        variable act : boolean := false;
        variable sfd : boolean := false;
        variable pre : natural := 0;
        variable nib : natural := 0;
        variable lo  : std_logic_vector(3 downto 0);
        variable b   : byte_arr_t(0 to 127);
        variable fcs : std_logic_vector(31 downto 0);
    begin
        if rising_edge(eth_clk) then
            if eth_tx_en = '1' then
                if not act then
                    act := true; sfd := false; pre := 0; nib := 0;
                end if;
                if not sfd then
                    if eth_txd = x"5" then pre := pre + 1; elsif eth_txd = x"D" then sfd := true; end if;
                else
                    if nib mod 2 = 0 then
                        lo := eth_txd;
                    elsif nib / 2 <= 127 then
                        b(nib / 2) := eth_txd & lo;
                    end if;
                    nib := nib + 1;
                end if;
            elsif act then
                act := false;
                fcs := crc_ref(b, 60);
                assert sfd and pre = 15 and nib = 128 report "TX: Rahmenlaenge/Praeambel falsch" severity error;
                assert b(60) = fcs(7 downto 0) and b(61) = fcs(15 downto 8) and
                       b(62) = fcs(23 downto 16) and b(63) = fcs(31 downto 24)
                    report "TX: FCS falsch" severity error;
                txb       <= b(0 to 63);
                tx_frames <= tx_frames + 1;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Test-Server: schickt alle 300 us einen Spielzustand (Art 1)
    ------------------------------------------------------------------
    process
        variable f   : byte_arr_t(0 to 63);
        variable fcs : std_logic_vector(31 downto 0);
        variable seq : natural := 0;
    begin
        wait until inject;
        while inject loop
            f := (others => x"00");
            f(0 to 5)   := (others => x"FF");
            f(6 to 11)  := (x"02", x"50", x"4F", x"4E", x"47", x"01");
            f(12 to 13) := (x"88", x"B5");
            f(14 to 17) := (x"50", x"4F", x"4E", x"47");
            f(18) := x"01";
            f(19) := x"01";
            f(20) := b8(seq mod 256);
            f(21) := b8(S_PL); f(22) := b8(S_PR); f(23) := b8(S_BX);
            f(24) := b8(S_BY); f(25) := b8(S_SL); f(26) := b8(S_SR);
            fcs := crc_ref(f, 60);
            f(60) := fcs(7 downto 0);   f(61) := fcs(15 downto 8);
            f(62) := fcs(23 downto 16); f(63) := fcs(31 downto 24);
            seq := seq + 1;
            -- Nibbles bei fallender Flanke anlegen (stabil zur steigenden)
            wait until falling_edge(eth_clk);
            rx_dv <= '1';
            for k in 0 to 14 loop
                rxd <= x"5";
                wait until falling_edge(eth_clk);
            end loop;
            rxd <= x"D";
            wait until falling_edge(eth_clk);
            for k in 0 to 63 loop
                rxd <= f(k)(3 downto 0);
                wait until falling_edge(eth_clk);
                rxd <= f(k)(7 downto 4);
                wait until falling_edge(eth_clk);
            end loop;
            rx_dv <= '0';
            rxd   <= x"0";
            wait for 300 us;
        end loop;
    end process;

    ------------------------------------------------------------------
    -- Stimulus und Pruefungen
    ------------------------------------------------------------------
    process
        variable f      : natural;
        variable found  : boolean;
        variable n0, r0, g0, e0 : natural;
    begin
        wait for 100 ns;
        rstn <= '1';

        -- Bild 1: sw0 = 0 -> Server, Pong-Grundstellung
        wait until frame_cnt = 1;
        assert cmds(0) = x"AE" report "Init: erstes Kommando /= AE" severity error;
        assert cmds(37) = x"AF" report "Init: Display-ein fehlt" severity error;
        assert cmd_cnt = 44 report "Anzahl Kommandos Bild 1: " & integer'image(cmd_cnt) severity error;
        assert cmds(38) = x"15" and cmds(39) = x"00" and cmds(40) = x"5F" and
               cmds(41) = x"75" and cmds(42) = x"00" and cmds(43) = x"3F"
            report "Fenster-Kommandos falsch" severity error;
        assert px(4, 30) = WHITE and px(0, 0) = BLACK and px(91, 30) = WHITE and px(10, 10) = BLACK and
               px(47, 31) = WHITE
            report "Bild 1: Pong-Grundstellung falsch" severity error;
        assert px(4, 24) = BLACK and px(4, 39) = BLACK report "Bild 1: Schlaegerhoehe falsch" severity error;
        assert led = "0000" report "LEDs spiegeln die Schalter nicht" severity error;
        report "Bild 1 (Init, Server-Grundstellung): OK";

        -- Server: btn0 4 Bilder lang -> linker Schlaeger 12 Pixel hoeher, rechter bleibt
        btn <= "0001";
        f := frame_cnt;
        wait until frame_cnt = f + 5;
        assert px(4, 14) = WHITE and px(4, 12) = BLACK and px(4, 26) = WHITE and px(4, 28) = BLACK
            report "Server: btn0 bewegt linken Schlaeger falsch" severity error;
        assert px(91, 30) = WHITE and px(91, 24) = BLACK
            report "Server: rechter Schlaeger bewegt sich ohne Taste" severity error;
        btn <= "0000";

        -- Server ohne Client: btn2 bewegt den rechten Schlaeger, Server sendet Zustand, LD0 rot
        n0 := tx_frames; r0 := r_on; g0 := g_on;
        btn <= "0100";
        f := frame_cnt;
        wait until frame_cnt = f + 3;
        btn <= "0000";
        assert px(91, 24) = WHITE report "Server: btn2 bewegt rechten Schlaeger nicht" severity error;
        assert tx_frames >= n0 + 2 report "Server sendet keine Rahmen" severity error;
        assert txb(11) = x"01" and txb(19) = x"01" and txb(21) = b8(pad_top(4)) and txb(22) = b8(pad_top(91))
            report "Server: Rahmen enthaelt nicht den angezeigten Spielzustand" severity error;
        assert r_on > r0 and g_on = g0 report "Server: LD0 nicht rot" severity error;
        report "Server (sw0 = 0): OK";

        -- Client mit OLED, Test-Server schickt einen Zustand
        sw     <= "0001";
        inject <= true;
        f := frame_cnt;
        wait until frame_cnt = f + 3;
        n0 := tx_frames; r0 := r_on; g0 := g_on;
        btn <= "0100";                            -- btn2 = hoch beim Client
        wait until frame_cnt = f + 4;
        assert px(4, 10) = WHITE and px(4, 9) = BLACK and px(4, 23) = WHITE and px(4, 24) = BLACK
            report "Client: linker Schlaeger nicht wie vom Server" severity error;
        assert px(91, 40) = WHITE and px(91, 39) = BLACK and px(91, 53) = WHITE and px(91, 54) = BLACK
            report "Client: rechter Schlaeger nicht wie vom Server" severity error;
        assert px(20, 15) = WHITE and px(22, 17) = WHITE and px(19, 15) = BLACK and px(46, 30) = BLACK
            report "Client: Ball nicht wie vom Server" severity error;
        assert tx_frames >= n0 + 1 and txb(11) = x"02" and txb(19) = x"02" and txb(27) = x"01"
            report "Client: sendet seine Tasten nicht" severity error;
        assert g_on > g0 and r_on = r0 report "Client: LD0 nicht gruen" severity error;
        assert led = "0001" report "Client: LEDs spiegeln die Schalter nicht" severity error;
        btn <= "0000";
        report "Client mit OLED (sw0 = 1): OK";

        -- Client ohne OLED: Display-Pins aus, LEDs = Punktestand, sendet weiter
        sw <= "0011";
        wait for 1 ms;
        n0 := tx_frames; r0 := r_on; g0 := g_on; e0 := sck_edges; f := frame_cnt;
        btn <= "0010";                            -- btn1 = runter
        wait for 2 ms;
        assert oled_pmoden = '0' and oled_vccen = '0' and oled_res = '0' and oled_cs = '0' and
               oled_sck = '0' and sck_edges = e0
            report "ohne OLED: Display-Pins nicht aus" severity error;
        assert frame_cnt = f report "ohne OLED: es werden weiter Bilder gesendet" severity error;
        assert led = std_logic_vector(to_unsigned(S_SR, 4))
            report "ohne OLED: LEDs zeigen nicht den Punktestand" severity error;
        assert tx_frames >= n0 + 3 and txb(19) = x"02" and txb(27) = x"02"
            report "ohne OLED: Client sendet keine Tasten" severity error;
        assert g_on > g0 and r_on = r0 report "ohne OLED: LD0 nicht gruen" severity error;
        btn <= "0000";
        report "Client ohne OLED (sw0 = sw1 = 1): OK";

        -- Server schweigt -> nach 15 Bildern getrennt: LD0 rot, Punktestand 0
        inject <= false;
        wait for 4 ms;
        r0 := r_on; g0 := g_on;
        wait for 100 us;
        assert r_on > r0 and g_on = g0 report "Zeitueberwachung: LD0 nicht rot" severity error;
        assert led = "0000" report "Zeitueberwachung: LEDs nicht 0" severity error;
        report "Zeitueberwachung: OK";

        -- wieder mit OLED: Display startet neu und zeigt die Grundstellung
        sw <= "0001";
        found := false;
        f := frame_cnt;
        wait until frame_cnt = f + 2;
        assert px(4, 25) = WHITE and px(4, 24) = BLACK and px(91, 25) = WHITE and px(91, 38) = WHITE
            report "Display nach Neustart: keine Grundstellung" severity error;
        report "Display wieder an: OK";

        report "ALLE TESTS ABGESCHLOSSEN";
        finish;
    end process;

    process
    begin
        wait for 400 ms;
        report "Timeout" severity failure;
    end process;

end architecture sim;
