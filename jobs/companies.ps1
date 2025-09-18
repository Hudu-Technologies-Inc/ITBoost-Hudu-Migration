if ($ITBoostData.ContainsKey("organizations")){
    foreach ($row in $ITBoostData.organizations.CSVData){
        $matchedCompany = $huduCompanies | where-object {
            ($_.name -eq $row.name) -or
            [bool]$(Test-NameEquivalent -A $_.name -B "*$($row.name)*") -or
            [bool]$(Test-NameEquivalent -A $_.nickname -B "*$($row.short_name)*")} | Select-Object -First 1
        if ($matchedCompany){
            Write-Host "Matched company $($matchedCompany.name) to $($row.name)"
            $ITBoostData.organizations["matches"]+=@{
                CompanyName=$row.name
                HuduCompany=$matchedCompany
                CsvRow=$row.CsvRow
                ITBID=$row.id
                HuduID=$matchedCompany.id
                PasswordsToCreate=$($row.password ?? @())
            }
        } else {
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
                $newCompany=New-HuduCompany @newCompanyRequest
                if ($newCompany){
                    $ITBoostData.organizations["matches"]+=@{
                        CsvRow=-1
                        ITBID=$row.id
                        HuduID=$newCompany.id
                        CompanyName=$row.name
                        HuduCompany=$newCompany
                        PasswordsToCreate=$($row.password ?? @())
                    }
                }
            } catch {
                Write-Host "Error during company create $_"
            }
        }
    }
} else {write-host "No organizations data found, cannot proceed."; exit 1}
Write-Host "Created $($($ITBoostdata.organizations.matches | where-object {$_.CsvRow -gt 0}).count) and matched $($($ITBoostdata.organizations.matches | where-object {$_.CsvRow -lt 0}).count) companies"
$huduCompanies = Get-HuduCompanies