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

# see https://gist.github.com/IISResetMe/36ef331484a770e23a81
function Get-MachineSID {
    param(
        [switch]$DomainSID
    )

    # Retrieve the Win32_ComputerSystem class and determine if machine is a Domain Controller
    $WmiComputerSystem = Get-CimInstance Win32_ComputerSystem
    $IsDomainController = $WmiComputerSystem.DomainRole -ge 4

    if ($IsDomainController -or $DomainSID) {
        # We grab the Domain SID from the DomainDNS object (root object in the default NC)
        $Domain    = $WmiComputerSystem.Domain
        $SIDBytes = ([ADSI]"LDAP://$Domain").objectSid | %{$_}
        New-Object System.Security.Principal.SecurityIdentifier -ArgumentList ([Byte[]]$SIDBytes),0
    } else {
        # Going for the local SID by finding a local account and removing its Relative ID (RID)
        $LocalAccountSID = Get-CimInstance -Query "SELECT SID FROM Win32_UserAccount WHERE LocalAccount = 'True'" | Select-Object -First 1 -ExpandProperty SID
        $MachineSID      = ($p = $LocalAccountSID -split "-")[0..($p.Length-2)]-join"-"
        New-Object System.Security.Principal.SecurityIdentifier -ArgumentList $MachineSID
    }
}

$windowsBuild = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber

# wait for a previous provision-sysprep-oobe to finish.
$sysprepOobePath = 'C:\Windows\System32\Sysprep\provision-sysprep-oobe.txt'
if (Test-Path $sysprepOobePath) {
    Write-ProvisionProgress 'Waiting for previous provision-sysprep-oobe to finish...'
    while (Test-Path $sysprepOobePath) {
        Start-Sleep -Seconds 5
    }
    Start-Sleep -Seconds 5
}

# show the current machine sid.
Write-ProvisionProgress 'Getting the Windows Machine SID...'
$machineSid = Get-MachineSID
Write-Output "$machineSid"

# signal the provision-sysprep-oobe start.
# NB this file is used by provision-sysprep-oobe-wait.ps1 to wait for
#    a previous run too.
Write-ProvisionProgress 'Signaling the provision-sysprep-oobe start...'
Set-Content `
    -Encoding UTF8 `
    -NoNewLine `
    -Path $sysprepOobePath `
    -Value $machineSid

# remove the sshd host keys.
Write-ProvisionProgress 'Removing the sshd host keys...'
Remove-Item -Force C:\ProgramData\ssh\ssh_host_*

# reset cloudbase-init.
Write-ProvisionProgress 'Resetting cloudbase-init...'
Remove-Item 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\*.log'
$cloudbaseInitRegistryKeyPath = 'HKLM:\SOFTWARE\Cloudbase Solutions'
if (Test-Path $cloudbaseInitRegistryKeyPath) {
    Remove-Item -Recurse -Force $cloudbaseInitRegistryKeyPath
}

# remove appx packages that prevent sysprep from working.
# NB without this, sysprep will fail with:
#       2024-12-14 14:08:40, Error                 SYSPRP Package Microsoft.MicrosoftEdge.Stable_131.0.2903.99_neutral__8wekyb3d8bbwe was installed for a user, but not provisioned for all users. This package will not function properly in the sysprep image.
# NB you can list all the appx and which users have installed them:
#       Get-AppxPackage -AllUsers | Format-List PackageFullName,PackageUserInformation
# NB this only seems to be required in Windows 11/2025+ (aka 24H2 aka build 26100).
#    NB on earlier versions pwsh fails to load the Appx module as:
#           Operation is not supported on this platform. (0x80131539)
# see https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/sysprep-fails-remove-or-update-store-apps#cause
if ($windowsBuild -ge 26100) {
    Write-ProvisionProgress "Removing appx packages that prevent sysprep from working..."
    Get-AppxPackage -AllUsers `
        | Where-Object { $_.PackageUserInformation.InstallState -eq 'Installed' } `
        | Where-Object {
            $_.PackageFullName -like 'Microsoft.MicrosoftEdge.*' -or `
            $_.PackageFullName -like 'NotepadPlusPlus*'
        } `
        | ForEach-Object {
            Write-ProvisionProgress "Removing the $($_.PackageFullName) appx package..."
            Remove-AppxPackage -AllUsers -Package $_.PackageFullName
        }
}

# delete the previous sysprep oobe logs.
# NB unfortunately, we cannot delete these files, as they are being used by
#    other processes. so reading these logs will be a bit harder, since you
#    have to check to which boot they belong to.
# # NB when oobe is still running, we cannot delete the logs, as this fails with:
# #       The process cannot access the file 'C:\Windows\Panther\UnattendGC\setupact.log' because it is being used by another process.
# # NB while testing, these were the processes that had open files:
# #       taskhostw.exe
# #       CloudExperienceHostBroker.exe
# #       RuntimeBroker.exe
# #       UserOOBEBroker.exe
# # see https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-process-overview?view=windows-11#sysprep-log-files
# Write-ProvisionProgress 'Removing the oobe logs...'
# while ($true) {
#     try {
#         Remove-Item -Force C:\Windows\Panther\UnattendGC\setup*.log
#         Remove-Item -Force C:\Windows\Panther\UnattendGC\diag*.xml
#         break
#     } catch {
#         if ("$_" -like '*is being used by another process*') {
#             Write-Output "Failed to delete the previous OOBE log files. The files are currently open by the following processes:"
#             handle.exe C:\Windows\Panther\UnattendGC
#             Write-Output "Retrying the delete in a moment..."
#             Start-Sleep -Seconds 5
#             continue
#         }
#         throw $_
#     }
# }

# remove the previous sysprep generalize logs.
# see https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-process-overview?view=windows-11#sysprep-log-files
Write-ProvisionProgress 'Removing the previous sysprep logs...'
Remove-Item -Force C:\Windows\System32\Sysprep\Panther\setup*.log
Remove-Item -Force C:\Windows\System32\Sysprep\Panther\diag*.xml

# remove the previous sysprep specialize logs.
# NB unfortunately, we cannot delete these files, as they are being used by
#    other processes. so reading these logs will be a bit harder, since you
#    have to check to which boot they belong to.
# Remove-Item -Force C:\Windows\Panther\setup*.log
# Remove-Item -Force C:\Windows\Panther\diag*.xml

# sysprep the machine.
# see https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-process-overview?view=windows-11
# see https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-states?view=windows-11
# see https://github.com/rgl/vagrant-windows-sysprep/blob/master/lib/vagrant-windows-sysprep/unattend.xml
Write-ProvisionProgress 'Syspreping the machine...'
$unattendPath = 'C:\Windows\System32\Sysprep\provision-sysprep-oobe.xml'
Set-Content -Encoding UTF8 -Path $unattendPath -NoNewLine -Value @"
<?xml version="1.0" encoding="utf-8"?>
<!--
    sysprep copies this file to C:\Windows\Panther\unattend.xml
    the logs are stored in the following directories:
        generalize phase: C:\Windows\System32\Sysprep\Panther
        specialize phase: C:\Windows\Panther
        oobe phase:       C:\Windows\Panther\UnattendGC
-->
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="generalize">
        <component name="Microsoft-Windows-Security-SPP" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <SkipRearm>1</SkipRearm>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <InputLocale>en-US</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Home</NetworkLocation>
                <ProtectYourPC>1</ProtectYourPC>
            </OOBE>
            <AutoLogon>
                <Enabled>true</Enabled>
                <Username>vagrant</Username>
                <Password>
                    <Value>vagrant</Value>
                    <PlainText>true</PlainText>
                </Password>
            </AutoLogon>
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <CommandLine>PowerShell -WindowStyle Maximized -File C:\Windows\System32\Sysprep\provision-sysprep-oobe.ps1</CommandLine>
                </SynchronousCommand>
            </FirstLogonCommands>
        </component>
    </settings>
</unattend>
"@
$sysprepSucceededTagPath = 'C:\Windows\System32\Sysprep\Sysprep_succeeded.tag'
# NB although sysprep is supposed to delete this, to be safe (e.g. earlier
#    sysprep errors), delete it.
if (Test-Path $sysprepSucceededTagPath) {
    Remove-Item -Force $sysprepSucceededTagPath
}
C:\Windows\System32\Sysprep\Sysprep.exe `
    /mode:vm `
    /generalize `
    /oobe `
    /quiet `
    /quit `
    "/unattend:$unattendPath" `
    | Out-String -Stream

Write-ProvisionProgress 'Checking for sysprep errors...'
if (!(Test-Path $sysprepSucceededTagPath)) {
    Get-Content C:\Windows\System32\Sysprep\Panther\setuperr.log
    throw "sysprep failed because no $sysprepSucceededTagPath file was found. for more details see the C:\Windows\System32\Sysprep\Panther\setupact.log file (and related files)."
}

Write-ProvisionProgress 'Ensuring the windows image state is IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE...'
$imageState = (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State).ImageState
if ($imageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {
    throw "the windows image state $imageState is not the expected IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE."
}
