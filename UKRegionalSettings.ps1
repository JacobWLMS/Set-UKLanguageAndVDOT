# Set-UKRegionalSettings.ps1
# Sets UK regional settings and runs VDOT with default user settings optimizations
# Fully self-contained for Azure Image Builder

Write-Output '=== Starting UK Regional Settings + VDOT configuration ==='

# ----------------------------------------------------------------------
# Step 1: Set System Locale and Regional Settings
# ----------------------------------------------------------------------
$LanguageTag = 'en-GB'

Write-Output "Setting system locale and regional settings to $LanguageTag..."

# Set system locale
Set-WinSystemLocale -SystemLocale $LanguageTag

# Set regional format settings
Set-Culture -CultureInfo $LanguageTag
Set-WinHomeLocation -GeoId 242  # United Kingdom

Write-Output "System locale and regional settings set to $LanguageTag."

# ----------------------------------------------------------------------
# Step 2: Apply UK locale defaults via VDOT DefaultUserSettings
# ----------------------------------------------------------------------
$tempDir = 'C:\AIBTemp'
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

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
# Step 3: Final cleanup
# ----------------------------------------------------------------------
Write-Output 'Performing final cleanup...'
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Output '=== UK Regional Settings + VDOT configuration completed successfully ==='
