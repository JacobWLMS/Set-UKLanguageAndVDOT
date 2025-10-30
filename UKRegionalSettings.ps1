# Set-UKLanguageAndVDOT.ps1
# Installs English (United Kingdom) language pack, sets locale, and runs VDOT with only default user settings optimizations
# Fully self-contained for Azure Image Builder

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
        # Try without source first (lets Windows Update handle it)
        $result = Add-WindowsCapability -Online -Name $cap -ErrorAction Stop
        Write-Output "  Status: $($result.RestartNeeded)"
    } catch {
        Write-Warning "Failed to install $cap : $_"
        # Try with explicit source as fallback
        try {
            Write-Output "  Retrying with explicit source..."
            Add-WindowsCapability -Online -Name $cap -Source "https://go.microsoft.com/fwlink/?linkid=2156295" -LimitAccess -ErrorAction Stop
        } catch {
            Write-Warning "  Retry also failed: $_"
        }
    }
}

Write-Output 'Language pack installation completed. Waiting for provisioning...'
Start-Sleep -Seconds 30

# Verify installation
Write-Output 'Verifying installed capabilities...'
$installed = Get-WindowsCapability -Online | Where-Object { $_.Name -like "Language.*$LanguageTag*" -and $_.State -eq 'Installed' }
Write-Output "Installed: $($installed.Count) of $($capabilities.Count) capabilities"
foreach ($cap in $installed) {
    Write-Output "  ✓ $($cap.Name)"
}

# ----------------------------------------------------------------------
# Step 2: Set System Locale and Language
# ----------------------------------------------------------------------
Write-Output "Setting system and user language to $LanguageTag..."

# Set user language list
$UserLanguageList = New-WinUserLanguageList -Language $LanguageTag
Set-WinUserLanguageList -LanguageList $UserLanguageList -Force

# Set system locale
Set-WinSystemLocale -SystemLocale $LanguageTag

# Set additional regional settings
Set-Culture -CultureInfo $LanguageTag
Set-WinHomeLocation -GeoId 242  # United Kingdom

Write-Output "System language and locale set to $LanguageTag."

# ----------------------------------------------------------------------
# Step 2.5: Clean up language pack provisioning state
# ----------------------------------------------------------------------
Write-Output 'Cleaning up provisioning state...'
try {
    # Clear pending operations that might interfere with sysprep
    $null = DISM.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
    Write-Output 'Component cleanup completed.'
} catch {
    Write-Warning "Cleanup warning: $_"
}

Start-Sleep -Seconds 10

# ----------------------------------------------------------------------
# Step 3: Apply UK locale defaults via VDOT DefaultUserSettings
# ----------------------------------------------------------------------
$vdotZipUrl = 'https://github.com/The-Virtual-Desktop-Team/Virtual-Desktop-Optimization-Tool/archive/refs/heads/main.zip'
$vdotZipPath = Join-Path $tempDir 'VDOT.zip'
$vdotExtractedPath = Join-Path $tempDir 'Virtual-Desktop-Optimization-Tool-main'
$defaultUserSettingsPath = Join-Path $vdotExtractedPath '2009\ConfigurationFiles\DefaultUserSettings.JSON'

Write-Output 'Downloading Virtual Desktop Optimization Tool (VDOT)...'
Invoke-WebRequest -Uri $vdotZipUrl -OutFile $vdotZipPath -UseBasicParsing
Expand-Archive -Path $vdotZipPath -DestinationPath $tempDir -Force
Get-ChildItem -Path $vdotExtractedPath -Recurse | Unblock-File

if (Test-Path $defaultUserSettingsPath) {
    Write-Output 'Injecting UK locale entries into DefaultUserSettings.JSON...'
    $json = Get-Content $defaultUserSettingsPath -Encoding UTF8 | ConvertFrom-Json
    
    # Remove any existing regional settings to avoid duplicates
    $json = $json | Where-Object { 
        -not ($_.HivePath -like "*International*" -and ($_.KeyName -in @("Locale", "LocaleName", "sCurrency", "sShortDate"))) -and
        -not ($_.HivePath -like "*International\Geo*" -and ($_.KeyName -in @("Name", "Nation")))
    }
    
    $appendItems = @(
        [ordered]@{ HivePath='HKLM:\VDOT_TEMP\Control Panel\International'; KeyName='Locale'; PropertyType='STRING'; PropertyValue='00000809'; SetProperty='True' },
        [ordered]@{ HivePath='HKLM:\VDOT_TEMP\Control Panel\International'; KeyName='LocaleName'; PropertyType='STRING'; PropertyValue='en-GB'; SetProperty='True' },
        [ordered]@{ HivePath='HKLM:\VDOT_TEMP\Control Panel\International'; KeyName='sCurrency'; PropertyType='STRING'; PropertyValue='£'; SetProperty='True' },
        [ordered]@{ HivePath='HKLM:\VDOT_TEMP\Control Panel\International'; KeyName='sShortDate'; PropertyType='STRING'; PropertyValue='dd/MM/yyyy'; SetProperty='True' },
        [ordered]@{ HivePath='HKLM:\VDOT_TEMP\Control Panel\International\Geo'; KeyName='Name'; PropertyType='STRING'; PropertyValue='GB'; SetProperty='True' },
        [ordered]@{ HivePath='HKLM:\VDOT_TEMP\Control Panel\International\Geo'; KeyName='Nation'; PropertyType='STRING'; PropertyValue='242'; SetProperty='True' }
    )
    
    $json = @($json) + $appendItems
    $json | ConvertTo-Json -Depth 10 | Out-File -FilePath $defaultUserSettingsPath -Encoding UTF8 -Force
    Write-Output 'UK locale settings injected successfully.'
}

$vdotScript = Join-Path $vdotExtractedPath 'Windows_VDOT.ps1'
if (Test-Path $vdotScript) {
    Write-Output 'Running VDOT DefaultUserSettings optimization only...'
    Push-Location (Split-Path $vdotScript -Parent)
    & $vdotScript -AcceptEula -Verbose -Optimizations @('DefaultUserSettings')
    Pop-Location
    Write-Output 'VDOT DefaultUserSettings applied successfully.'
}
else {
    Write-Warning 'VDOT script not found — skipping.'
}

# ----------------------------------------------------------------------
# Step 4: Final cleanup
# ----------------------------------------------------------------------
Write-Output 'Performing final cleanup...'
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Output '=== UK Language + Locale + VDOT configuration completed successfully ==='
Write-Output 'NOTE: Add a Windows Restart customizer next in your Image Builder sequence.'
Write-Output 'Then allow sufficient time (10-15 mins) before running sysprep.'
