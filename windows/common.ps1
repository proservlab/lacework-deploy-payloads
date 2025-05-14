##############################################################
# Variables
################################################################

$tag = $env:TAG
$scriptName = "$tag"
$tempDir = "$env:TEMP"  # Use the TEMP directory
$logFile = "$tempDir\$scriptName.log"
$lockFile = "$tempDir\$scriptName.lock"

##########################################################
# Functions
##########################################################

function Write-LogMessage {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    Write-Output "$timestamp $message" | Tee-Object -Append -FilePath $logFile
}

function Invoke-RandomSleep {
    param(
        [int]$min = 30,
        [int]$max = 300
    )
    $sleepTime = Get-Random -Minimum $min -Maximum $max
    Write-LogMessage "Sleeping for $sleepTime seconds..."
    Start-Sleep -Seconds $sleepTime
}

function Get-Base64GzipString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Base64Payload
    )
    return [IO.StreamReader]::new(
        [IO.Compression.GzipStream]::new(
            [IO.MemoryStream]::new([Convert]::FromBase64String($Base64Payload)),
            [IO.Compression.CompressionMode]::Decompress
        )
    ).ReadToEnd()
}

function New-LockFile {
    if (Test-Path $lockFile) {
        Write-Output "Another instance is already running. Exiting..."
        exit 1
    }
    else {
        New-Item -Path $lockFile -ItemType File | Out-Null
    }
}

function Invoke-LogRotation {
    param(
        [int]$LogRotationCount = 2
    )
    for ($i = $LogRotationCount - 1; $i -ge 1; $i--) {
        if (Test-Path "$logFile.$i") {
            Rename-Item "$logFile.$i" "$logFile.$($i + 1)" -ErrorAction Ignore
        }
    }
    if (Test-Path $logFile) {
        Rename-Item $logFile "$logFile.1" -ErrorAction Ignore
    }
}

function Invoke-Cleanup {
    Remove-Item -Path $lockFile -ErrorAction SilentlyContinue
}

# Check for Chocolatey Installation
function Install-Chocolatey {
    Write-LogMessage "Ensuring Chocolatey commands are on the path"
    $chocoInstallVariableName = "ChocolateyInstall"
    $chocoPath = [Environment]::GetEnvironmentVariable($chocoInstallVariableName)

    if (-not $chocoPath) {
        $chocoPath = "$env:ALLUSERSPROFILE\Chocolatey"
    }

    if (-not (Test-Path ($chocoPath))) {
        $chocoPath = "$env:PROGRAMDATA\chocolatey"
    }

    $chocoExePath = Join-Path $chocoPath -ChildPath 'bin'

    # Update current process PATH environment variable if it needs updating.
    if ($env:Path -notlike "*$chocoExePath*") {
        $env:Path = [Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::Machine)
    }

    # Check if Chocolatey is installed; if not, install it.
    if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
        Write-LogMessage "Chocolatey is not installed. Installing Chocolatey..."
        # Set execution policy to allow the script to run
        Set-ExecutionPolicy Bypass -Scope Process -Force
        # Ensure TLS 1.2 (or better) is used
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        # Download and execute the official Chocolatey install script
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    else {
        Write-LogMessage "Chocolatey is already installed."
    }
}

# Check if Chocolatey or msiexec.exe is Running
function Test-ChocoInUse {
    return $null -ne (Get-Process | Where-Object { $_.Name -match "choco|msiexec" })
}

function Test-CommandAvailability {
    param(
        [string]$command
    )
    $result = Get-Command $command -ErrorAction SilentlyContinue
    return $null -ne $result
}

function Test-ChocoPackageInstalled {
    param(
        [string]$packageName
    )
    $result = choco list --exact $packageName 2>$null
    return $result -match "^$packageName "
}

# Install Package Function for Git and Docker
function Install-ChocoPackage {
    param(
        [string[]]$packageNames
    )

    foreach ($packageName in $packageNames) {
        Write-LogMessage "Installing package: $packageName"
        if (Test-ChocoPackageInstalled -packageName $packageName) {
            Write-LogMessage "$packageName is already installed via Chocolatey. Skipping installation."
            return
        }
        else {
            Write-LogMessage "$packageName is not installed. Installing $packageName..."
            Invoke-Expression "choco install $packageName -y"
            if (Get-PendingReboot) {
                Write-LogMessage "A pending reboot was detected. Rebooting now..."
                Restart-Computer -Force
            }
            else {
                Write-LogMessage "No pending reboot detected."
            }
        }
    }
}

function Start-ServiceList {
    param(
        [string[]]$serviceName
    )
    foreach ($serviceName in $serviceNames) {
        Write-LogMessage "Starting service: $serviceName"
        Start-Service -Name $serviceName
    }
}

function Stop-ServiceList {
    param(
        [string[]]$serviceName
    )
    foreach ($serviceName in $serviceNames) {
        Write-LogMessage "Starting service: $serviceName"
        Start-Service -Name $serviceName
    }
}

function Enable-ServiceList {
    param(
        [string[]]$serviceNames
    )
    foreach ($serviceName in $serviceNames) {
        Write-LogMessage "Enabling service: $serviceName"
        Set-Service -Name $serviceName -StartupType Automatic
    }
}

function Restart-ComputerIfNeeded {
    # Example usage:
    if (Get-PendingReboot) {
        Write-LogMessage "A pending reboot was detected. Rebooting now..."
        Restart-Computer -Force
    }
    else {
        Write-LogMessage "No pending reboot detected."
    }
}

function Get-PendingReboot {
    # Check for pending file rename operations
    $pendingFileRename = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
            -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($pendingFileRename) {
        return $true
    }

    # Check for Windows Update pending reboot key
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        return $true
    }

    # Check for Component Based Servicing pending reboot key
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        return $true
    }

    # No indicators found, assume no pending reboot
    return $false
}

function Wait-PackageManager {
    param(
        [int]$maxWaitTime = 300
    )
    $waitTime = 0
    while ($waitTime -lt $maxWaitTime) {
        if (-not (Test-ChocoInUse)) {
            Write-LogMessage "Package manager is not in use. Proceeding with installation."
            return
        }
        Start-Sleep -Seconds 5
        $waitTime += 5
    }
    Write-LogMessage "Package manager is still in use after $maxWaitTime seconds. Exiting..."
    exit 1
}

function Invoke-CommandList {
    param(
        [string[]]$tasks
    )
    foreach ($task in $tasks) {
        Write-LogMessage "Executing task: $task"
        Invoke-Expression $task
    }
}

# Always rotate log file and start lock-file
Invoke-LogRotation -LogRotationCount 2
New-LockFile

# Trap exit and cleanup
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    try { Invoke-Cleanup } catch { Write-LogMessage "Error during cleanup: $_" }
}