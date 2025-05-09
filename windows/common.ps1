function Get-Base64GzipString {
    param([string]$input)
    return [IO.StreamReader]::new(
      [IO.Compression.GzipStream]::new(
        [IO.MemoryStream]::new([Convert]::FromBase64String($input)),
        [IO.Compression.CompressionMode]::Decompress
      )
    ).ReadToEnd()
}