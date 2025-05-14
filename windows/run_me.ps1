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

    Log-RotationCount = 2
    Rotate-Log -LogRotationCount $Log-RotationCount

    Write-LogMessage "Starting..."

    Write-LogMessage "Checking for Chocolatey package manager..."
    Install-Chocolatey

    # Retry Mechanism if Chocolatey is Busy
    Wait-PackageManager

    # Randomized Delay before starting
    Invoke-RandomSleep 30 300

    # Execute Pre-tasks
    Write-LogMessage "Starting pre-tasks..."
    Invoke-CommandList $preTasks
    Write-LogMessage "Pre-tasks complete."

    # Install Chocolatey Packages (for example, Git and Docker Desktop)
    Write-LogMessage "Starting package installation..."
    Install-ChocoPackage -packageNames $packages
    Write-LogMessage "Package installation complete."

    # Start services (for example com.docker.service)
    Write-LogMessage "Starting services..."
    Start-ServiceList -serviceNames $services
    Write-LogMessage "Service start complete."

    # Execute Post-tasks
    Write-LogMessage "Starting post-tasks..."
    PostInstall-CommandList $postTasks
    Write-LogMessage "Post-tasks complete."

    #################################################################
    # Main script logic goes here
    #################################################################

    $env_context_compressed = "$env:ENV_CONTEXT"
    $env_context = Get-Base64GzipString -Base64Payload $env_context_compressed | ConvertFrom-Json
    Write-LogMessage "Environment context: $($env_context | ConvertTo-Json -Compress)"
    Write-LogMessage "Building full payload..."
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
    Write-LogMessage "Payload built and logged to $env:TEMP\\run_me.log"
}
catch {
    Write-LogMessage "Error: $_"
}
finally {
    Invoke-Cleanup
    Write-LogMessage "Done"
}