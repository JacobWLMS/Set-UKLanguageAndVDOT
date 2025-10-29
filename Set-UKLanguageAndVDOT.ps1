# Set-UKLanguageAndVDOT.ps1
# Installs English (United Kingdom) language pack, sets locale, and runs VDOT
# Fully self-contained for Azure Image Builder

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$PSDefaultParameterValues['Out-File:Encoding'] = 'UTF8'

Write-Output '=== Starting UK Language + Locale + VDOT configuration ==='

# ----------------------------------------------------------------------
# Step 1: Install English (United Kingdom) language pack + FoD
# ----------------------------------------------------------------------
$tempDir = 'C:\AIBTemp'
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Write-Output 'Preparing servicing stack...'
Start-Service TrustedInstaller -ErrorAction SilentlyContinue
Start-Service wuauserv -ErrorAction SilentlyContinue
Start-Sleep -Seconds 10

$LanguageTag = 'en-GB'
Write-Output "Installing language pack for $LanguageTag ..."

# Install the core language pack and basic features
$capabilities = @(
    "Language.Basic~~~$LanguageTag~0.0.1.0",
    "Language.Handwriting~~~$LanguageTag~0.0.1.0",
    "Language.OCR~~~$LanguageTag~0.0.1.0",
    "Language.Speech~~~$LanguageTag~0.0.1.0",
    "Language.TextToSpeech~~~$LanguageTag~0.0.1.0"
)

foreach ($cap in $capabilities) {
    Write-Output "Installing capability: $cap"
    try {
        Add-WindowsCapability -Online -Name $cap -LimitAccess -Source "https://go.microsoft.com/fwlink/?linkid=2156295" -ErrorAction Stop
    } catch {
        Write-Warning "Failed to install $cap : $_"
    }
}

Write-Output 'Language pack installation completed.'

# ----------------------------------------------------------------------
# Step 2: Set System Locale and Language
# ----------------------------------------------------------------------
Write-Output "Setting system and user language to $LanguageTag..."
$UserLanguageList = New-WinUserLanguageList -Language $LanguageTag
Set-WinUserLanguageList -LanguageList $UserLanguageList -Force

Set-SystemPreferredUILanguage -Language $LanguageTag
Set-WinSystemLocale -SystemLocale $LanguageTag
Write-Output "System language and locale set to $LanguageTag."

# ----------------------------------------------------------------------
# Step 3: Download and Run Virtual Desktop Optimization Tool (VDOT)
# ----------------------------------------------------------------------
$vdotZipUrl = 'https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/archive/refs/heads/main.zip'
$vdotZipPath = Join-Path $tempDir 'VDOT.zip'
$vdotExtractedPath = Join-Path $tempDir 'Virtual-Desktop-Optimization-Tool-main'
$defaultUserSettingsPath = Join-Path $vdotExtractedPath '2009\ConfigurationFiles\DefaultUserSettings.JSON'

Write-Output 'Downloading Virtual Desktop Optimization Tool...'
Invoke-WebRequest -Uri $vdotZipUrl -OutFile $vdotZipPath
Expand-Archive -Path $vdotZipPath -DestinationPath $tempDir -Force
Get-ChildItem -Path $vdotExtractedPath -Recurse | Unblock-File

if (Test-Path $defaultUserSettingsPath) {
    Write-Output 'Injecting UK locale entries into DefaultUserSettings.JSON...'
    $json = Get-Content $defaultUserSettingsPath -Encoding UTF8 | ConvertFrom-Json
    $appendItems = @(
        [ordered]@{ HivePath='HKLM:\VDOT_TEMP\Control Panel\International'; KeyName='Locale'; PropertyType='STRING'; PropertyValue='00000809'; SetProperty='True' },
        [ordered]@{ HivePath='HKLM:\VDOT_TEMP\Control Panel\International'; KeyName='LocaleName'; PropertyType='STRING'; PropertyValue='en-GB'; SetProperty='True' },
        [ordered]@{ HivePath='HKLM:\VDOT_TEMP\Control Panel\International'; KeyName='sCurrency'; PropertyType='STRING'; PropertyValue='`u00A3'; SetProperty='True' },
        [ordered]@{ HivePath='HKLM:\VDOT_TEMP\Control Panel\International'; KeyName='sShortDate'; PropertyType='STRING'; PropertyValue='dd/MM/yyyy'; SetProperty='True' },
        [ordered]@{ HivePath='HKLM:\VDOT_TEMP\Control Panel\International\Geo'; KeyName='Name'; PropertyType='STRING'; PropertyValue='GB'; SetProperty='True' },
        [ordered]@{ HivePath='HKLM:\VDOT_TEMP\Control Panel\International\Geo'; KeyName='Nation'; PropertyType='STRING'; PropertyValue='242'; SetProperty='True' }
    )
    $json += $appendItems
    $json | ConvertTo-Json -Depth 5 | Out-File -FilePath $defaultUserSettingsPath -Encoding UTF8 -Force
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
