function Get-Base64GzipString {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Base64Payload
    )
    return [IO.StreamReader]::new(
      [IO.Compression.GzipStream]::new(
        [IO.MemoryStream]::new([Convert]::FromBase64String($Base64Payload)),
        [IO.Compression.CompressionMode]::Decompress
      )
    ).ReadToEnd()
}