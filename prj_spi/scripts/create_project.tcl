# Vivado-Projekt fuer Pong (Pmod OLEDrgb + LAN) erzeugen
#
# Board waehlen (Standard: Arty A7-100T):
#   vivado -mode gui   -source scripts/create_project.tcl                 Arty A7-100T
#   vivado -mode gui   -source scripts/create_project.tcl -tclargs 35     Arty A7-35T
#   (-mode batch statt -mode gui: ohne Oberflaeche)
# In der Tcl-Konsole von Vivado:
#   source scripts/create_project.tcl                                     Arty A7-100T
#   set board 35; source scripts/create_project.tcl                       Arty A7-35T
# Danach oeffnen: File > Open Project > vivado/spi_oled.xpr

set script_dir [file normalize [file dirname [info script]]]
set root       [file normalize "$script_dir/.."]

if {![info exists board]} {
    set board 100
    if {[info exists argv] && [llength $argv] > 0} {
        set board [lindex $argv 0]
    }
}

switch -- $board {
    100     { set part "xc7a100tcsg324-1"  }
    35      { set part "xc7a35ticsg324-1L" }
    default { error "Unbekanntes Board '$board' - erlaubt sind 100 (Arty A7-100T) und 35 (Arty A7-35T)" }
}

set proj_name "spi_oled"

create_project $proj_name "$root/vivado" -part $part -force

add_files -fileset sources_1 [glob "$root/src/*.vhd"]
add_files -fileset sim_1     [glob "$root/sim/*.vhd"]
add_files -fileset constrs_1 "$root/constraints/arty_a7_oled.xdc"

set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sources_1] *.vhd]
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sim_1] *.vhd]

set_property top spi_top    [get_filesets sources_1]
set_property top tb_spi_top [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Projekt '$proj_name' fuer Arty A7-${board}T ($part) angelegt unter $root/vivado"
