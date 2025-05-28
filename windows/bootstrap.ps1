param (
    [switch] $EnableSSH,                    # ‑EnableSSH to install & configure OpenSSH
    [string] $PublicKeyOpenSSHBase64,             # your public key in OpenSSH format
    [string] $InstanceName                  # computer name to set; omit to keep current name
)
function Invoke-PostSysprep {
    [CmdletBinding()]
    param (
        [switch] $EnableSSH,                    # ‑EnableSSH to install & configure OpenSSH
        [string] $PublicKeyOpenSSHBase64,             # your public key in OpenSSH format
        [string] $InstanceName                  # computer name to set; omit to keep current name
    )

    $LogFile = 'C:\Windows\Temp\install.log'
    $log = {
        param([string]$Message)
        "$((Get-Date -Format s))Z $Message" |
            Tee-Object -FilePath $LogFile -Append
    }

    try {
        & $log 'Start'

        # ---------- Optional OpenSSH setup ----------
        if ($EnableSSH) {
            & $log 'Enabling OpenSSH Server'
            if (-not (Get-WindowsCapability -Online |
                        Where-Object Name  -like 'OpenSSH.Server*' |
                        Where-Object State -eq   'Installed')) {

                Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
            }

            & $log 'Setting OpenSSH service to automatic'
            sc.exe config sshd start=auto | Out-Null
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' `
                                -Name DefaultShell `
                                -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
                                -Force

            if ($PublicKeyOpenSSHBase64) {
                & $log 'Setting public key for OpenSSH'
                $keyPath = 'C:\ProgramData\ssh\administrators_authorized_keys'
                [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($PublicKeyOpenSSHBase64)) | Out-File $keyPath -Encoding UTF8
                icacls.exe $keyPath /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F'
            }else{
                & $log 'No public key provided for OpenSSH'
            }
            & $log 'Starting OpenSSH service'
            sc.exe start sshd | Out-Null
        }else{
            & $log 'OpenSSH Server not enabled'
        }
        # ---------- End OpenSSH setup ----------

        # Install Chocolatey (abbreviated -UseB == -UseBasicParsing)
        Invoke-Expression ((Invoke-WebRequest -UseBasicParsing `
                            'https://community.chocolatey.org/install.ps1').Content)

        # Rename the computer if a name was supplied
        if ($InstanceName) {
            Rename-Computer -NewName $InstanceName -Force 2>$null
        }

        # Delayed reboot so the extension can finish cleanly
        Start-Job { Start-Sleep 90; Restart-Computer -Force } | Out-Null

    } catch {
        & $log "Error: $_"
        throw   # re‑throw so the extension reports failure
    } finally {
        & $log 'Done with Windows Sysprep'
    }
}

# -------------------------------------------------------------
# When the script file is executed, forward any parameters
# (this lets you call the script *or* dot‑source it)
Invoke-PostSysprep @PSBoundParameters
exit 0