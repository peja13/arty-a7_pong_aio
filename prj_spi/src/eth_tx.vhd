----------------------------------------------------------------------------------
-- Modul        : eth_tx
-- Beschreibung : Ethernet-Sender fuer die MII-Schnittstelle des PHY (TI DP83848J).
--                Laeuft im Takt TX_CLK des PHY (25 MHz bei 100 Mbit/s, 2,5 MHz bei
--                10 Mbit/s) und gibt pro Takt ein Nibble aus, niederwertiges zuerst.
--                Ablauf: 15 x 5 + D (Praeambel + SFD), FRAME_LEN Datenbytes, 4 Byte
--                FCS (CRC-32), danach Sendepause (Inter Frame Gap).
--
-- Uebergabe aus dem 100-MHz-Takt (Toggle-Handshake):
--   Auftraggeber legt frame an und kippt req_t. Sobald der Rahmen samt Pause
--   draussen ist, setzt eth_tx ack_t = req_t. Solange ack_t /= req_t ist, darf
--   frame nicht veraendert werden.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use work.eth_pkg.all;

entity eth_tx is
    generic (
        FRAME_LEN   : positive := ETH_FRAME_LEN;  -- Bytes ohne FCS
        IFG_NIBBLES : positive := 26              -- Pause, mind. 24 Nibbles = 12 Byte
    );
    port (
        tx_clk : in  std_logic;
        frame  : in  byte_arr_t(0 to FRAME_LEN - 1);
        req_t  : in  std_logic;                   -- Sendeauftrag (Toggle, fremder Takt)
        ack_t  : out std_logic;                   -- Quittung (Toggle)
        txd    : out std_logic_vector(3 downto 0);
        tx_en  : out std_logic
    );
end entity eth_tx;

architecture rtl of eth_tx is

    type state_t is (T_IDLE, T_PRE, T_DATA, T_FCS, T_IFG);
    signal state : state_t := T_IDLE;

    signal req_s : std_logic_vector(1 downto 0) := "00";   -- Synchronisierer fuer req_t
    signal req_q : std_logic := '0';                        -- bearbeiteter Auftrag
    signal ack   : std_logic := '0';

    signal cnt   : natural range 0 to 31 := 0;              -- Praeambel / FCS / Pause
    signal idx   : natural range 0 to FRAME_LEN - 1 := 0;   -- Datenbyte
    signal hi    : std_logic := '0';                        -- 1 = oberes Nibble ist dran
    signal crc   : std_logic_vector(31 downto 0) := (others => '1');

    signal txd_r : std_logic_vector(3 downto 0) := "0000";
    signal en_r  : std_logic := '0';

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of req_s : signal is "TRUE";

begin

    ack_t <= ack;
    txd   <= txd_r;
    tx_en <= en_r;

    process (tx_clk)
        variable n : std_logic_vector(3 downto 0);
    begin
        if rising_edge(tx_clk) then
            req_s <= req_s(0) & req_t;

            case state is

                when T_IDLE =>
                    en_r  <= '0';
                    txd_r <= "0000";
                    if req_s(1) /= ack then
                        req_q <= req_s(1);
                        cnt   <= 0;
                        state <= T_PRE;
                    end if;

                when T_PRE =>                     -- 7 Byte 55, dann SFD D5
                    en_r <= '1';
                    if cnt = 15 then
                        txd_r <= x"D";
                        cnt   <= 0;
                        idx   <= 0;
                        hi    <= '0';
                        crc   <= (others => '1');
                        state <= T_DATA;
                    else
                        txd_r <= x"5";
                        cnt   <= cnt + 1;
                    end if;

                when T_DATA =>
                    if hi = '0' then
                        n := frame(idx)(3 downto 0);
                    else
                        n := frame(idx)(7 downto 4);
                    end if;
                    txd_r <= n;
                    crc   <= crc32_nibble(crc, n);
                    hi    <= not hi;
                    if hi = '1' then
                        if idx = FRAME_LEN - 1 then
                            cnt   <= 0;
                            state <= T_FCS;
                        else
                            idx <= idx + 1;
                        end if;
                    end if;

                when T_FCS =>                     -- not crc, Bit 0 zuerst
                    txd_r <= not crc(3 downto 0);
                    crc   <= "1111" & crc(31 downto 4);
                    if cnt = 7 then
                        cnt   <= 0;
                        state <= T_IFG;
                    else
                        cnt <= cnt + 1;
                    end if;

                when T_IFG =>
                    en_r  <= '0';
                    txd_r <= "0000";
                    if cnt = IFG_NIBBLES - 1 then
                        ack   <= req_q;
                        state <= T_IDLE;
                    else
                        cnt <= cnt + 1;
                    end if;

            end case;
        end if;
    end process;

end architecture rtl;
