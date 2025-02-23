Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
trap {
    Write-Host "ERROR: $_"
    ($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1' | Write-Host
    ($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1' | Write-Host
    Exit 1
}

# reload the environment variables.
# NB this is required because the chocolatey installation added itself to the
#    PATH, but the packer provisioner does not reload it.
$env:PATH = "$([Environment]::GetEnvironmentVariable("PATH", "Machine"));$([Environment]::GetEnvironmentVariable("PATH", "User"))"

# see https://community.chocolatey.org/packages/handle
# NB we have to ignore the checksums because the upstream does not version its artifact.
choco install -y handle --ignore-checksums
