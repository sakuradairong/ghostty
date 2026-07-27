# Copyright (c) 2024 Mitchell Hashimoto
# SPDX-License-Identifier: MIT

<#
.SYNOPSIS
Creates a reproducible portable Ghostty archive from an installed Zig output.

.DESCRIPTION
This is deliberately a portable archive, not an installer. It does not create
Start Menu shortcuts, register an AppUserModelID, or modify the registry.

The input must be the install prefix produced by `zig build` (normally
`zig-out`). The archive contains the Windows executable, Ghostty's installed
resources, and the project license. Debug symbols and development libraries are
not runtime dependencies and are not included.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string] $ZigOut = (Join-Path $PSScriptRoot '..\..\zig-out'),

    [Parameter()]
    [string] $OutputPath,

    [Parameter()]
    [string] $Version,

    [Parameter()]
    [ValidateSet('x86_64', 'aarch64')]
    [string] $Architecture = 'x86_64'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$zigOutPath = [IO.Path]::GetFullPath($ZigOut)

if ([string]::IsNullOrWhiteSpace($Version)) {
    $zon = Get-Content -LiteralPath (Join-Path $repoRoot 'build.zig.zon') -Raw
    $match = [regex]::Match($zon, '(?m)^\s*\.version\s*=\s*"([^"]+)"')
    if (-not $match.Success) {
        throw 'Unable to read the Ghostty version from build.zig.zon. Pass -Version explicitly.'
    }
    $Version = $match.Groups[1].Value
}

if ($Version -notmatch '^[0-9A-Za-z][0-9A-Za-z._+-]*$') {
    throw "Version must contain only ASCII letters, digits, dot, underscore, plus, or hyphen: $Version"
}

$archiveRoot = "ghostty-$Version-windows-$Architecture"
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $zigOutPath "dist\$archiveRoot.zip"
}
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)

$inputs = @(
    @{ Source = Join-Path $zigOutPath 'bin\ghostty.exe'; Destination = 'bin/ghostty.exe'; Directory = $false },
    @{ Source = Join-Path $zigOutPath 'share'; Destination = 'share'; Directory = $true },
    @{ Source = Join-Path $repoRoot 'LICENSE'; Destination = 'LICENSE'; Directory = $false }
)

foreach ($input in $inputs) {
    if (-not (Test-Path -LiteralPath $input.Source)) {
        throw "Required packaging input does not exist: $($input.Source)"
    }
}

# resourcesdir.zig uses this file to discover the installed resource tree.
$terminfo = Join-Path $zigOutPath 'share\terminfo\ghostty.terminfo'
if (-not (Test-Path -LiteralPath $terminfo -PathType Leaf)) {
    throw "Required Windows resource sentinel does not exist: $terminfo"
}

$entries = [Collections.Generic.List[object]]::new()
foreach ($input in $inputs) {
    if ($input.Directory) {
        $base = [IO.Path]::GetFullPath($input.Source)
        foreach ($file in Get-ChildItem -LiteralPath $base -File -Recurse) {
            $relative = [IO.Path]::GetRelativePath($base, $file.FullName).Replace('\', '/')
            $entries.Add([pscustomobject]@{
                Source = $file.FullName
                Destination = "$($input.Destination)/$relative"
            })
        }
    } else {
        $entries.Add([pscustomobject]@{
            Source = [IO.Path]::GetFullPath($input.Source)
            Destination = $input.Destination
        })
    }
}

$entries = @($entries | Sort-Object -Property Destination -CaseSensitive)
if ($entries.Count -eq 0) {
    throw 'No files were selected for the portable archive.'
}

$outputDirectory = Split-Path -Parent $outputFullPath
[IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$temporaryPath = "$outputFullPath.tmp"
Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue

Add-Type -AssemblyName System.IO.Compression
$fixedTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)

try {
    $stream = [IO.File]::Open($temporaryPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            foreach ($item in $entries) {
                $name = "$archiveRoot/$($item.Destination)"
                $entry = $archive.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = $fixedTimestamp
                # Normalize Unix permissions while retaining a regular-file type.
                $entry.ExternalAttributes = [int32] -2119958528 # 0x81A40000

                $inputStream = [IO.File]::OpenRead($item.Source)
                try {
                    $outputStream = $entry.Open()
                    try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
                } finally {
                    $inputStream.Dispose()
                }
            }
        } finally {
            $archive.Dispose()
        }
    } finally {
        $stream.Dispose()
    }

    Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
} catch {
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    throw
}

Write-Output $outputFullPath
