# variable from jinja2 template 
$environment = "%%{ environment }%%"
$deployment = "%%{ deployment }%%"
$attacker_asset_inventory = "%%{ attacker_instances }%%"
$target_asset_inventory = "%%{ target_asset_inventory }%%"

echo "${environment}:${deployment}" > C:\\Windows\\Temp\\run_me.log

[IO.StreamReader]::new(
    [IO.Compression.GzipStream]::new(
        [IO.MemoryStream]::new([Convert]::FromBase64String("${attacker_asset_inventory}")),
        [IO.Compression.CompressionMode]::Decompress
    )
).ReadToEnd() | Out-File -FilePath C:\\Windows\\Temp\\attacker_asset_inventory.log
[IO.StreamReader]::new(
    [IO.Compression.GzipStream]::new(
        [IO.MemoryStream]::new([Convert]::FromBase64String("${target_asset_inventory}")),
        [IO.Compression.CompressionMode]::Decompress
    )
).ReadToEnd() | Out-File -FilePath C:\\Windows\\Temp\\target_asset_inventory.log