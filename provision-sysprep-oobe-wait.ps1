Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$', 'ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$', 'ERROR EXCEPTION: $1' | Write-Host
    Exit 1
}

function Write-ProvisionProgress($message) {
    "$(Get-Date -UFormat "%Y-%m-%dT%T%Z") $message"
}

# wait for a previous provision-sysprep-oobe to finish.
$sysprepOobePath = 'C:\Windows\System32\Sysprep\provision-sysprep-oobe.txt'
if (Test-Path $sysprepOobePath) {
    Write-ProvisionProgress 'Waiting for previous provision-sysprep-oobe to finish...'
    while (Test-Path $sysprepOobePath) {
        Start-Sleep -Seconds 5
    }
    Start-Sleep -Seconds 5
}
