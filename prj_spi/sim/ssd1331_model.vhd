----------------------------------------------------------------------------------
-- Testbench-Modell : ssd1331_model
-- Beschreibung     : Vereinfachtes Pmod OLEDrgb (SSD1331, SPI-Mode 3) fuer
--                    tb_lan_pong. Pixeldaten landen in fb (96x64 x 2 Byte),
--                    frame_cnt zaehlt vollstaendig empfangene Bilder.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package tb_oled_pkg is
    type fb_t is array (0 to 12287) of std_logic_vector(7 downto 0);

    function fb_px (fb : fb_t; x, y : natural) return std_logic_vector;
end package tb_oled_pkg;

package body tb_oled_pkg is
    function fb_px (fb : fb_t; x, y : natural) return std_logic_vector is
        constant i : natural := 2 * (y * 96 + x);
    begin
        return fb(i) & fb(i + 1);
    end function;
end package body tb_oled_pkg;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use work.tb_oled_pkg.all;

entity ssd1331_model is
    port (
        cs        : in  std_logic;
        sck       : in  std_logic;
        mosi      : in  std_logic;
        dc        : in  std_logic;
        fb        : out fb_t;
        frame_cnt : out natural
    );
end entity ssd1331_model;

architecture sim of ssd1331_model is
begin

    process (sck, cs)
        variable sh   : std_logic_vector(7 downto 0) := (others => '0');
        variable bits : natural := 0;
        variable dcnt : natural := 0;
        variable fcnt : natural := 0;
        variable buf  : fb_t := (others => (others => '0'));
    begin
        if cs = '1' then
            bits := 0;
        elsif rising_edge(sck) then
            sh   := sh(6 downto 0) & mosi;
            bits := bits + 1;
            if bits = 8 then
                bits := 0;
                if dc = '1' then
                    buf(dcnt) := sh;
                    dcnt := dcnt + 1;
                    if dcnt = 12288 then          -- Bild komplett: auf einmal ausgeben
                        dcnt := 0;
                        fcnt := fcnt + 1;
                        fb        <= buf;
                        frame_cnt <= fcnt;
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture sim;
