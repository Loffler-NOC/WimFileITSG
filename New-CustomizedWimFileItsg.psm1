<#
.SYNOPSIS
Modifies an install.wim file for use within ITSG operating system deployments (MDT task sequence)

.DESCRIPTION
Function requires a folder path containing an install.wim file to be modified. Additional paramaters include:
* (Optional) Remove specified AppX packages within the install.wim file
* (Optional) Modify specified registry settings within the install.wim file

If both optional parameters were skipped, function will exit

.PARAMETER FolderPath
The folder path containing the existing install.wim file

.PARAMETER AppxPackagesToRemove
(Optional) The name of the file containing AppX packages to remove

.PARAMETER RegistryModifications
(Optional) The name of the file containing registry modifications

Registry modifications within the custom registry settings file should be keyed in with the following replacements:
* HKLM\Software = HKEY_LOCAL_MACHINE\RegHKLMSoftware
* HKLM\System =   HKEY_LOCAL_MACHINE\RegHKLMSystem
* HKCU =          HKEY_USERS\RegNtuserdat

.EXAMPLE
New-CustomizedWimFileItsg -FolderPath 'C:\WorkingDir' -AppxPackagesToRemove 'PLACEHOLDER.txt' -RegistryModifications 'PLACEHOLDER.reg'

.NOTES
Version/Date/Notes: v1.0 (2024-03-21).
#>

function New-CustomizedWimFileItsg {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FolderPath,

        [string]$AppxPackagesToRemove,
        [string]$RegistryModifications
    )

    # Check if both optional parameters were skipped. If so, exit (function currently only handles this optional functionality)
    if (($AppxPackagesToRemove -eq $null) -and ($RegistryModifications -eq $null)) {
        Write-Error "You specified a folder, but no modifications to make within an install.wim file. Press any key to exit..."
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit
    }

    # Check if the specified folder path exists
    if (!(Test-Path -Path $FolderPath)) {
        Write-Error "The specified folder $FolderPath does not exist. Press any key to exit..."
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit
    }

    # Checks if the specified folder path contains an install.wim file
    $WimFilePath = Join-Path -Path $FolderPath -ChildPath 'install.wim'
    if (!(Test-Path -Path $WimFilePath)) {
        Write-Error "No install.wim file found within the specified folder. Press any key to exit..."
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit
    }

    # Create offline servicing folder if it doesn't exist
    $FolderPathOfflineServicing = Join-Path -Path $FolderPath -ChildPath 'WIM-OFFLINESERVICING'
    if (!(Test-Path -Path $FolderPathOfflineServicing)) {
        New-Item -Path $FolderPathOfflineServicing -ItemType Directory | Out-Null
        Write-Host "Offline servicing folder created: $FolderPathOfflineServicing" -ForegroundColor Green
    }

    # Clean up any stale mounted WIM file leftovers
    & dism.exe /Cleanup-Wim
    Write-Host "Any stale mounted WIM file leftovers cleaned up" -ForegroundColor Green

    # Mount the WIM file to the offline servicing folder
    & dism.exe /Mount-Image /ImageFile:"$WimFilePath" /Index:1 /MountDir:"$FolderPathOfflineServicing"
    Write-Host "WIM file mounted to $FolderPathOfflineServicing" -ForegroundColor Green

    # (Optional) AppX packages removal
    if ($AppxPackagesToRemove) {
        $AppxApps = Get-Content -Path "$FolderPath\$AppxPackagesToRemove"

        foreach ($AppAppx in $AppxApps) {
            Write-Host "Removing AppX package: $AppAppx" -ForegroundColor Green
            (Get-AppxProvisionedPackage -Path "$FolderPathOfflineServicing" | Where-Object { $_.DisplayName -like "$AppAppx" }) | Remove-AppxProvisionedPackage
        }
    }

    # (Optional) Apply registry modifications
    if ($RegistryModifications) {
        reg load HKLM\RegHKLMSoftware "$FolderPathOfflineServicing\Windows\System32\config\SOFTWARE"
        reg load HKLM\RegHKLMSystem "$FolderPathOfflineServicing\Windows\System32\config\SYSTEM"
        reg load HKU\RegNtuserdat "$FolderPathOfflineServicing\Users\Default\ntuser.dat"
        Write-Host "Registry hives mounted" -ForegroundColor Yellow

        regedit /s "$FolderPath\$RegistryModifications"
        Write-Host "Registry modifications applied" -ForegroundColor Green

        [System.GC]::Collect()
        Write-Host "Garbage collection ran" -ForegroundColor Yellow

        reg unload HKLM\RegHKLMSoftware
        reg unload HKLM\RegHKLMSystem
        reg unload HKU\RegNtuserdat
        Write-Host "Registry hives unmounted" -ForegroundColor Yellow
    }

    # Determine whether or not WIM file modifications should be applied
    $ChoiceFinalizeWim = $null
    while ($ChoiceFinalizeWim -ne '1' -and $ChoiceFinalizeWim -ne '2') {
        $ChoiceFinalizeWim = Read-Host -Prompt "Would you like to Commit or Discard these WIM changes? If you saw a bunch of red text, it may be wise to Discard...`n`n1) Commit (Save changes to WIM!)`n2) Discard (Abandon ship!)`n`nEnter 1 or 2"
    }

    if ($ChoiceFinalizeWim -eq '1') { $ChoiceFinalizeWim = "Commit" }
    if ($ChoiceFinalizeWim -eq '2') { $ChoiceFinalizeWim = "Discard" }

    # Unmount the WIM file and either Commit or Discard
    & dism.exe /Unmount-Image /MountDir:"$FolderPathOfflineServicing" /$ChoiceFinalizeWim
    Write-Host "WIM file unmounted. Changes were set to $ChoiceFinalizeWim" -ForegroundColor Green
    Write-Host "WIM file located in $WimFilePath. You may clean up any additional source files" -ForegroundColor Green

    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit
}
