echo "MINECRAFT BEDROCK SERVER UPDATE SCRIPT - UberGuidoZ GitHub Edition v1.0 (7/1/25)"

# INSTRUCTIONS: MICROSOFT POWERSHELL SCRIPT
# (1) RENAME gameDir TO YOUR SERVER DIRECTORY
# (2) PUT THIS SCRIPT FILE IN THAT DIRECTORY WITH .PS1 FILE EXTENSION
# (3) TEST IT IN POWERSHELL, MAKE SURE IT WORKS
# (4) CREATE POWERSHELL TASK IN WINDOWS TASK SCHEDULER TO RUN PERIODICALLY (WHEN NOBODY IS LIKELY TO BE CONNECTED TO SERVER)
# (5) ???
# (6) PROFIT
#
# FULL REWRITE BY u/UberGuidoZ TO USE GITHUB JSON VERSIONING INSTEAD!
# Mojang changed to javascript page rewrites and it broke everything...
# NOW INCLUDES UPDATE AND ERROR/SUCCESS LOGGING PLUS OLD BACKLUP CLEANUP
#
# CREDITS (Original): u/WhetselS u/Nejireta_ u/rockknocker
# LINKS: 	https://www.reddit.com/r/PowerShell/comments/xy9xqh/script_for_updating_minecraft_bedrock_server_on/
#			https://www.dvgaming.de/minecraft-pe-bedrock-windows-automatic-update-script/

# Define game directory
# YOU MUST CHANGE THIS BUT NOTHING ELSE
$gameDir = "C:\Users\Owner\Desktop\Minecraft Server"
cd $gameDir

# Setup log folder and log file
$logDir = "$gameDir\logs"
if (!(Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir
}
$logFile = "$logDir\update-{0}.log" -f (Get-Date -Format "yyyy-MM-dd")
Start-Transcript -Path $logFile -Append

# Clean up logs older than 30 days
Get-ChildItem -Path $logDir -Filter *.log | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force

# Create backup directory if it doesn't exist
if (!(Test-Path -Path "$gameDir\BACKUP")) {
    New-Item -ItemType Directory -Path "$gameDir\BACKUP"
}

# Step 1: Fetch version index from GitHub v2 branch
$versionsUrl = "https://raw.githubusercontent.com/EndstoneMC/bedrock-server-data/refs/heads/v2/versions.json"
try {
    $versionsIndex = Invoke-WebRequest -Uri $versionsUrl -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
} catch {
    Write-Error "Failed to fetch versions index from GitHub v2 branch."
    exit 1
}

$buildType = "release"
$latestVersion = $versionsIndex.$buildType.latest
Write-Host "Latest $buildType version: $latestVersion"

# Step 2: Construct metadata URL and download it
$metadataUrl = "https://raw.githubusercontent.com/EndstoneMC/bedrock-server-data/refs/heads/v2/$buildType/$latestVersion/metadata.json"
try {
    $metadata = Invoke-WebRequest -Uri $metadataUrl -UseBasicParsing | Select-Object -ExpandProperty Content | ConvertFrom-Json
} catch {
    Write-Error "Failed to fetch metadata for version $latestVersion."
    exit 1
}

$url = $metadata.binary.windows.url
$sha256 = $metadata.binary.windows.sha256
$filename = Split-Path $url -Leaf
$output = "$gameDir\BACKUP\$filename"

Write-Host "Download URL: $url"
Write-Host "SHA256: $sha256"
Write-Host "Saving to: $output"

# Check if already downloaded

$alreadyDownloaded = Test-Path -Path $output
if (!$alreadyDownloaded) {

    # Stop the server if running
    if (Get-Process -Name bedrock_server -ErrorAction SilentlyContinue) {
        Write-Host "Stopping running bedrock_server..."
        Stop-Process -Name "bedrock_server"
    }

    # Backup config files
    foreach ($file in @("server.properties", "allowlist.json", "permissions.json")) {
        if (Test-Path -Path $file) {
            Write-Host "Backing up $file"
            Copy-Item -Path $file -Destination "$gameDir\BACKUP\$file"
        }
    }

    # Download the server zip
    Write-Host "Downloading $filename..."
    Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing -TimeoutSec 30

    # Verify SHA256
    if ($sha256) {
        $computed = Get-FileHash -Algorithm SHA256 -Path $output
        if ($computed.Hash -ne $sha256.ToUpper()) {
            Write-Error "Downloaded file is corrupt (SHA256 mismatch)."
            exit 1
        }
        Write-Host "SHA256 checksum verified."

    # Clean up old versions in BACKUP folder (keep only the latest)
    Write-Host "Cleaning up old backups..."
    Get-ChildItem -Path "$gameDir\BACKUP" -Filter "bedrock-server-*.zip" | Where-Object { $_.Name -ne $filename } | Remove-Item -Force
    }

    # Extract the zip file
    Write-Host "Extracting archive..."
    Expand-Archive -LiteralPath $output -DestinationPath $gameDir -Force

    # Restore backed-up configs
    foreach ($file in @("server.properties", "allowlist.json", "permissions.json")) {
        if (Test-Path -Path "$gameDir\BACKUP\$file") {
            Write-Host "Restoring $file"
            Copy-Item -Path "$gameDir\BACKUP\$file" -Destination "$gameDir\$file" -Force
        }
    }

    # Restart the server
    Write-Host "Starting bedrock_server..."
    Start-Process -FilePath "$gameDir\bedrock_server.exe"
} else {
    Write-Host "Update already downloaded: $filename"
}

# Update history tracking
$historyFile = "$logDir\update_history.txt"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
if ($alreadyDownloaded) {
    Add-Content -Path $historyFile -Value "$timestamp - Installed version $latestVersion - SKIPPED (already downloaded)"
} else {
    Add-Content -Path $historyFile -Value "$timestamp - Installed version $latestVersion - SUCCESS"
}

Start-Sleep -Seconds 5
Stop-Transcript
exit