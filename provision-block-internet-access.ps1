Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1' | Write-Host
    Exit 1
}

New-NetFirewallRule `
    -Name PROVISION-BLOCK-INTERNET-Out `
    -DisplayName "Block Internet Access" `
    -Description "Blocks Internet Access" `
    -Direction Outbound `
    -RemoteAddress Internet `
    -Action Block `
    -Enabled True
