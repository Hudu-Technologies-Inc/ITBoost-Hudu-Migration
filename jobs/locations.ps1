$LocationsMap = @{
address_1="Address 1"
address_2="Address 2"
city="City"
postal_code="Postal Code"
region = "Region"
country = "Country"
notes = "Notes"
phone = "Phone"
fax = "Fax"

}
if ($ITBoostData.ContainsKey("locations")){

    $LocationLayout = $allHuduLayouts | Where-Object { ($(Get-NeedlePresentInHaystack -needle "location" -haystack $_.name) -or $(Get-NeedlePresentInHaystack -needle "branch" -Haystack $_.name)) } | Select-Object -First 1

    if (-not $LocationLayout){
        $locationlayout=$(New-HuduAssetLayout -name "location" -Fields @(
            @{label        = 'Address 1'; field_type   = 'Text'; show_in_list = 'true'; position     = 1},
            @{label        = 'Address 2'; field_type   = 'Text'; show_in_list = 'false'; position     = 2},
            @{label        = 'City'; field_type   = 'Text'; show_in_list = 'true'; position     = 3},
            @{label        = 'Postal Code'; field_type   = 'Text'; show_in_list = 'true'; position     = 4},
            @{label        = 'Region'; field_type   = 'Text'; show_in_list = 'false'; position     = 5},
            @{label        = 'Country'; field_type   = 'Text'; show_in_list = 'false'; position     = 6},
            @{label        = 'Phone'; field_type   = 'Text'; show_in_list = 'false'; position     = 7},
            @{label        = 'Fax'; field_type   = 'Text'; show_in_list = 'false'; position     = 8},
            @{label        = 'Notes'; field_type   = 'RichText'; show_in_list = 'false'; position     = 9}
        ) -Icon "fas fa-building" -IconColor "#ffffff" -Color "#6136ff" -IncludePasswords $true -IncludePhotos $true -IncludeComments $true -IncludeFiles $true).asset_layout
        $LocationLayout = Get-HuduAssetLayouts -id $LocationLayout.id
    }

    $locationfields = $LocationLayout.fields
    $AddressDataField = $($locationfields | where-object {$_.field_type -eq "AddressData"} | select-object -first 1).label ?? $null

    $groupedLocations = $ITBoostData.locations.CSVData | Group-Object { $_.organization } -AsHashTable -AsString
    
    $allHuduLocations = Get-HuduAssets -AssetLayoutId $LocationLayout.id
    
    foreach ($company in $groupedLocations.Keys){
        $locationsSeen = @()
        $locationsForCompany=$groupedLocations["$company"]
        $matchedCompany = $huduCompanies | where-object {($_.name -eq $row.organization) -or [bool]$(Test-NameEquivalent -A $_.name -B $company)} | Select-Object -First 1
        if (-not $matchedCompany) {$matchedCompany = $(New-HuduCompany -name "$($row.organization)" -AddressLine1 "$($row.address_1)" -AddressLine2 "$($row.address_2)" -city "$($row.city)" -State "$($row.region)" -Zip "$($row.postal_code)" -CountryName "$($row.country)" -Notes $("$($row.notes)") -replace "[]","imported from ITBoost").company}
        # $matchedCompany=$matchedCompany ?? $($huducompanies | where-object {$_.name -eq $(Select-ObjectFromList -objects $($huduCompanies.name | sort-object) -message "Which company to match for source company, named $company")} | select-object -first 1)
        write-host "$($locationsForCompany.count) locations for $company, hudu company id: $($matchedCompany.id)"
        foreach ($companyLocation in $locationsForCompany){
            if ($locationsSeen -contains $companyLocation.name){continue} else {$locationsSeen+="$($companyLocation.name)"}

            $matchedlocation = $allHuduLocations | where-object {$_.company_id -eq $matchedCompany.id -and 
                $($(Test-NameEquivalent -A $_.name -B $companyLocation.name) -or
                 $(Test-NameEquivalent -A $companyLocation.address_1 -B $($_.fields | where-object {$_.label -ilike "address"} | select-object -first 1).value))} | select-object -first 1
            if ($matchedLocation){
                Write-Host "Matched $($companyLocation.name) to $($matchedlocation.name) for $($matchedCompany.name)"
                $ITBoostData.locations["matches"]+=@{
                    CompanyName=$companyLocation.organization
                    CsvRow=$companyLocation.CsvRow
                    ITBID=$companyLocation.id
                    HuduID=$MatchedWebsite.id
                    HuduObject=$MatchedWebsite
                    HuduCompanyId=$MatchedWebsite.company_id
                    PasswordsToCreate=$($companyLocation.password ?? @())
                }
            } else {
                $NewAddressRequest=@{
                    Name=$companyLocation.name
                    CompanyID = $matchedCompany.id
                    AssetLayoutId=$LocationLayout.id
                }
                if ($false -eq $UseSimpleMap){
                    $NewAddressRequest["Fields"]=Build-FieldsFromRow -row $companyLocation -layoutFields $locationfields  -companyId $matchedCompany.id
                } else {
                    $fields = @()
                    $fields = foreach ($key in $LocationsMap.Keys) {
                    # pull value from CSV row
                    $rowVal = $row.$key ?? $null
                    if ($null -eq $rowVal) { continue }
                    $rowVal = [string]$rowVal
                    if ([string]::IsNullOrWhiteSpace($rowVal)) { continue }

                    $huduField = $LocationsMap[$key]
                    [ordered]@{ $($huduField) = $rowVal.Trim() }
                    }

                    $NewAddressRequest["Fields"]=$fields
                }


                try {
                    $newLocation = New-Huduasset @NewAddressRequest
                } catch {
                    write-host "Error creating location: $_"
                }
                if ($newLocation){
                    $ITBoostData.locations["matches"]+=@{
                        CompanyName=$companyLocation.organization
                        CsvRow=$companyLocation.CsvRow
                        ITBID=$companyLocation.id
                        Name=$companyLocation.name
                        HuduID=$newLocation.id
                        HuduObject=$newLocation
                        HuduCompanyId=$newLocation.company_id
                        PasswordsToCreate=$($companyLocation.password ?? @())
                    }            
                }
            }
        }
    }
} else {write-host "no locations in CSV! skipping."}
    $allHuduLocations = Get-HuduAssets -AssetLayoutId $LocationLayout.id
