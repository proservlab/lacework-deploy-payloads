####################################################################
# Example script to demonstrate how to use environment context in a pwsh script
######################################################################

# pull common functions from git repo
$url = 'https://raw.githubusercontent.com/proservlab/lacework-deploy-payloads/main/windows/common.ps1'
Invoke-Expression (Invoke-WebRequest $url -UseBasicParsing).Content

##################################################################
# Main Script
##################################################################

try {
    
    if ($null -eq $env:ENV_CONTEXT) {
        Write-Output "Environment context is not set."
        exit 1
    }

    $preTasks = @()
    $packages = @()  # e.g. "git"
    $services = @()
    $postTasks = @()

    Write-Log-Message "Starting..."

    Write-Log-Message "Checking for Chocolatey package manager..."
    Install-ChocolateyIfNeeded

    # Retry Mechanism if Chocolatey is Busy
    Wait-ForPackageManager

    # Randomized Delay before starting
    Random-Sleep 30 300

    # Execute Pre-tasks
    Write-Log-Message "Starting pre-tasks..."
    PreInstall-Commands $preTasks
    Write-Log-Message "Pre-tasks complete."

    # Install Chocolatey Packages (for example, Git and Docker Desktop)
    Write-Log-Message "Starting package installation..."
    Install-Packages -packageNames $packages
    Write-Log-Message "Package installation complete."

    # Start services (for example com.docker.service)
    Write-Log-Message "Starting services..."
    Start-Services -serviceNames $services
    Write-Log-Message "Service start complete."

    # Execute Post-tasks
    Write-Log-Message "Starting post-tasks..."
    PostInstall-Commands $postTasks
    Write-Log-Message "Post-tasks complete."

    #################################################################
    # Main script logic goes here
    #################################################################

    $env_context_compressed = "$env:ENV_CONTEXT"
    $env_context = Get-Base64GzipString -Base64Payload $env_context_compressed | ConvertFrom-Json
    Write-Log-Message "Environment context: $($env_context | ConvertTo-Json -Compress)"
    Write-Log-Message "Building full payload..."
    @{
        "env_context"                          = $env_context
        "tag"                                  = $env:TAG
        "deployment"                           = $env_context.deployment
        "environment"                          = $env_context.environment
        "attacker_asset_inventory"             = Get-Base64GzipString -Base64Payload $env_context.attacker_asset_inventory | ConvertFrom-Json
        "target_asset_inventory"               = Get-Base64GzipString -Base64Payload $env_context.target_asset_inventory | ConvertFrom-Json
        "attacker_lacework_agent_access_token" = $env_context.attacker_lacework_agent_access_token
        "attacker_lacework_server_url"         = $env_context.attacker_lacework_server_url
        "target_lacework_agent_access_token"   = $env_context.target_lacework_agent_access_token
        "target_lacework_server_url"           = $env_context.target_lacework_server_url
    } | ConvertTo-Json -Compress | Out-File -FilePath $env:TEMP\\run_me_env_context.log
    Write-Log-Message "Payload built and logged to $env:TEMP\\run_me.log"
}
catch {
    Write-Log-Message "Error: $_"
}
finally {
    Cleanup
    Write-Log-Message "Done"
}