function Import-ITBoostCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [ref]$HeaderMap
    )

    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LiteralPath)
    $parser = $null
    $recordNumber = 0
    try {
        $parser = [Microsoft.VisualBasic.FileIO.TextFieldParser]::new($fullPath, [Text.UTF8Encoding]::new($false, $true), $true)
        $parser.SetDelimiters(',')
        $parser.HasFieldsEnclosedInQuotes = $true
        $parser.TrimWhiteSpace = $false
        if ($parser.EndOfData) {
            if ($HeaderMap) { $HeaderMap.Value = @() }
            return
        }

        $headers = $parser.ReadFields()
        $reservedNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $usedNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        # These fields describe the imported row; source columns with these names are retained under suffixes.
        foreach ($name in @('CsvRow', 'SourceFile')) { [void]$usedNames.Add($name) }
        foreach ($header in $headers) {
            if (-not [string]::IsNullOrWhiteSpace($header)) { [void]$reservedNames.Add($header.Trim()) }
        }
        $mapping = for ($column = 0; $column -lt $headers.Length; $column++) {
            $originalName = $headers[$column]
            $baseName = $originalName.Trim()
            if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = "Column$($column + 1)" }
            $name = $baseName
            $suffix = 2
            # Reserve original names up front: a renamed duplicate must not steal an existing password_2 column.
            while ($usedNames.Contains($name) -or
                   ($name -ne $originalName.Trim() -and $reservedNames.Contains($name))) {
                $name = "${baseName}_$suffix"
                $suffix++
            }
            [void]$usedNames.Add($name)
            [pscustomobject]@{ Column = $column + 1; OriginalName = $originalName; Name = $name }
        }
        if ($HeaderMap) { $HeaderMap.Value = @($mapping) }
        $renamed = @($mapping | Where-Object { $_.OriginalName -cne $_.Name })
        if ($renamed.Count -gt 0) {
            $changes = ($renamed | ForEach-Object { "column $($_.Column): '$($_.OriginalName)' -> '$($_.Name)'" }) -join '; '
            Write-Warning "Adjusted CSV headers in '$fullPath': $changes"
        }

        $parser.Dispose()
        $parser = $null
        # Keep PowerShell's CSV parsing behavior for ITBoost's occasionally nonstandard quoted HTML.
        # Supplying unique headers avoids Import-Csv's duplicate-member error; skip the original logical header row.
        Import-Csv -LiteralPath $fullPath -Header @($mapping.Name) -Encoding utf8 -ErrorAction Stop |
            Select-Object -Skip 1 | ForEach-Object {
            $recordNumber++
            $sourceRow = $_
            $row = [ordered]@{ CsvRow = $recordNumber; SourceFile = $fullPath }
            for ($column = 0; $column -lt $headers.Length; $column++) {
                $name = $mapping[$column].Name
                $row[$name] = $sourceRow.$name
            }
            [pscustomobject]$row
        }
    } catch {
        throw "Cannot import CSV '$fullPath' near data record $recordNumber`: $($_.Exception.Message)"
    } finally {
        if ($parser) { $parser.Dispose() }
    }
}

function Get-ITBoostCsvFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ExportPath)

    # Walk all entity folders, but do not interpret attached documents or converted runbooks as entity exports.
    $pending = [Collections.Generic.Queue[string]]::new()
    $pending.Enqueue((Get-Item -LiteralPath $ExportPath -ErrorAction Stop).FullName)
    while ($pending.Count -gt 0) {
        $directory = $pending.Dequeue()
        foreach ($item in Get-ChildItem -LiteralPath $directory -ErrorAction Stop | Sort-Object Name) {
            if ($item.PSIsContainer) {
                if ($item.Name -notin @('attachments', 'documents', 'RB') -and
                    -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    $pending.Enqueue($item.FullName)
                }
            } elseif ($item.Extension -ieq '.csv') {
                $item
            }
        }
    }
}
