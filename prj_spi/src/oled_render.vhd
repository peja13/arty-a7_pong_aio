----------------------------------------------------------------------------------
-- Modul        : oled_render
-- Beschreibung : Pixelgenerator fuer Pong (weiss auf schwarz).
--                client = '0' (Server): das Spiel wird hier gerechnet.
--                    btn0/btn1 = linker Schlaeger. Den rechten Schlaeger steuert
--                    der Client ueber das LAN; ist keiner verbunden, wie bisher
--                    btn2/btn3 am selben Board (zu zweit an einem Board).
--                client = '1' (Client): zeigt den Spielzustand, den der Server
--                    schickt.
--                Die Rolle wird nur am Bildende uebernommen (kein Tearing).
--                pix ist 3 Takte nach (x, y) gueltig; x/y muessen so lange stabil sein.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.pong_pkg.all;

entity oled_render is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        x           : in  unsigned(6 downto 0);
        y           : in  unsigned(5 downto 0);
        frame_tick  : in  std_logic;
        client      : in  std_logic;                     -- Schalter: 0 = Server, 1 = Client
        btn         : in  std_logic_vector(3 downto 0);
        pix         : out std_logic_vector(15 downto 0);
        -- LAN-Pong
        net_ok      : in  std_logic;                     -- Partner verbunden
        net_btn     : in  std_logic_vector(1 downto 0);  -- Server: Tasten des Clients (1 runter, 0 hoch)
        net_state   : in  pong_state_t;                  -- Client: Spielzustand vom Server
        pong_state  : out pong_state_t;                  -- angezeigter Spielzustand
        pong_client : out std_logic                      -- uebernommene Rolle: 1 = Client
    );
end entity oled_render;

architecture rtl of oled_render is

    signal remote  : std_logic := '0';
    signal r_up    : std_logic;
    signal r_dn    : std_logic;
    signal pong_on : std_logic;

begin

    ------------------------------------------------------------------
    -- Rolle nur am Bildende uebernehmen
    ------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                remote <= '0';
            elsif frame_tick = '1' then
                remote <= client;
            end if;
        end if;
    end process;

    pong_client <= remote;

    -- rechter Schlaeger beim Server: Client ueber LAN, sonst die Taster am Board
    r_up <= net_btn(0) when net_ok = '1' else btn(2);
    r_dn <= net_btn(1) when net_ok = '1' else btn(3);

    u_pong : entity work.pong_game
        port map (
            clk        => clk,
            rst        => rst,
            remote     => remote,
            remote_ok  => net_ok,
            st_in      => net_state,
            st_out     => pong_state,
            frame_tick => frame_tick,
            l_up       => btn(0),
            l_dn       => btn(1),
            r_up       => r_up,
            r_dn       => r_dn,
            x          => x,
            y          => y,
            pix_on     => pong_on
        );

    ------------------------------------------------------------------
    -- Ausgabe: weiss oder schwarz (1 Registerstufe nach pong_game)
    ------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            if pong_on = '1' then
                pix <= x"FFFF";
            else
                pix <= x"0000";
            end if;
        end if;
    end process;

end architecture rtl;
