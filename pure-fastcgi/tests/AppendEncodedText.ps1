param(
  [Parameter(Mandatory = $true)][string]$FilePath,
  [Parameter(Mandatory = $true)][string]$Text,
  [Parameter(Mandatory = $true)]
  [ValidateSet('ASCII', 'UTF16LE')][string]$Encoding
)

$codec = if ($Encoding -eq 'ASCII') {
  [System.Text.Encoding]::ASCII
} else {
  [System.Text.Encoding]::Unicode
}
$bytes = $codec.GetBytes($Text)
$stream = [System.IO.File]::Open(
  $FilePath,
  [System.IO.FileMode]::Append,
  [System.IO.FileAccess]::Write,
  [System.IO.FileShare]::Read)
try {
  $stream.Write($bytes, 0, $bytes.Length)
} finally {
  $stream.Dispose()
}
