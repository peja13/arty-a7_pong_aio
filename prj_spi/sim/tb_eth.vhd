----------------------------------------------------------------------------------
-- Testbench    : tb_eth
-- Beschreibung : eth_tx sendet ueber ein Kabelmodell an eth_rx.
--                Geprueft werden Praeambel/SFD, Rahmenlaenge, FCS (gegen eine
--                eigene, byteweise CRC-32), Empfang mit verkuerzter Praeambel,
--                Verwerfen bei Bitfehler, RX_ER und abgeschnittenem Rahmen,
--                zwei Rahmen direkt hintereinander und 10 Mbit/s (2,5 MHz).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.env.all;

use work.eth_pkg.all;

entity tb_eth is
end entity tb_eth;

architecture sim of tb_eth is

    signal t_half  : time := 20 ns;               -- 25 MHz
    signal tx_clk  : std_logic := '0';
    signal rx_clk  : std_logic := '0';

    signal frame   : byte_arr_t(0 to ETH_FRAME_LEN - 1) := (others => x"00");
    signal req_t   : std_logic := '0';
    signal ack_t   : std_logic;
    signal txd     : std_logic_vector(3 downto 0);
    signal tx_en   : std_logic;

    signal rxd     : std_logic_vector(3 downto 0) := "0000";
    signal rx_dv   : std_logic := '0';
    signal rx_er   : std_logic := '0';
    signal data    : byte_arr_t(0 to 27);
    signal ok_t    : std_logic;
    signal rx_cnt  : natural := 0;

    -- Kabelmodell (Nibble-Nummern ab dem ersten Datennibble nach dem SFD)
    signal drop_pre : natural := 0;               -- verschluckte Praeambel-Nibbles
    signal flip_at  : integer := -1;              -- dieses Nibble wird verfaelscht
    signal er_at    : integer := -1;              -- hier meldet der PHY RX_ER
    signal cut_at   : integer := -1;              -- Rahmen ab hier abgeschnitten

    -- Mitschnitt des gesendeten Rahmens
    signal cap     : byte_arr_t(0 to 127) := (others => x"00");
    signal cap_len : natural := 0;                -- Bytes nach dem SFD
    signal cap_pre : natural := 0;                -- Nibbles 5 vor dem SFD
    signal cap_sfd : boolean := false;
    signal tx_cnt  : natural := 0;

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

    function ascii (s : string) return byte_arr_t is
        variable r : byte_arr_t(0 to s'length - 1);
    begin
        for i in 0 to s'length - 1 loop
            r(i) := std_logic_vector(to_unsigned(character'pos(s(s'low + i)), 8));
        end loop;
        return r;
    end function;

begin

    tx_clk <= not tx_clk after t_half;
    rx_clk <= transport tx_clk after 3 ns;        -- Empfangstakt kommt vom Sender

    dut_tx : entity work.eth_tx
        port map (tx_clk => tx_clk, frame => frame, req_t => req_t, ack_t => ack_t,
                  txd => txd, tx_en => tx_en);

    dut_rx : entity work.eth_rx
        port map (rx_clk => rx_clk, rxd => rxd, rx_dv => rx_dv, rx_er => rx_er,
                  data => data, ok_t => ok_t);

    process (ok_t)
    begin
        if ok_t'event then
            rx_cnt <= rx_cnt + 1;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Kabel: TXD wird bei steigender TX_CLK-Flanke gelesen (wie im PHY) und
    -- 12 ns spaeter auf RXD ausgegeben.
    ------------------------------------------------------------------
    process (tx_clk)
        variable pos : integer := 0;
        variable d   : integer;
        variable n   : std_logic_vector(3 downto 0);
        variable dv  : std_logic;
    begin
        if rising_edge(tx_clk) then
            if tx_en = '1' then
                d  := pos - 16;
                n  := txd;
                dv := '1';
                if pos < drop_pre or (cut_at >= 0 and d >= cut_at) then
                    dv := '0';
                end if;
                if flip_at >= 0 and d = flip_at then
                    n(0) := not n(0);
                end if;
                if er_at >= 0 and d = er_at then
                    rx_er <= transport '1' after 12 ns;
                else
                    rx_er <= transport '0' after 12 ns;
                end if;
                rxd   <= transport n after 12 ns;
                rx_dv <= transport dv after 12 ns;
                pos   := pos + 1;
            else
                rxd   <= transport "0000" after 12 ns;
                rx_dv <= transport '0' after 12 ns;
                rx_er <= transport '0' after 12 ns;
                pos   := 0;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Mitschnitt des Senders
    ------------------------------------------------------------------
    process (tx_clk)
        variable act  : boolean := false;
        variable sfd  : boolean := false;
        variable pre  : natural := 0;
        variable nib  : natural := 0;
        variable lo   : std_logic_vector(3 downto 0);
        variable buf  : byte_arr_t(0 to 127);
    begin
        if rising_edge(tx_clk) then
            if tx_en = '1' then
                if not act then
                    act := true;
                    sfd := false;
                    pre := 0;
                    nib := 0;
                end if;
                if not sfd then
                    if txd = x"5" then
                        pre := pre + 1;
                    elsif txd = x"D" then
                        sfd := true;
                    end if;
                else
                    if nib mod 2 = 0 then
                        lo := txd;
                    elsif nib / 2 <= 127 then
                        buf(nib / 2) := txd & lo;
                    end if;
                    nib := nib + 1;
                end if;
            elsif act then
                act     := false;
                cap     <= buf;
                cap_len <= nib / 2;
                cap_pre <= pre;
                cap_sfd <= sfd;
                tx_cnt  <= tx_cnt + 1;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Ablauf
    ------------------------------------------------------------------
    process
        variable fcs   : std_logic_vector(31 downto 0);
        variable r0    : natural;
        variable t0    : natural;

        procedure send is
        begin
            wait for 50 ns;
            req_t <= not req_t;
            wait until ack_t = req_t;
            wait for 2 us;
        end procedure;

        procedure check_tx (name : string) is
        begin
            assert cap_sfd and cap_pre = 15
                report name & ": Praeambel/SFD falsch (" & integer'image(cap_pre) & " x 5)" severity error;
            assert cap_len = ETH_FRAME_LEN + 4
                report name & ": Rahmenlaenge " & integer'image(cap_len) severity error;
            for i in 0 to ETH_FRAME_LEN - 1 loop
                assert cap(i) = frame(i)
                    report name & ": Byte " & integer'image(i) & " falsch gesendet" severity error;
            end loop;
            fcs := crc_ref(frame, ETH_FRAME_LEN);
            assert cap(60) = fcs(7 downto 0) and cap(61) = fcs(15 downto 8) and
                   cap(62) = fcs(23 downto 16) and cap(63) = fcs(31 downto 24)
                report name & ": FCS falsch" severity error;
        end procedure;

        procedure check_rx (name : string; expect : boolean) is
        begin
            if expect then
                assert rx_cnt = r0 + 1 report name & ": Rahmen nicht empfangen" severity error;
                for i in 0 to 27 loop
                    assert data(i) = frame(i)
                        report name & ": Byte " & integer'image(i) & " falsch empfangen" severity error;
                end loop;
            else
                assert rx_cnt = r0 report name & ": fehlerhafter Rahmen wurde angenommen" severity error;
            end if;
        end procedure;

    begin
        -- Referenz-CRC selbst pruefen (Standard-Pruefwert von CRC-32)
        assert crc_ref(ascii("123456789"), 9) = x"CBF43926"
            report "Referenz-CRC falsch" severity failure;

        for i in 0 to ETH_FRAME_LEN - 1 loop
            frame(i) <= std_logic_vector(to_unsigned((i * 37 + 11) mod 256, 8));
        end loop;
        frame(0 to 5) <= (others => x"FF");
        wait for 1 us;

        -- 1: normaler Rahmen
        r0 := rx_cnt; t0 := tx_cnt;
        send;
        assert tx_cnt = t0 + 1 report "1: kein Rahmen gesendet" severity error;
        check_tx("1");
        check_rx("1", true);
        report "1 Rahmen senden/empfangen: OK";

        -- 2: PHY verschluckt Teile der Praeambel
        frame(30) <= x"A5";
        drop_pre <= 9;
        r0 := rx_cnt;
        send;
        check_tx("2");
        check_rx("2", true);
        drop_pre <= 0;
        report "2 verkuerzte Praeambel: OK";

        -- 3: Bitfehler in den Daten, 4: Bitfehler in der FCS
        flip_at <= 50;
        r0 := rx_cnt;
        send;
        check_rx("3", false);
        flip_at <= 2 * ETH_FRAME_LEN + 5;
        r0 := rx_cnt;
        send;
        check_rx("4", false);
        flip_at <= -1;
        report "3/4 Bitfehler werden verworfen: OK";

        -- 5: RX_ER vom PHY
        er_at <= 31;
        r0 := rx_cnt;
        send;
        check_rx("5", false);
        er_at <= -1;
        report "5 RX_ER wird verworfen: OK";

        -- 6: Rahmen abgeschnitten (Laenge falsch)
        cut_at <= 100;
        r0 := rx_cnt;
        send;
        check_rx("6", false);
        cut_at <= -1;
        report "6 abgeschnittener Rahmen wird verworfen: OK";

        -- 7: zwei Rahmen direkt hintereinander
        r0 := rx_cnt; t0 := tx_cnt;
        wait for 50 ns;
        req_t <= not req_t;
        wait until ack_t = req_t;
        frame(40) <= x"3C";
        wait for 1 ns;
        req_t <= not req_t;
        wait until ack_t = req_t;
        wait for 2 us;
        assert tx_cnt = t0 + 2 and rx_cnt = r0 + 2
            report "7: Rahmen hintereinander verloren" severity error;
        assert data(27) = frame(27) report "7: Daten falsch" severity error;
        report "7 zwei Rahmen hintereinander: OK";

        -- 8: 10 Mbit/s (2,5 MHz)
        t_half <= 200 ns;
        frame(25) <= x"5A";
        wait for 1 us;
        r0 := rx_cnt;
        send;
        wait for 10 us;
        check_tx("8");
        check_rx("8", true);
        report "8 10 Mbit/s: OK";

        report "ALLE TESTS ABGESCHLOSSEN";
        finish;
    end process;

    process
    begin
        wait for 2 ms;
        report "Timeout" severity failure;
    end process;

end architecture sim;
