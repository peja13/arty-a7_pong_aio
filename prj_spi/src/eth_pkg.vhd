----------------------------------------------------------------------------------
-- Modul        : eth_pkg
-- Beschreibung : Gemeinsame Typen und Funktionen fuer die Ethernet-Anbindung (MII):
--                Byte-Feld und CRC-32 der Ethernet-Pruefsumme (FCS).
--
-- CRC-32 nach IEEE 802.3: Startwert FFFFFFFF, Polynom 04C11DB7. Weil Ethernet jedes
-- Byte mit dem niederwertigsten Bit zuerst sendet, rechnet man "gespiegelt" mit
-- EDB88320 und schiebt nach rechts. Am MII kommen 4 Bit (ein Nibble) pro Takt an,
-- deshalb verarbeitet crc32_nibble genau 4 Bit, d(0) zuerst.
-- Gesendet wird FCS = not crc, Bit 0 zuerst. Rechnet der Empfaenger die CRC ueber
-- Daten UND FCS, bleibt bei fehlerfreiem Rahmen immer CRC_RESIDUE uebrig.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package eth_pkg is

    type byte_arr_t is array (natural range <>) of std_logic_vector(7 downto 0);

    constant ETH_FRAME_LEN : positive := 60;      -- Bytes ohne FCS (= Mindestrahmen 64 Byte)
    constant CRC_RESIDUE   : std_logic_vector(31 downto 0) := x"DEBB20E3";

    function crc32_nibble (crc : std_logic_vector(31 downto 0);
                           d   : std_logic_vector(3 downto 0)) return std_logic_vector;

end package eth_pkg;

package body eth_pkg is

    function crc32_nibble (crc : std_logic_vector(31 downto 0);
                           d   : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable c : std_logic_vector(31 downto 0) := crc;
    begin
        for i in 0 to 3 loop
            if (c(0) xor d(i)) = '1' then
                c := ('0' & c(31 downto 1)) xor x"EDB88320";
            else
                c := '0' & c(31 downto 1);
            end if;
        end loop;
        return c;
    end function;

end package body eth_pkg;
