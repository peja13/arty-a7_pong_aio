----------------------------------------------------------------------------------
-- Modul        : eth_rx
-- Beschreibung : Ethernet-Empfaenger fuer die MII-Schnittstelle des PHY (TI DP83848J).
--                Laeuft im Takt RX_CLK des PHY. Sucht nach Praeambel (Nibbles 5) das
--                SFD-Nibble D, setzt danach je zwei Nibbles zu einem Byte zusammen
--                (niederwertiges zuerst) und rechnet die CRC-32 mit.
--                Angenommen wird ein Rahmen nur, wenn er genau FRAME_LEN + 4 Byte
--                lang ist, kein RX_ER kam und die CRC stimmt. Dann kippt ok_t.
--
-- Uebergabe an den 100-MHz-Takt: data (die ersten CAP_BYTES Bytes) ist ab dem
-- Kippen von ok_t mindestens bis zum Beginn des naechsten Rahmens stabil
-- (> 1 us). Der Empfaenger synchronisiert ok_t und kopiert data sofort.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use work.eth_pkg.all;

entity eth_rx is
    generic (
        FRAME_LEN : positive := ETH_FRAME_LEN;    -- erwartete Laenge ohne FCS
        CAP_BYTES : positive := 28                -- so viele Bytes werden ausgegeben
    );
    port (
        rx_clk : in  std_logic;
        rxd    : in  std_logic_vector(3 downto 0);
        rx_dv  : in  std_logic;
        rx_er  : in  std_logic;
        data   : out byte_arr_t(0 to CAP_BYTES - 1);
        ok_t   : out std_logic                    -- Toggle: fehlerfreier Rahmen
    );
end entity eth_rx;

architecture rtl of eth_rx is

    type state_t is (R_IDLE, R_PRE, R_DATA, R_DROP);
    signal state : state_t := R_IDLE;

    -- Eingangsregister (direkt an den Pins, im IOB)
    signal rxd_q : std_logic_vector(3 downto 0) := "0000";
    signal dv_q  : std_logic := '0';
    signal er_q  : std_logic := '0';

    signal lo    : std_logic_vector(3 downto 0) := "0000";
    signal hi    : std_logic := '0';                        -- 1 = oberes Nibble ist dran
    signal idx   : natural range 0 to FRAME_LEN + 4 := 0;   -- empfangene Bytes
    signal crc   : std_logic_vector(31 downto 0) := (others => '1');
    signal bad   : std_logic := '0';
    signal buf   : byte_arr_t(0 to CAP_BYTES - 1) := (others => (others => '0'));
    signal tog   : std_logic := '0';

begin

    data <= buf;
    ok_t <= tog;

    process (rx_clk)
    begin
        if rising_edge(rx_clk) then
            rxd_q <= rxd;
            dv_q  <= rx_dv;
            er_q  <= rx_er;

            case state is

                when R_IDLE =>
                    if dv_q = '1' then
                        if rxd_q = x"5" then
                            state <= R_PRE;
                        else
                            state <= R_DROP;
                        end if;
                    end if;

                when R_PRE =>                     -- Praeambel, der PHY darf Teile weglassen
                    if dv_q = '0' then
                        state <= R_IDLE;
                    elsif rxd_q = x"D" then       -- SFD: ab jetzt Daten
                        hi    <= '0';
                        idx   <= 0;
                        crc   <= (others => '1');
                        bad   <= '0';
                        state <= R_DATA;
                    elsif rxd_q /= x"5" then
                        state <= R_DROP;
                    end if;

                when R_DATA =>
                    if dv_q = '1' then
                        crc <= crc32_nibble(crc, rxd_q);
                        if er_q = '1' then
                            bad <= '1';
                        end if;
                        if hi = '0' then
                            lo <= rxd_q;
                            hi <= '1';
                        else
                            hi <= '0';
                            if idx < CAP_BYTES then
                                buf(idx) <= rxd_q & lo;
                            end if;
                            if idx < FRAME_LEN + 4 then
                                idx <= idx + 1;
                            else
                                bad <= '1';       -- zu lang
                            end if;
                        end if;
                    else                          -- Rahmenende: alles pruefen
                        if bad = '0' and hi = '0' and idx = FRAME_LEN + 4 and crc = CRC_RESIDUE then
                            tog <= not tog;
                        end if;
                        state <= R_IDLE;
                    end if;

                when R_DROP =>                    -- fremder/kaputter Rahmen: Ende abwarten
                    if dv_q = '0' then
                        state <= R_IDLE;
                    end if;

            end case;
        end if;
    end process;

end architecture rtl;
