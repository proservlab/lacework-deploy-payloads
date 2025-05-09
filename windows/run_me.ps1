####################################################################
# Example script to demonstrate how to use environment context in a pwsh script
######################################################################

# pull common functions from git repo
$url = 'https://raw.githubusercontent.com/proservlab/lacework-deploy-payloads/main/windows/common.ps1'
iex (Invoke-WebRequest $url -UseBasicParsing).Content

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
$attacker_lacework_agent_access_token = Get-Base64GzipString($env_context["attacker_lacework_agent_access_token"])
$attacker_lacework_server_url = Get-Base64GzipString($env_context["attacker_lacework_server_url"])
$target_lacework_agent_access_token = Get-Base64GzipString($env_context["target_lacework_agent_access_token"])
$target_lacework_server_url = Get-Base64GzipString($env_context["target_lacework_server_url"])

$output = @{
    deployment = $deployment
    environment = $environment
    attacker_asset_inventory = $attacker_asset_inventory
    target_asset_inventory = $target_asset_inventory
    attacker_lacework_agent_access_token = $attacker_lacework_agent_access_token
    attacker_lacework_server_url = $attacker_lacework_server_url
    target_lacework_agent_access_token = $target_lacework_agent_access_token
    target_lacework_server_url = $target_lacework_server_url
} | ConvertTo-Json -Depth | Out-File -FilePath C:\\Windows\\Temp\\run_me.log

Remove-Item $func -Force