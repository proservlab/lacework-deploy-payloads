# Configurable Parameters
$scriptName = "deploy_docker"
$logRotationCount = 2
$scriptDelaySecs = 30  # Set desired delay here
$tempDir = "$env:TEMP"  # Use the TEMP directory
$logFile = "$tempDir\$scriptName.log"
$lockFile = "$tempDir\$scriptName.lock"
$preTasks = @("if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) { Write-Log `"Docker not installed, installing...`"; Invoke-WebRequest -UseBasicParsing `"https://raw.githubusercontent.com/microsoft/Windows-Containers/Main/helpful_tools/Install-DockerCE/install-docker-ce.ps1`" -o install-docker-ce.ps1; .\install-docker-ce.ps1 } else { Write-Log `"Docker is already installed.`" }")
$packages = @()  # e.g. "git", "docker-desktop"
$services = @("docker")
$postTasks = @()

function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    Write-Output "$timestamp $message" | Tee-Object -Append -FilePath $logFile
}

# Create Lock File if Not Exists
if (Test-Path $lockFile) {
    Write-Host "Another instance is already running. Exiting..."
    exit 1
} else {
    New-Item -Path $lockFile -ItemType File | Out-Null
}

# Log Rotation
for ($i = $logRotationCount - 1; $i -ge 1; $i--) {
    if (Test-Path "$logFile.$i") {
        Rename-Item "$logFile.$i" "$logFile.$($i + 1)" -ErrorAction Ignore
    }
}
if (Test-Path $logFile) {
    Rename-Item $logFile "$logFile.1" -ErrorAction Ignore
}

# Cleanup Lock File on Exit
function Cleanup {
    Remove-Item -Path $lockFile -ErrorAction Ignore
}

# Check for Chocolatey Installation
function Install-ChocolateyIfNeeded {
    Write-Log "Ensuring Chocolatey commands are on the path"
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
        Write-Host "Chocolatey is not installed. Installing Chocolatey..."
        # Set execution policy to allow the script to run
        Set-ExecutionPolicy Bypass -Scope Process -Force
        # Ensure TLS 1.2 (or better) is used
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        # Download and execute the official Chocolatey install script
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    } else {
        Write-Host "Chocolatey is already installed."
    }
}

# Check if Chocolatey or msiexec.exe is Running
function Check-ChocolateyInUse {
    return (Get-Process | Where-Object { $_.Name -match "choco|msiexec" }) -ne $null
}

function Is-ChocoPackageInstalled {
    param(
        [string]$packageName
    )
    $result = choco list --exact $packageName 2>$null
    return $result -match "^$packageName "
}

# Install Package Function for Git and Docker
function Install-Package {
    param(
        [string]$packageName
    )
    
    if (Is-ChocoPackageInstalled -packageName $packageName) {
        Write-Log "$packageName is already installed via Chocolatey. Skipping installation."
        return
    } else {
        Write-Log "$packageName is not installed. Installing $packageName..."
        Invoke-Expression "choco install $packageName -y"
        if (Get-PendingReboot) {
            Write-Log "A pending reboot was detected. Rebooting now..."
            Restart-Computer -Force
        } else {
            Write-Log "No pending reboot detected."
        }
    }
}

function Start-Deployed-Service {
    param(
        [string]$serviceName
    )
    Write-Log "Starting service: $serviceName"
    Start-Service -Name $serviceName
}

function Enable-Deployed-Service {
    param(
        [string]$serviceName
    )
    Write-Log "Enabling service: $serviceName"
    Set-Service -Name $serviceName -StartupType Automatic
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

try {
    Write-Log "Starting..."

    Write-Log "Checking for Chocolatey package manager..."
    Install-ChocolateyIfNeeded

    # Retry Mechanism if Chocolatey is Busy
    $retryAttempts = 5
    $attempt = 0
    while (Check-ChocolateyInUse -and $attempt -lt $retryAttempts) {
        Write-Log "Chocolatey or an install is in use. Retrying in 30 seconds..."
        Start-Sleep -Seconds 30
        $attempt++
    }

    if ($attempt -ge $retryAttempts) {
        Write-Log "Installation is still in use after multiple attempts. Exiting..."
        exit 1
    }

    # Randomized Delay before starting
    $randWait = Get-Random -Minimum 30 -Maximum 300
    Write-Log "Waiting $randWait seconds before starting..."
    Start-Sleep -Seconds $randWait

    # Execute Pre-tasks
    Write-Log "Starting pre-tasks..."
    foreach ($task in $preTasks) {
        Write-Log "Executing pre-task: $task"
        Invoke-Expression $task
    }

    # Install Chocolatey Packages (for example, Git and Docker Desktop)
    Write-Log "Starting package installation..."
    foreach ($package in $packages) {
        Install-Package -packageName $package
    }
    Write-Log "Package installation complete."

    # Start services (for example com.docker.service)
    Write-Log "Starting services after installation..."
    foreach ($service in $services) {
        Enable-Deployed-Service -serviceName $service
        Start-Deployed-Service -serviceName $service
    }
    Write-Log "Service start complete."

    # Execute Post-tasks
    Write-Log "Starting post-tasks..."
    foreach ($task in $postTasks) {
        Write-Log "Executing post-task: $task"
        Invoke-Expression $task
    }
} catch {
    Write-Log "Error: $_"
} finally {
    Cleanup
    Write-Log "Done"
}
