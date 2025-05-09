####################################################################
# Example script to demonstrate how to use environment context in a pwsh script
######################################################################

# pull common functions from git repo
$url = 'https://raw.githubusercontent.com/proservlab/lacework-deploy-payloads/main/windows/common.ps1'
$func = [System.IO.Path]::GetTempFileName()
Invoke-WebRequest $url -UseBasicParsing -OutFile $func

# dot‑source loads the function into current scope
. $func

if ($env:ENV_CONTEXT -eq $null) {
    Write-Host "Environment context is not set."
    Remove-Item $func -Force
    exit 1
}

$env_context_compressed = "$env:ENV_CONTEXT"

$env_context = Get-Base64GzipString($env_context_compressed) | ConvertFrom-Json
$deployment = $env_context["deployment"]
$environment = $env_context["environment"]
$attacker_asset_inventory = Get-Base64GzipString($env_context["attacker_asset_inventory"])
$target_asset_inventory = Get-Base64GzipString($env_context["target_asset_inventory"])

$output = @{
    deployment = $deployment
    environment = $environment
    attacker_asset_inventory = $attacker_asset_inventory
    target_asset_inventory = $target_asset_inventory
} | ConvertTo-Json -Depth | Out-File -FilePath C:\\Windows\\Temp\\run_me.log

Remove-Item $func -Force