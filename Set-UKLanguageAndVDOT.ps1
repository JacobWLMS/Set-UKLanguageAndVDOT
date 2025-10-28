# Set-UKLanguageAndVDOT.ps1
# Installs English (United Kingdom) language pack, sets locale, and runs VDOT
# For use in Azure Image Builder (portal-friendly single script)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'UTF8'

Write-Output '=== Starting UK Language + Locale + VDOT configuration ==='

# ----------------------------------------------------------------------
# Step 1: Install UK Language Pack
# ----------------------------------------------------------------------
$tempDir = 'C:\AIBTemp'
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$installScript = Join-Path $tempDir 'InstallLanguagePacks.ps1'
$installUrl = 'https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/InstallLanguagePacks.ps1'

Write-Output 'Downloading official InstallLanguagePacks.ps1...'
Invoke-WebRequest -Uri $installUrl -OutFile $installScript

Write-Output 'Installing English (United Kingdom) language pack...'
& $installScript -LanguageList 'English (United Kingdom)'

Write-Output 'Language pack installation completed.'

# ----------------------------------------------------------------------
# Step 2: Set System Locale and Language
# ----------------------------------------------------------------------
$LanguageTag = 'en-GB'

Write-Output "Setting system and user language to $LanguageTag..."
$OldList = Get-WinUserLanguageList
$UserLanguageList = New-WinUserLanguageList -Language $LanguageTag
$UserLanguageList += $OldList | Where-Object { $_.LanguageTag -ne $LanguageTag }
Set-WinUserLanguageList -LanguageList $UserLanguageList -Force

Set-SystemPreferredUILanguage -Language $LanguageTag
Set-WinSystemLocale -SystemLocale $LanguageTag

Write-Output "System language and locale set to $LanguageTag. A reboot will be required after this script."

# ----------------------------------------------------------------------
# Step 3: Download and Run Virtual Desktop Optimization Tool (VDOT)
# ----------------------------------------------------------------------
$vdotZipUrl = 'https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/archive/refs/heads/main.zip'
$vdotZipPath = Join-Path $tempDir 'VDOT.zip'
$vdotExtractedPath = Join-Path $tempDir 'Virtual-Desktop-Optimization-Tool-main'
$defaultUserSettingsPath = Join-Path $vdotExtractedPath '2009\ConfigurationFiles\DefaultUserSettings.JSON'

Write-Output 'Downloading Virtual Desktop Optimization Tool...'
Invoke-WebRequest -Uri $vdotZipUrl -OutFile $vdotZipPath

Write-Output 'Extracting VDOT files...'
Expand-Archive -Path $vdotZipPath -DestinationPath $tempDir -Force
Get-ChildItem -Path $vdotExtractedPath -Recurse | Unblock-File

if (Test-Path $defaultUserSettingsPath) {
    Write-Output 'Patching DefaultUserSettings.JSON with UK regional settings...'
    $json = Get-Content $defaultUserSettingsPath -Encoding UTF8 | ConvertFrom-Json
    $appendItems = @(
        [ordered]@{ HivePath = 'HKLM:\VDOT_TEMP\Control Panel\International'; KeyName = 'Locale'; PropertyType = 'STRING'; PropertyValue = '00000809'; SetProperty = 'True' },
        [ordered]@{ HivePath = 'HKLM:\VDOT_TEMP\Control Panel\International'; KeyName = 'LocaleName'; PropertyType = 'STRING'; PropertyValue = 'en-GB'; SetProperty = 'True' },
        [ordered]@{ HivePath = 'HKLM:\VDOT_TEMP\Control Panel\International'; KeyName = 'sCurrency'; PropertyType = 'STRING'; PropertyValue = "`u00A3"; SetProperty = 'True' },
        [ordered]@{ HivePath = 'HKLM:\VDOT_TEMP\Control Panel\International'; KeyName = 'sShortDate'; PropertyType = 'STRING'; PropertyValue = 'dd/MM/yyyy'; SetProperty = 'True' },
        [ordered]@{ HivePath = 'HKLM:\VDOT_TEMP\Control Panel\International\Geo'; KeyName = 'Name'; PropertyType = 'STRING'; PropertyValue = 'GB'; SetProperty = 'True' },
        [ordered]@{ HivePath = 'HKLM:\VDOT_TEMP\Control Panel\International\Geo'; KeyName = 'Nation'; PropertyType = 'STRING'; PropertyValue = '242'; SetProperty = 'True' }
    )
    $json += $appendItems
    $json | ConvertTo-Json -Depth 5 | Out-File -FilePath $defaultUserSettingsPath -Encoding UTF8 -Force
    Write-Output 'UK locale entries appended to VDOT configuration.'
}
else {
    Write-Output 'WARNING: DefaultUserSettings.JSON not found — skipping locale injection.'
}

$vdotScript = Join-Path $vdotExtractedPath 'Windows_VDOT.ps1'
if (Test-Path $vdotScript) {
    Write-Output 'Running VDOT optimization...'
    & $vdotScript -AcceptEula -Verbose -Optimizations @(
        'Autologgers','DefaultUserSettings','LocalPolicy',
        'NetworkOptimizations','ScheduledTasks','Services','WindowsMediaPlayer'
    ) -AdvancedOptimizations @('Edge')
    Write-Output 'VDOT run completed.'
}
else {
    Write-Output 'ERROR: Windows_VDOT.ps1 not found!'
}

Write-Output '=== UK Language + Locale + VDOT configuration completed successfully ==='
Write-Output 'NOTE: Add a Windows Restart customizer next in your Image Builder sequence.'

