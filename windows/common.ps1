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

function Write-Log-Message-Message {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    Write-Output "$timestamp $message" | Tee-Object -Append -FilePath $logFile
}

function Random-Sleep {
    param(
        [int]$min = 30,
        [int]$max = 300
    )
    $sleepTime = Get-Random -Minimum $min -Maximum $max
    Write-Log-Message "Sleeping for $sleepTime seconds..."
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

function Lock-File {
    if (Test-Path $lockFile) {
        Write-Output "Another instance is already running. Exiting..."
        exit 1
    }
    else {
        New-Item -Path $lockFile -ItemType File | Out-Null
    }
}

function Rotate-Log {
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

function Cleanup {
    Remove-Item -Path $lockFile -ErrorAction SilentlyContinue
}

# Check for Chocolatey Installation
function Install-ChocolateyIfNeeded {
    Write-Log-Message "Ensuring Chocolatey commands are on the path"
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
        Write-Log-Message "Chocolatey is not installed. Installing Chocolatey..."
        # Set execution policy to allow the script to run
        Set-ExecutionPolicy Bypass -Scope Process -Force
        # Ensure TLS 1.2 (or better) is used
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        # Download and execute the official Chocolatey install script
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    else {
        Write-Log-Message "Chocolatey is already installed."
    }
}

# Check if Chocolatey or msiexec.exe is Running
function Check-ChocolateyInUse {
    return $null -ne (Get-Process | Where-Object { $_.Name -match "choco|msiexec" })
}

function Is-Command-Available {
    param(
        [string]$command
    )
    $result = Get-Command $command -ErrorAction SilentlyContinue
    return $result -ne $null
}

function Is-ChocoPackageInstalled {
    param(
        [string]$packageName
    )
    $result = choco list --exact $packageName 2>$null
    return $result -match "^$packageName "
}

# Install Package Function for Git and Docker
function Install-Packages {
    param(
        [string[]]$packageNames
    )
  
    foreach ($packageName in $packageNames) {
        Write-Log-Message "Installing package: $packageName"
        if (Is-ChocoPackageInstalled -packageName $packageName) {
            Write-Log-Message "$packageName is already installed via Chocolatey. Skipping installation."
            return
        }
        else {
            Write-Log-Message "$packageName is not installed. Installing $packageName..."
            Invoke-Expression "choco install $packageName -y"
            if (Get-PendingReboot) {
                Write-Log-Message "A pending reboot was detected. Rebooting now..."
                Restart-Computer -Force
            }
            else {
                Write-Log-Message "No pending reboot detected."
            }
        }
    }
}

function Start-Services {
    param(
        [string[]]$serviceName
    )
    foreach ($serviceName in $serviceNames) {
        Write-Log-Message "Starting service: $serviceName"
        Start-Service -Name $serviceName
    }
}

function Stop-Services {
    param(
        [string[]]$serviceName
    )
    foreach ($serviceName in $serviceNames) {
        Write-Log-Message "Starting service: $serviceName"
        Start-Service -Name $serviceName
    }
}

function Enable-Services {
    param(
        [string[]]$serviceNames
    )
    foreach ($serviceName in $serviceNames) {
        Write-Log-Message "Enabling service: $serviceName"
        Set-Service -Name $serviceName -StartupType Automatic
    }
}

function Restart-Computer-IfNeeded {
    # Example usage:
    if (Get-PendingReboot) {
        Write-Log-Message "A pending reboot was detected. Rebooting now..."
        Restart-Computer -Force
    }
    else {
        Write-Log-Message "No pending reboot detected."
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

function Wait-ForPackageManager {
    param(
        [int]$maxWaitTime = 300
    )
    $waitTime = 0
    while ($waitTime -lt $maxWaitTime) {
        if (-not (Check-ChocolateyInUse)) {
            Write-Log-Message "Package manager is not in use. Proceeding with installation."
            return
        }
        Start-Sleep -Seconds 5
        $waitTime += 5
    }
    Write-Log-Message "Package manager is still in use after $maxWaitTime seconds. Exiting..."
    exit 1
}

function PreInstall-Commands {
    param(
        [string[]]$preTasks
    )
    foreach ($task in $preTasks) {
        Write-Log-Message "Executing pre-task: $task"
        Invoke-Expression $task
    }
}

function PostInstall-Commands {
    param(
        [string[]]$postTasks
    )
    foreach ($task in $postTasks) {
        Write-Log-Message "Executing post-task: $task"
        Invoke-Expression $task
    }
}