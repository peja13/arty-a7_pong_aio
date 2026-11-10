param(
    [string]$Ghdl = 'ghdl',
    [string[]]$Tb = @('tb_eth', 'tb_spi_top', 'tb_lan_pong')
)
# Testbenches mit GHDL:  tb_eth (Ethernet, Sekunden), tb_spi_top (ein Board, Minuten),
# tb_lan_pong (zwei Boards ueber LAN, Minuten). Nur eine:  scripts/run_sim.ps1 -Tb tb_eth
$ErrorActionPreference = 'Stop'
$root  = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root 'sim/build'
New-Item -ItemType Directory -Force $build | Out-Null
Push-Location $build
try {
    $src = 'eth_pkg','pong_pkg','input_filter','spi_tx','oled_ctrl','eth_tx','eth_rx',
           'lan_link','pong_game','oled_render','spi_top' | ForEach-Object { "$root/src/$_.vhd" }
    $sim = 'ssd1331_model','tb_eth','tb_spi_top','tb_lan_pong' | ForEach-Object { "$root/sim/$_.vhd" }
    & $Ghdl -a --std=08 @src @sim
    if ($LASTEXITCODE -ne 0) { throw 'VHDL-Analyse fehlgeschlagen' }
    foreach ($t in $Tb) {
        Write-Host "=== $t ==="
        & $Ghdl --elab-run --std=08 $t --assert-level=error
        if ($LASTEXITCODE -ne 0) { throw "Simulation $t fehlgeschlagen" }
    }
} finally {
    Pop-Location
}
