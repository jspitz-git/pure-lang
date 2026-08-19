param(
  [Parameter(Mandatory=$true)][string]$Stage,
  [Parameter(Mandatory=$true)][string]$SourcePrefix,
  [Parameter(Mandatory=$true)][string]$BuildPrefix,
  [Parameter(Mandatory=$true)][string]$StagePrefix
)

$ErrorActionPreference = 'Stop'
function Stop-Scan([string]$Kind, [string]$Path) {
  [Console]::Error.WriteLine(('{0}|{1}' -f $Kind, $Path))
  exit 73
}

$byteEncoding = [Text.Encoding]::GetEncoding(28591)
$rawPatterns = [Collections.Generic.List[Text.RegularExpressions.Regex]]::new()
$rawNames = [Collections.Generic.List[string]]::new()
$rawKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$textPatterns = [Collections.Generic.HashSet[string]]::new(
  [StringComparer]::Ordinal)
foreach ($prefix in @($SourcePrefix, $BuildPrefix, $StagePrefix)) {
  if ([String]::IsNullOrWhiteSpace($prefix)) { continue }
  foreach ($variant in @($prefix, $prefix.Replace('/', '\'),
      $prefix.Replace('\', '/'))) {
    [void]$textPatterns.Add($variant)
    foreach ($encoding in @([Text.Encoding]::UTF8, [Text.Encoding]::Unicode)) {
      $bytes = $encoding.GetBytes($variant)
      $key = [Convert]::ToBase64String($bytes)
      if (-not $rawKeys.Add($key)) { continue }
      $expression = [Text.StringBuilder]::new()
      for ($index = 0; $index -lt $bytes.Length; ++$index) {
        $value = $bytes[$index]
        $asciiLetter = (($value -ge 65 -and $value -le 90) -or
          ($value -ge 97 -and $value -le 122))
        if ($encoding.CodePage -eq [Text.Encoding]::Unicode.CodePage) {
          $asciiLetter = $asciiLetter -and (($index % 2) -eq 0) -and
            (($index + 1) -lt $bytes.Length) -and ($bytes[$index + 1] -eq 0)
        }
        if ($asciiLetter) {
          $lower = $value
          if ($lower -le 90) { $lower += 32 }
          [void]$expression.Append(('[{0}{1}]' -f
            [char]($lower - 32), [char]$lower))
        } else {
          [void]$expression.Append(('\x{0:X2}' -f $value))
        }
      }
      $options = [Text.RegularExpressions.RegexOptions]::Compiled -bor
        [Text.RegularExpressions.RegexOptions]::CultureInvariant
      $rawPatterns.Add([Text.RegularExpressions.Regex]::new(
        $expression.ToString(), $options))
      $rawNames.Add($variant)
    }
  }
}

$utf8 = [Text.UTF8Encoding]::new($false, $true)
$utf16 = [Text.UnicodeEncoding]::new($false, $true, $true)
$pending = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
$pending.Push([IO.DirectoryInfo](Get-Item -LiteralPath $Stage -Force))
while ($pending.Count -gt 0) {
  $directory = $pending.Pop()
  foreach ($entry in $directory.EnumerateFileSystemInfos()) {
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      Stop-Scan 'REPARSE' $entry.FullName
    }
    if (($entry.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
      $pending.Push([IO.DirectoryInfo]$entry)
      continue
    }
    $bytes = [IO.File]::ReadAllBytes($entry.FullName)
    $raw = $byteEncoding.GetString($bytes)
    for ($index = 0; $index -lt $rawPatterns.Count; ++$index) {
      if ($rawPatterns[$index].IsMatch($raw)) {
        Stop-Scan ('PREFIX:' + $rawNames[$index]) $entry.FullName
      }
    }
    foreach ($encoding in @($utf8, $utf16)) {
      try { $text = $encoding.GetString($bytes) } catch { continue }
      foreach ($pattern in $textPatterns) {
        if ($text.IndexOf($pattern,
            [StringComparison]::OrdinalIgnoreCase) -ge 0) {
          Stop-Scan ('PREFIX_UNICODE:' + $pattern) $entry.FullName
        }
      }
    }
  }
}
