Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1' | Write-Host
    Exit 1
}

# install chocolatey.
# see https://community.chocolatey.org/packages/chocolatey
# renovate: datasource=nuget:chocolatey depName=chocolatey
$env:chocolateyVersion = '2.4.1'
Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')
if ($LASTEXITCODE) {
    throw "failed to install with exit code $LASTEXITCODE"
}
