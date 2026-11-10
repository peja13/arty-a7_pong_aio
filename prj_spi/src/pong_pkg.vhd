----------------------------------------------------------------------------------
-- Modul        : pong_pkg
-- Beschreibung : Sichtbarer Spielzustand von Pong. Genau diese Werte schickt der
--                Server pro Bild ueber das LAN an den Client; der Client zeichnet
--                damit dasselbe Spielfeld.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package pong_pkg is

    type pong_state_t is record
        pl_y    : natural range 0 to 63;          -- linker Schlaeger, obere Kante
        pr_y    : natural range 0 to 63;          -- rechter Schlaeger, obere Kante
        bx      : natural range 0 to 95;          -- Ball, linke obere Ecke
        by      : natural range 0 to 63;
        score_l : natural range 0 to 9;
        score_r : natural range 0 to 9;
    end record;

    -- Anfangszustand: Schlaeger mittig, Ball in der Mitte, 0:0
    constant PONG_INIT : pong_state_t := (
        pl_y => 25, pr_y => 25, bx => 46, by => 30, score_l => 0, score_r => 0);

end package pong_pkg;
