# variable from jinja2 template 
$environment = "%%{ environment }%%"
$deployment = "%%{ deployment }%%"
$attacker_instances = "%%{ attacker_instances }%%"
$attacker_dns_records = "%%{ attacker_dns_records }%%"
$target_instances = "%%{ target_instances }%%"
$target_dns_records = "%%{ target_dns_records }%%"
$attacker_k8s_services = "%%{ attacker_k8s_services }%%"
$target_k8s_services = "%%{ target_k8s_services }%%"

echo "${environment}:${deployment}" > C:\\Windows\\Temp\\run_me.log

[IO.StreamReader]::new(
    [IO.Compression.GzipStream]::new(
        [IO.MemoryStream]::new([Convert]::FromBase64String("${attacker_instances}")),
        [IO.Compression.CompressionMode]::Decompress
    )
).ReadToEnd() | Out-File -FilePath C:\\Windows\\Temp\\attacker_instances.log
[IO.StreamReader]::new(
    [IO.Compression.GzipStream]::new(
        [IO.MemoryStream]::new([Convert]::FromBase64String("${attacker_dns_records}")),
        [IO.Compression.CompressionMode]::Decompress
    )
).ReadToEnd() | Out-File -FilePath C:\\Windows\\Temp\\attacker_dns_records.log
[IO.StreamReader]::new(
    [IO.Compression.GzipStream]::new(
        [IO.MemoryStream]::new([Convert]::FromBase64String("${target_instances}")),
        [IO.Compression.CompressionMode]::Decompress
    )
).ReadToEnd() | Out-File -FilePath C:\\Windows\\Temp\\target_instances.log
[IO.StreamReader]::new(
    [IO.Compression.GzipStream]::new(
        [IO.MemoryStream]::new([Convert]::FromBase64String("${target_dns_records}")),
        [IO.Compression.CompressionMode]::Decompress
    )
).ReadToEnd() | Out-File -FilePath C:\\Windows\\Temp\\target_dns_records.log
[IO.StreamReader]::new(
    [IO.Compression.GzipStream]::new(
        [IO.MemoryStream]::new([Convert]::FromBase64String("${attacker_k8s_services}")),
        [IO.Compression.CompressionMode]::Decompress
    )
).ReadToEnd() | Out-File -FilePath C:\\Windows\\Temp\\attacker_k8s_services.log
[IO.StreamReader]::new(
    [IO.Compression.GzipStream]::new(
        [IO.MemoryStream]::new([Convert]::FromBase64String("${target_k8s_services}")),
        [IO.Compression.CompressionMode]::Decompress
    )
).ReadToEnd() | Out-File -FilePath C:\\Windows\\Temp\\target_k8s_services.log