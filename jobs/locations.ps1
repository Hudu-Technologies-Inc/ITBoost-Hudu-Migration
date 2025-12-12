
# individual fields
$LocationsMap = @{
fax = "Special Information"
notes = "Notes"
phone = "Front Desk Phone Number"

}
# addressdata field for address
# Location
# Primary POC
# Front Desk Phone Number
# Office Email
# Hours of Operation
# Door Code
# Special Information
# Notes

# address_1
# address_2
# city
# country
# CsvRow
# fax
# id
# name
# notes
# organization
# password
# phone
# postal_code
# primary
# region
# resource_id
# resource_type




$huduCompanies = $huduCompanies ?? $(get-huducompanies)
# load companies index if available
$ITBoostData.organizations["matches"] = $ITBoostData.organizations["matches"] ?? $(get-content $companiesIndex -Raw | convertfrom-json -depth 99) ?? @()

if ($ITBoostData.ContainsKey("locations")){
    if (-not $ITBoostData.locations.ContainsKey('matches')) { $ITBoostData.locations['matches'] = @() }

    $LocationLayout = Get-HuduAssetLayouts | Where-Object { ($(Get-NeedlePresentInHaystack -needle "location" -haystack $_.name) -or $(Get-NeedlePresentInHaystack -needle "locations" -Haystack $_.name)) } | Select-Object -First 1

    if (-not $LocationLayout){
        $locationlayout=$(New-HuduAssetLayout -name "location" -Fields @(
            @{label= "Location"; "show_in_list"=$false; field_type="AddressData"; required=$false; hint=""; position=1},
            @{label= "Primary POC"; "show_in_list"=$false; field_type="AssetTag"; required=$false; hint=""; position=2},
            @{label= "Front Desk Phone Number"; "show_in_list"=$false; field_type="Phone"; required=$false; hint=""; position=3},
            @{label= "Office Email"; "show_in_list"=$false; field_type="Email"; required=$false; hint=""; position=4},
            @{label= "Hours of Operation"; "show_in_list"=$false; field_type="Text"; required=$false; hint=""; position=5},
            @{label= "Door Code"; "show_in_list"=$false; field_type="Text"; required=$null; hint=""; position=6},
            @{label= "Special Information"; "show_in_list"=$false; field_type="Text"; required=$false; hint=""; position=7},
            @{label= "Notes"; "show_in_list"=$false; field_type="RichText"; required=$false; hint=""; position=8}
        ) -Icon "fas fa-building" -IconColor "#ffffff" -Color "#6136ff" -IncludePasswords $true -IncludePhotos $true -IncludeComments $true -IncludeFiles $true)
        $LocationLayout = $locationlayout.asset_layout ?? $locationlayout
        $LocationLayout = Get-HuduAssetLayouts -id $LocationLayout.id
    }
    $locationLayout = $LocationLayout.asset_layout ?? $LocationLayout

    $locationfields = $LocationLayout.fields
    $AddressDataField = $($locationfields | where-object {$_.field_type -eq "AddressData"} | select-object -first 1).label ?? $null

    $groupedLocations = $ITBoostData.locations.CSVData | Group-Object { $_.organization } -AsHashTable -AsString
    `
    $allHuduLocations = Get-HuduAssets -AssetLayoutId $LocationLayout.id
    
    foreach ($company in $groupedLocations.Keys){
        

        $locationsSeen = @()
        if ([string]::IsNullOrEmpty($company)){continue}
        $locationsForCompany=$groupedLocations["$company"]
        $matchedcompany = $null
        $matchedCompany = Get-HuduCompanyFromName -CompanyName $company -HuduCompanies $huduCompanies  -existingIndex $($ITBoostData.organizations["matches"] ?? $null)
        $matchedCompany = $matchedCompany.company ?? $matchedCompany
        if ($null -eq $matchedCompany -or $null -eq $matchedcompany.id -or $matchedcompany.id -lt 1) {write-host "skipping $company due to no match"; continue;}
        # $matchedCompany=$matchedCompany ?? $($huducompanies | where-object {$_.name -eq $(Select-ObjectFromList -objects $($huduCompanies.name | sort-object) -message "Which company to match for source company, named $company")} | select-object -first 1)
        write-host "$($locationsForCompany.count) locations for $company, hudu company id: $($matchedCompany.id)"
        foreach ($companyLocation in $locationsForCompany){

            if ($locationsSeen -contains $companyLocation.name){continue} else {$locationsSeen+="$($companyLocation.name)"}
            $matchedlocation = $null
            $matchedlocation = $allHuduLocations | Where-Object {(test-equiv -A $_.name -B $companyLocation.name) -and $_.company_id -eq $matchedCompany.id} | Select-Object -First 1
            $matchedlocation = $matchedlocation ?? $(get-huduassets -AssetLayoutId $LocationLayout.id -CompanyId $matchedCompany.id -name $companyLocation.name | select-object -first 1)
            $matchedlocation = $matchedlocation.asset ?? $matchedlocation
            if ($null -ne $matchedlocation){
                Write-Host "Matched $($companyLocation.name) to $($matchedlocation.name) for $($matchedCompany.name)"
                $ITBoostData.locations["matches"]+=@{
                    CompanyName=$companyLocation.organization
                    ITBID=$companyLocation.id
                    HuduID=$matchedlocation.id
                    HuduObject=$matchedlocation
                    HuduCompanyId=$($matchedlocation.company_id ?? $matchedCompany.id)
                }
            } else {
                $NewAddressRequest=@{
                    Name=$companyLocation.name
                    CompanyID = $matchedCompany.id
                    AssetLayoutId=$LocationLayout.id
                }
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

                if ($fields.count -ge 1){
                    $NewAddressRequest["Fields"]=$fields
                }
            }
            if ($null -ne $AddressDataField){
                $newAddress=$null
                if ($row.address_1 -or $row.address_2 -or $row.city -or $row.region -or $row.postal_code -or $row.country) {
                    $NewAddress = [ordered]@{
                        address_line_1 = $row.address_1
                        city           = $row.city
                        state          = $(Normalize-Region $row.region)
                        zip            = $(Normalize-Zip $row.postal_code)
                        country_name   = $(Normalize-CountryName $row.country)
                    }
                    if (-not [string]::IsNullOrEmpty($row.address_2)) { $NewAddress['address_line_2'] = $addr2 }
                }
                if ($null -ne $newAddress){
                    $fields+=@{$AddressDataField = $newAddress}
                    $NewAddressRequest["Fields"]=$fields
                }

            }



            try {
                $newLocation = $null
                $newLocation = New-Huduasset @NewAddressRequest
                $newLocation = $newLocation.asset ?? $newLocation
            } catch {
                write-host "Error creating location: $_"
            }
            if ($newLocation){
                write-host "created location $($companyLocation.name) with ID $($newLocation.id) for company $($matchedCompany.name)"
                $ITBoostData.locations["matches"]+=@{
                    CompanyName=$companyLocation.organization
                    ITBID=$companyLocation.id
                    Name=$companyLocation.name
                    HuduID=$newLocation.id
                    HuduObject=$newLocation
                    HuduCompanyId= $($matchedCompany.id ?? $newLocation.company_id)
                }            
            }
        }
        
    }
} else {write-host "no locations in CSV! skipping."}
    $allHuduLocations = Get-HuduAssets -AssetLayoutId $LocationLayout.id

$ITBoostData.locations["matches"] | convertto-json -depth 99 | out-file $($(join-path $debug_folder -ChildPath "MatchedLocations.json")) -Force
