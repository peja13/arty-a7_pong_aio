----------------------------------------------------------------------------------
-- Modul        : lan_link
-- Beschreibung : LAN-Verbindung fuer Pong zwischen zwei Arty A7 (Server und Client).
--                Erzeugt Takt (25 MHz) und Reset fuer den PHY, verpackt den
--                Spielzustand bzw. die Tasten in Ethernet-Rahmen und wertet die
--                Rahmen des Partners aus.
--
--   Server : sendet nach jedem Bild den Spielzustand (Typ 1),
--            empfaengt die Tasten des Clients (Typ 2).
--   Client : sendet nach jedem Bild und bei jeder Tastenaenderung seine Tasten,
--            empfaengt den Spielzustand.
--
-- Rahmen (64 Byte, Broadcast, kein IP noetig - Direktkabel oder Switch):
--    0..5   FF FF FF FF FF FF   Ziel: alle
--    6..11  02 50 4F 4E 47 0R   Quelle, R = 1 Server / 2 Client
--   12..13  88 B5               EtherType "lokal/experimentell" (IEEE 802)
--   14..17  50 4F 4E 47         "PONG"
--   18      01                  Protokollversion
--   19      01 / 02             Typ: 1 = Spielzustand, 2 = Tasten
--   20      Folgenummer
--   21..26  pl_y pr_y bx by score_l score_r   (nur Typ 1)
--   27      Bit 0 = hoch, Bit 1 = runter      (nur Typ 2)
--   28..59  00                  Auffuellen auf Mindestlaenge
--   60..63  FCS (CRC-32)
--
-- peer_ok = 1, solange in den letzten TIMEOUT_FRAMES Bildern ein gueltiger
-- Rahmen des Partners ankam.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.eth_pkg.all;
use work.pong_pkg.all;

entity lan_link is
    generic (
        PHY_RST_CYCLES : positive := 1_000_000;   -- PHY-Reset 10 ms bei 100 MHz
        TIMEOUT_FRAMES : positive := 15           -- ca. 0,3 s ohne Partner = getrennt
    );
    port (
        clk         : in  std_logic;              -- 100 MHz
        rst         : in  std_logic;
        enable      : in  std_logic;              -- 1 = Pong-Modus
        client      : in  std_logic;              -- 0 = Server, 1 = Client
        frame_tick  : in  std_logic;
        st_tx       : in  pong_state_t;           -- Server: eigener Spielzustand
        btn_tx      : in  std_logic_vector(1 downto 0);   -- Client: (1) runter, (0) hoch
        st_rx       : out pong_state_t;           -- Client: Zustand vom Server
        btn_rx      : out std_logic_vector(1 downto 0);   -- Server: Tasten vom Client
        peer_ok     : out std_logic;
        -- PHY (MII)
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
end entity lan_link;

architecture rtl of lan_link is

    constant CAP        : positive := 28;
    constant TYPE_STATE : std_logic_vector(7 downto 0) := x"01";
    constant TYPE_INPUT : std_logic_vector(7 downto 0) := x"02";

    constant HDR : byte_arr_t(0 to 18) := (
        x"FF", x"FF", x"FF", x"FF", x"FF", x"FF",
        x"02", x"50", x"4F", x"4E", x"47", x"00",
        x"88", x"B5",
        x"50", x"4F", x"4E", x"47",
        x"01");

    -- PHY-Takt und -Reset
    signal ref_div : unsigned(1 downto 0) := "00";
    signal rst_cnt : natural range 0 to PHY_RST_CYCLES := 0;
    signal rstn_r  : std_logic := '0';

    -- Senden
    signal txf     : byte_arr_t(0 to ETH_FRAME_LEN - 1) := (others => x"00");
    signal req_t   : std_logic := '0';
    signal ack_t   : std_logic;
    signal ack_s   : std_logic_vector(1 downto 0) := "00";
    signal pending : std_logic := '0';
    signal fire    : std_logic := '0';
    signal seq     : unsigned(7 downto 0) := (others => '0');
    signal tick_d  : std_logic_vector(1 downto 0) := "00";
    signal btn_q   : std_logic_vector(1 downto 0) := "00";

    -- Empfangen
    signal rx_data : byte_arr_t(0 to CAP - 1);
    signal rx_t    : std_logic;
    signal rx_s    : std_logic_vector(1 downto 0) := "00";
    signal rx_q    : std_logic := '0';
    signal rxb     : byte_arr_t(0 to CAP - 1) := (others => x"00");
    signal parse   : std_logic := '0';
    signal lost    : natural range 0 to TIMEOUT_FRAMES := TIMEOUT_FRAMES;
    signal client_q : std_logic := '0';

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of ack_s : signal is "TRUE";
    attribute ASYNC_REG of rx_s  : signal is "TRUE";

    function hdr_ok (b : byte_arr_t(0 to CAP - 1)) return boolean is
    begin
        for i in 0 to 5 loop
            if b(i) /= x"FF" then
                return false;
            end if;
        end loop;
        for i in 12 to 18 loop
            if b(i) /= HDR(i) then
                return false;
            end if;
        end loop;
        return true;
    end function;

    function clip (b : std_logic_vector(7 downto 0); max : natural) return natural is
    begin
        if to_integer(unsigned(b)) > max then
            return max;
        end if;
        return to_integer(unsigned(b));
    end function;

    function to_byte (v : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(v, 8));
    end function;

begin

    ------------------------------------------------------------------
    -- 25 MHz fuer den PHY (100 MHz / 4) und PHY-Reset nach dem Einschalten
    ------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            ref_div <= ref_div + 1;
            if rst = '1' then
                rst_cnt <= 0;
                rstn_r  <= '0';
            elsif rst_cnt = PHY_RST_CYCLES then
                rstn_r <= '1';
            else
                rst_cnt <= rst_cnt + 1;
                rstn_r  <= '0';
            end if;
        end if;
    end process;

    eth_ref_clk <= ref_div(1);
    eth_rstn    <= rstn_r;

    ------------------------------------------------------------------
    -- Senden: Rahmen zusammenstellen, dann Auftrag an eth_tx kippen
    ------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            tick_d <= tick_d(0) & frame_tick;     -- 2 Takte spaeter ist der neue Zustand da
            ack_s  <= ack_s(0) & ack_t;
            btn_q  <= btn_tx;

            if fire = '1' then
                fire  <= '0';
                req_t <= not req_t;
            elsif pending = '1' and ack_s(1) = req_t then   -- eth_tx frei
                for i in HDR'range loop
                    txf(i) <= HDR(i);
                end loop;
                txf(20) <= std_logic_vector(seq);
                seq     <= seq + 1;
                if client = '1' then
                    txf(11) <= x"02";
                    txf(19) <= TYPE_INPUT;
                    for i in 21 to 26 loop
                        txf(i) <= x"00";
                    end loop;
                    txf(27) <= "000000" & btn_tx;
                else
                    txf(11) <= x"01";
                    txf(19) <= TYPE_STATE;
                    txf(21) <= to_byte(st_tx.pl_y);
                    txf(22) <= to_byte(st_tx.pr_y);
                    txf(23) <= to_byte(st_tx.bx);
                    txf(24) <= to_byte(st_tx.by);
                    txf(25) <= to_byte(st_tx.score_l);
                    txf(26) <= to_byte(st_tx.score_r);
                    txf(27) <= x"00";
                end if;
                for i in 28 to ETH_FRAME_LEN - 1 loop
                    txf(i) <= x"00";
                end loop;
                pending <= '0';
                fire    <= '1';
            end if;

            -- neuer Anlass zum Senden (nach dem Loeschen oben, damit nichts verloren geht)
            if enable = '0' then
                pending <= '0';
            elsif tick_d(1) = '1' or (client = '1' and btn_tx /= btn_q) then
                pending <= '1';
            end if;
        end if;
    end process;

    u_tx : entity work.eth_tx
        port map (
            tx_clk => eth_tx_clk,
            frame  => txf,
            req_t  => req_t,
            ack_t  => ack_t,
            txd    => eth_txd,
            tx_en  => eth_tx_en
        );

    ------------------------------------------------------------------
    -- Empfangen: gueltige Rahmen uebernehmen, Partner-Zeitueberwachung
    ------------------------------------------------------------------
    u_rx : entity work.eth_rx
        generic map (CAP_BYTES => CAP)
        port map (
            rx_clk => eth_rx_clk,
            rxd    => eth_rxd,
            rx_dv  => eth_rx_dv,
            rx_er  => eth_rxerr,
            data   => rx_data,
            ok_t   => rx_t
        );

    process (clk)
    begin
        if rising_edge(clk) then
            rx_s     <= rx_s(0) & rx_t;
            rx_q     <= rx_s(1);
            client_q <= client;
            parse    <= '0';
            if rx_s(1) /= rx_q then               -- neuer Rahmen: sofort kopieren
                rxb   <= rx_data;
                parse <= '1';
            end if;

            if frame_tick = '1' and lost < TIMEOUT_FRAMES then
                lost <= lost + 1;
            end if;
            if lost = TIMEOUT_FRAMES then         -- Partner weg: keine Taste gedrueckt
                btn_rx <= "00";
            end if;

            if parse = '1' and enable = '1' and hdr_ok(rxb) then
                if client = '1' and rxb(19) = TYPE_STATE then
                    st_rx.pl_y    <= clip(rxb(21), 63);
                    st_rx.pr_y    <= clip(rxb(22), 63);
                    st_rx.bx      <= clip(rxb(23), 95);
                    st_rx.by      <= clip(rxb(24), 63);
                    st_rx.score_l <= clip(rxb(25), 9);
                    st_rx.score_r <= clip(rxb(26), 9);
                    lost <= 0;
                elsif client = '0' and rxb(19) = TYPE_INPUT then
                    btn_rx <= rxb(27)(1 downto 0);
                    lost   <= 0;
                end if;
            end if;

            if rst = '1' or enable = '0' or client /= client_q then   -- auch bei Rollenwechsel
                lost   <= TIMEOUT_FRAMES;
                st_rx  <= PONG_INIT;
                btn_rx <= "00";
            end if;
        end if;
    end process;

    peer_ok <= '1' when lost < TIMEOUT_FRAMES else '0';

end architecture rtl;
