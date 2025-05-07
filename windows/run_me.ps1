# variable from jinja2 template 
$env_context_compressed = "$env:ENV_CONTEXT"

[IO.StreamReader]::new(
    [IO.Compression.GzipStream]::new(
        [IO.MemoryStream]::new([Convert]::FromBase64String("${env_context_compressed}")),
        [IO.Compression.CompressionMode]::Decompress
    )
).ReadToEnd() | Out-File -FilePath C:\\Windows\\Temp\\run_me.log