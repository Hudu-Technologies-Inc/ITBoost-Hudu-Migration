$huduCompanies = @(Get-HuduCompanies -ErrorAction Stop)
if (-not $ITBoostData.organizations.CompanyCandidates) {
    $null = Get-ITBoostOrganizationCatalog -ITBoostData $ITBoostData
}
$ITBoostData.organizations.matches = @()
$companyFieldMap = @{
    organization_type = 'CompanyType'; address_1 = 'AddressLine1'; address_2 = 'AddressLine2'
    city = 'City'; state = 'State'; zip = 'Zip'; country = 'Country'
}

try {
    foreach ($candidate in $ITBoostData.organizations.CompanyCandidates) {
        $organizationRows = @($candidate.OrganizationRows.ToArray())
        $eligibleRows = @($organizationRows | Where-Object { $_.organization_status -ine 'Inactive' })
        if ($SkipInactive -and $organizationRows.Count -gt 0 -and $eligibleRows.Count -eq 0) {
            Write-Host "Skipping explicitly inactive organization $($candidate.Name)"
            continue
        }

        $matchedCompany = Get-HuduCompanyFromName -CompanyName $candidate.Name -HuduCompanies $huduCompanies -ExactNameOnly
        $matchedCompany = $matchedCompany.company ?? $matchedCompany
        if ($null -eq $matchedCompany) {
            $newCompanyRequest = @{ Name = $candidate.Name }
            # Prefer metadata from active records, then fill missing fields from other exported organization rows.
            $metadataRows = $eligibleRows + @($organizationRows | Where-Object { $_.organization_status -ieq 'Inactive' })
            foreach ($field in $companyFieldMap.Keys) {
                $value = $metadataRows | ForEach-Object { $_.$field } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
                if ($null -ne $value) { $newCompanyRequest[$companyFieldMap[$field]] = $value }
            }
            Write-Host "No match for company $($candidate.Name), creating now"
            try {
                $matchedCompany = New-HuduCompany @newCompanyRequest -ErrorAction Stop
                $matchedCompany = $matchedCompany.company ?? $matchedCompany
                if ($null -eq $matchedCompany -or $matchedCompany.id -le 0) { throw 'Hudu did not return a valid company ID.' }
            } catch {
                throw "Cannot ensure organization '$($candidate.Name)' exists in Hudu: $($_.Exception.Message)"
            }
            $huduCompanies += $matchedCompany
            Write-Host "Created company $($matchedCompany.name) with ID $($matchedCompany.id)"
        } else {
            Write-Host "Matched company $($matchedCompany.name) to $($candidate.Name)"
        }

        # Keep each original ITBoost ID linked to the same company when source rows deduplicate by name.
        $sourceIds = @($organizationRows | ForEach-Object { $_.id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        if ($sourceIds.Count -eq 0) { $sourceIds = @($null) }
        foreach ($sourceId in $sourceIds) {
            $ITBoostData.organizations.matches += @{
                CompanyName = $candidate.Name
                Aliases = @($candidate.Aliases)
                ITBID = $sourceId
                HuduID = $matchedCompany.id
                HuduCompany = $matchedCompany
            }
        }
    }
} finally {
    # Save successful matches even if a later company fails; the job runner then stops dependent jobs.
    Export-MigrationJson -InputObject @($ITBoostData.organizations.matches) -LiteralPath $companiesIndex
}
