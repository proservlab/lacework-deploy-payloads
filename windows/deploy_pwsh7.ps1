######################################################################
# Enable Common Functions
#####################################################################

# pull common functions from git repo
$url = 'https://raw.githubusercontent.com/proservlab/lacework-deploy-payloads/main/windows/common.ps1'
Invoke-Expression (Invoke-WebRequest $url -UseBasicParsing).Content


##################################################################
# Main Script
##################################################################

try {

    <#  Upgrade Windows PowerShell 5.x to PowerShell 7.x  (cloud‑friendly) #>
    $TargetVersion=''

    $logRoot = "$env:SystemDrive\InstallLogs"; mkdir $logRoot -ea 0 | out-null
    Write-Log-Message "Starting installation transcript: $logRoot\pwsh-upgrade_{0:yyyyMMdd_HHmmss}.log"
    Start-Transcript -Path ("$logRoot\pwsh-upgrade_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $existing = Get-Command pwsh.exe -EA SilentlyContinue
    if ($existing) { Write-Log-Message "PowerShell 7 already present"; Stop-Transcript; return }

    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    if (-not $TargetVersion) {
        $TargetVersion = (Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' `
                        -Headers @{Accept='application/vnd.github+json'}).tag_name.TrimStart('v')
    }
    $msi = "PowerShell-$TargetVersion-win-$arch.msi"
    $tmp = Join-Path $env:TEMP $msi
    Invoke-WebRequest -Uri "https://github.com/PowerShell/PowerShell/releases/download/v$TargetVersion/$msi" `
                    -OutFile $tmp -UseBasicParsing
    $msiArgs = "/i `"$tmp`" /qn /norestart ADD_PATH=1 ENABLE_PSREMOTING=1"
    (Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -PassThru).ExitCode | where {$_} | `
        ForEach-Object { Write-Log-Message "msiexec failed with $_" }

    # ----- make pwsh available in THIS session & verify -------------------
    $pwshPath = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (-not (Test-Path $pwshPath)) { throw "pwsh.exe not found at $pwshPath" }
    Set-Alias pwsh $pwshPath
    $ver = & $pwshPath -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion'
    Write-Log-Message "PowerShell $ver installed at $pwshPath"

    Stop-Transcript

    if (Get-PendingReboot) {
        Write-Log-Message "A pending reboot was detected. Rebooting now..."
        Cleanup
        Restart-Computer -Force
    }
    else {
        Write-Log-Message "No pending reboot detected."
    }
}
catch {
    Write-Log-Message "Error: $_"
}
finally {
    Cleanup
    Write-Log-Message "Done"
}
