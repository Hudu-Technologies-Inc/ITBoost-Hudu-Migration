function Get-EnsuredPath {
    [CmdletBinding()]
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path (Split-Path -Parent $PSScriptRoot) 'debug'
    }

    # Resolve relative paths using PowerShell's location and treat wildcard characters literally.
    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    try {
        [IO.Directory]::CreateDirectory($fullPath) | Out-Null
    } catch {
        throw "Cannot create migration directory '$fullPath': $($_.Exception.Message)"
    }
    return $fullPath
}

function Initialize-MigrationOutputDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = Get-EnsuredPath -Path $Path
    $probePath = Join-Path $fullPath ".migration-writecheck-$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $probe = [IO.File]::Open($probePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $probe.Dispose()
        Remove-Item -LiteralPath $probePath -Force -ErrorAction Stop
    } catch {
        throw "Migration directory '$fullPath' is not writable: $($_.Exception.Message)"
    } finally {
        if ([IO.File]::Exists($probePath)) {
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        }
    }
    return $fullPath
}

function Export-MigrationJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object]$InputObject,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$LiteralPath,
        [ValidateRange(1, 100)][int]$Depth = 99
    )

    $fullPath = $LiteralPath
    $tempPath = $null
    try {
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LiteralPath)
        # Serialize before touching the destination; refuse silently truncated JSON.
        $json = ConvertTo-Json -InputObject $InputObject -Depth $Depth -ErrorAction Stop -WarningAction Stop
        $directory = Get-EnsuredPath -Path ([IO.Path]::GetDirectoryName($fullPath))
        $tempPath = Join-Path $directory ".migration-$([guid]::NewGuid().ToString('N')).tmp"
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json + [Environment]::NewLine)
        $stream = [IO.File]::Open($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally {
            $stream.Dispose()
        }

        # Stage beside the destination so the final replacement stays on the same filesystem.
        # Never delete the old index first: a failed write must leave it intact.
        if ([IO.File]::Exists($fullPath)) {
            [IO.File]::Replace($tempPath, $fullPath, [NullString]::Value)
        } else {
            [IO.File]::Move($tempPath, $fullPath)
        }
        Write-Verbose "Saved migration JSON: $fullPath"
    } catch {
        throw "Could not save migration JSON to '$fullPath': $($_.Exception.Message)"
    } finally {
        if ($tempPath -and [IO.File]::Exists($tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}
