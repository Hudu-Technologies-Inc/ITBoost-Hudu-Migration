$huducompanies = $huduCompanies ?? $(get-huducompanies)
if ($ITBoostData.ContainsKey("organizations")){
    if (-not $ITBoostData.organizations.ContainsKey('matches')) { $ITBoostData.organizations['matches'] = @() }

    foreach ($row in $ITBoostData.organizations.CSVData){
        $matchedCompany=$null
        $matchedCompany = Get-HuduCompanyFromName -CompanyName $row.name -HuduCompanies $huduCompanies  -existingIndex $($ITBoostData.organizations["matches"] ?? $null)
        if ($matchedCompany){
            Write-Host "Matched company $($matchedCompany.name) to $($row.name)"
            $ITBoostData.organizations["matches"]+=@{
                CompanyName=$row.name
                HuduCompany=$matchedCompany
                ITBID=$row.id
                HuduID=$matchedCompany.id
            }
            if ($row.organization_status -ieq "Inactive") {
                if ($true -eq $SkipInactive){continue}

                Write-Host "Setting company $($matchedCompany.name) to Inactive"
                Set-HuduCompanyArchive -id $matchedCompany.id -Archive $true -Confirm:$false
            } 
            continue
        } else {
            if ($row.organization_status -ieq "Inactive") {
                if ($true -eq $SkipInactive){continue}
            }
            $newCompanyRequest = @{
                Name=$row.name
            }
            Write-Host "No match for company $($newCompanyRequest.name), creating now"
            if (-not [string]::IsNullOrEmpty($row.organization_type)){$newCompanyRequest["CompanyType"] = $row.organization_type}
            if (-not [string]::IsNullOrEmpty($row.address_1)){$newCompanyRequest["AddressLine1"] = $row.address_1}
            if (-not [string]::IsNullOrEmpty($row.address_2)){$newCompanyRequest["AddressLine2"] = $row.address_2}
            if (-not [string]::IsNullOrEmpty($row.city)){$newCompanyRequest["City"] = $row.city}
            if (-not [string]::IsNullOrEmpty($row.state)){$newCompanyRequest["State"] = $row.address_2}
            if (-not [string]::IsNullOrEmpty($row.zip)){$newCompanyRequest["Zip"] = $row.zip}
            if (-not [string]::IsNullOrEmpty($row.country)){$newCompanyRequest["Country"] = $row.country}
            try {
                $newCompany = $null
                $newCompany=New-HuduCompany @newCompanyRequest
                $newCompany = $newCompany.company ?? $newCompany
                write-host "Created new company $($newCompany.name) with ID $($newCompany.id)"
                if ($newCompany){
                    $ITBoostData.organizations["matches"]+=@{
                        ITBID=$row.id
                        HuduID=$newCompany.id
                        CompanyName=$row.name
                        HuduCompany=$newCompany
                    }
                }
            } catch {
                Write-Host "Error during company create $_"
            }
        }
    }
} else {write-host "No organizations data found, cannot proceed."; exit 1}
$huduCompanies = Get-HuduCompanies
$ITBoostData.organizations["matches"] | convertto-json -depth 99 | out-file $companiesIndex -Force
