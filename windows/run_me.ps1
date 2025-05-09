####################################################################
# Example script to demonstrate how to use environment context in a bash script
######################################################################

if ($env:ENV_CONTEXT -eq $null) {
    Write-Host "Environment context is not set."
    exit 1
}

$env_context_compressed = "$env:ENV_CONTEXT"

function Get-Base64GzipString($input) {
    return [IO.StreamReader]::new(
        [IO.Compression.GzipStream]::new(
            [IO.MemoryStream]::new([Convert]::FromBase64String("${env_context_compressed}")),
            [IO.Compression.CompressionMode]::Decompress
        )).ReadToEnd()
}

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