function ConvertTo-ITBoostOrganizationName {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $clean = ($Name.Normalize([Text.NormalizationForm]::FormC) -replace '\s+', ' ').Trim()
    return [Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($clean.ToLowerInvariant())
}

function Test-ITBoostOrganizationColumn {
    param([string]$Name)

    # Deliberately exclude IDs, organization types and organization statuses.
    return ($Name.Trim() -replace '[\s_-]', '') -iin @(
        'organization', 'organisation', 'organizationname', 'organisationname', 'company', 'companyname'
    )
}

function Get-ITBoostOrganizationCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$ITBoostData)

    if (-not $ITBoostData.ContainsKey('organizations')) {
        $ITBoostData.organizations = @{ CSVData = @(); Matches = @(); CsvFiles = @() }
    }
    $catalog = [hashtable]::new([StringComparer]::OrdinalIgnoreCase)

    function Add-OrganizationName {
        param([string]$Name, [object]$OrganizationRow, [string]$SourceFile, [switch]$Reference)

        $normalized = ConvertTo-ITBoostOrganizationName -Name $Name
        if ([string]::IsNullOrWhiteSpace($normalized)) { return '' }
        if (-not $catalog.ContainsKey($normalized)) {
            $catalog[$normalized] = [pscustomobject]@{
                Name = $normalized
                Aliases = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                SourceFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                OrganizationRows = [Collections.Generic.List[object]]::new()
                ReferenceCount = 0
            }
        }
        $candidate = $catalog[$normalized]
        [void]$candidate.Aliases.Add($Name)
        if ($SourceFile) { [void]$candidate.SourceFiles.Add($SourceFile) }
        if ($null -ne $OrganizationRow) { $candidate.OrganizationRows.Add($OrganizationRow) }
        if ($Reference) { $candidate.ReferenceCount++ }
        return $normalized
    }

    # Retain every exported organization row, ID and metadata field, even when several names collapse to one company.
    foreach ($organizationRow in $ITBoostData.organizations.CSVData) {
        $organizationRow.name = Add-OrganizationName -Name $organizationRow.name -OrganizationRow $organizationRow -SourceFile ($organizationRow.SourceFile ?? 'organizations')
    }

    foreach ($key in @($ITBoostData.Keys | Sort-Object)) {
        $dataset = $ITBoostData[$key]
        if ($dataset -isnot [hashtable] -or -not $dataset.ContainsKey('CSVData')) { continue }
        $columnsByFile = @{}
        foreach ($csvFile in $dataset.CsvFiles) {
            $columnsByFile[$csvFile.Path] = @($csvFile.Headers | Where-Object {
                Test-ITBoostOrganizationColumn -Name $_.OriginalName
            } | Select-Object -ExpandProperty Name)
        }
        foreach ($csvRow in $dataset.CSVData) {
            $columns = if ($csvRow.SourceFile -and $columnsByFile.ContainsKey($csvRow.SourceFile)) {
                $columnsByFile[$csvRow.SourceFile]
            } else {
                @($csvRow.PSObject.Properties.Name | Where-Object { Test-ITBoostOrganizationColumn -Name $_ })
            }
            $primaryOrganization = ''
            foreach ($column in $columns) {
                $normalized = Add-OrganizationName -Name $csvRow.$column -SourceFile ($csvRow.SourceFile ?? $key) -Reference
                $csvRow.$column = $normalized
                if ($normalized -and (-not $primaryOrganization -or $column -ieq 'organization')) {
                    $primaryOrganization = $normalized
                }
            }
            # Subsystems such as Activity export CompanyName; expose the same ownership field used by later jobs.
            if ($primaryOrganization) {
                if (-not $csvRow.PSObject.Properties['organization']) {
                    $csvRow | Add-Member -NotePropertyName organization -NotePropertyValue $primaryOrganization
                } elseif ([string]::IsNullOrWhiteSpace($csvRow.organization)) {
                    $csvRow.organization = $primaryOrganization
                }
            }
        }
    }

    $ITBoostData.organizations.CompanyCandidates = @($catalog.Values | Sort-Object Name)
    return $ITBoostData.organizations.CompanyCandidates
}

function Get-ITBoostOrganizationSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Catalog)

    foreach ($candidate in $Catalog) {
        [pscustomobject]@{
            Name = $candidate.Name
            Aliases = @($candidate.Aliases | Sort-Object -CaseSensitive)
            SourceFiles = @($candidate.SourceFiles | Sort-Object)
            OrganizationIds = @($candidate.OrganizationRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.id) } | Select-Object -ExpandProperty id)
            HasOrganizationRecord = $candidate.OrganizationRows.Count -gt 0
            ReferenceCount = $candidate.ReferenceCount
        }
    }
}
