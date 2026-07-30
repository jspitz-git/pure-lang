param(
    [Parameter(Mandatory = $true)]
    [string] $Root
)

$ErrorActionPreference = 'Stop'
$rootPath = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
$rootInfo = [System.IO.DirectoryInfo]::new($rootPath)
if (($rootInfo.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Octave root identity rejects reparse-point root: $rootPath"
}

$pending = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
$files = New-Object 'System.Collections.Generic.List[string]'
$pending.Push($rootInfo)

while ($pending.Count -gt 0) {
    $directory = $pending.Pop()
    foreach ($entry in $directory.EnumerateFileSystemInfos()) {
        if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Octave root identity rejects reparse point: $($entry.FullName)"
        }
        if (($entry.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
            $pending.Push([System.IO.DirectoryInfo] $entry)
            continue
        }

        $relativePath = $entry.FullName.Substring($rootPath.Length).
            TrimStart('\').Replace('\', '/')
        if ($relativePath -cne 'pure-octave.fingerprint') {
            $files.Add($entry.FullName)
        }
    }
}

$paths = $files.ToArray()
[Array]::Sort($paths, [System.StringComparer]::Ordinal)
$aggregate = [System.Security.Cryptography.SHA256]::Create()
try {
    foreach ($filePath in $paths) {
        $fileHasher = [System.Security.Cryptography.SHA256]::Create()
        $stream = [System.IO.File]::OpenRead($filePath)
        try {
            $fileHash = $fileHasher.ComputeHash($stream)
        }
        finally {
            $stream.Dispose()
            $fileHasher.Dispose()
        }

        $hexHash = ([System.BitConverter]::ToString($fileHash)).Replace('-', '')
        $relativePath = $filePath.Substring($rootPath.Length).
            TrimStart('\').Replace('\', '/')
        $record = [System.Text.Encoding]::UTF8.GetBytes(
            $hexHash + '  ' + $relativePath + "`n")
        [void] $aggregate.TransformBlock(
            $record, 0, $record.Length, $record, 0)
    }
    [void] $aggregate.TransformFinalBlock([byte[]]::new(0), 0, 0)
    $identity = ([System.BitConverter]::ToString($aggregate.Hash)).
        Replace('-', '')
}
finally {
    $aggregate.Dispose()
}

Write-Output $identity
