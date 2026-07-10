
# individual fields
$LocationsMap = @{
fax = "Special Information"
notes = "Notes"
phone = "Front Desk Phone Number"
}
#  label Location - type AddressData
#  label Primary POC - type AssetTag
#  label Front Desk Phone Number - type Phone
#  label Office Email - type Email
#  label Hours of Operation - type Text
#  label Door Code - type Text
#  label Special Information - type Text
#  label Notes - type RichText
# ITBID - ID


# CsvRow


$huduCompanies = $huduCompanies ?? $(get-huducompanies)
# load companies index if available
$ITBoostData.organizations["matches"] = $ITBoostData.organizations["matches"] ?? $(get-content $companiesIndex -Raw | convertfrom-json -depth 99) ?? @()

if ($ITBoostData.ContainsKey("locations") -and $ITBoostData.locations.CSVData){
    if (-not $ITBoostData.locations.ContainsKey('matches')) { $ITBoostData.locations['matches'] = @() }
    $ITBoostData.locations['matches'] = @($ITBoostData.locations['matches'] ?? @())

    $LocationLayout = Get-HuduAssetLayouts | Where-Object { $_.name -ieq "location" -or $_.name -ieq "locations" } | Select-Object -First 1; $LocationLayout = $LocationLayout.asset_layout ?? $LocationLayout;

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
    if ($null -ne $AddressDataField){
        write-host "Meta-Mapping AddressData field from CSV for locations: $AddressDataField"
    }
    $groupedLocations = $ITBoostData.locations.CSVData | Group-ObjectSafeHashTable { $_.organization } -BlankKey "$internalCompanyName"
    
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
            $fields = @()
            $matchedlocation = $null
            $matchedlocation = $allHuduLocations | Where-Object {(test-equiv -A $_.name -B $companyLocation.name) -and $_.company_id -eq $matchedCompany.id} | Select-Object -First 1
            $matchedlocation = $matchedlocation ?? $(get-huduassets -AssetLayoutId $LocationLayout.id -CompanyId $matchedCompany.id -name $companyLocation.name | select-object -first 1)
            $matchedlocation = $matchedlocation.asset ?? $matchedlocation
            if ($null -ne $matchedlocation -and $false -eq $mergeOnMatch){
                Write-Host "Matched $($companyLocation.name) to $($matchedlocation.name) for $($matchedCompany.name)"
                $ITBoostData.locations["matches"]+=@{
                    CompanyName=$companyLocation.organization
                    ITBID=$companyLocation.id
                    HuduID=$matchedlocation.id
                    HuduObject=$matchedlocation
                    HuduCompanyId=$($matchedlocation.company_id ?? $matchedCompany.id)
                }
                if ($true -eq $skiponmatch){continue}
            } else {

                $NewAddressRequest=@{
                    Name=$companyLocation.name
                    CompanyID = $matchedCompany.id
                    AssetLayoutId=$LocationLayout.id
                }
                $fields = foreach ($key in $LocationsMap.Keys) {
                    # pull value from CSV row
                    $rowVal = $companyLocation.$key ?? $null
                    if ($null -eq $rowVal) { continue }
                    $rowVal = [string]$rowVal
                    if ([string]::IsNullOrWhiteSpace($rowVal)) { continue }

                    $huduField = $LocationsMap[$key]
                    [ordered]@{ $($huduField) = $rowVal.Trim() }
                }


            }
            if ($null -ne $AddressDataField){
                $newAddress=$null
                if ($companyLocation.address_1 -or $companyLocation.address_2 -or $companyLocation.city -or $companyLocation.region -or $companyLocation.postal_code -or $companyLocation.country) {
                    $NewAddress = [ordered]@{
                        address_line_1 = $companyLocation.address_1
                        city           = $companyLocation.city
                        state          = $(Normalize-Region $companyLocation.region)
                        zip            = $(Normalize-Zip $companyLocation.postal_code)
                        country_name   = $(Normalize-CountryName $companyLocation.country)
                    }
                    if (-not [string]::IsNullOrEmpty($companyLocation.address_2)) { $NewAddress['address_line_2'] = $companyLocation.address_2 }
                }
                if ($null -ne $newAddress){
                    $fields+=@{$AddressDataField = $newAddress}
                }
            }
            if ($fields.count -ge 1){
                $NewAddressRequest["Fields"]=$fields
            }            
            if ($null -ne $matchedlocation -and $matchedlocation.id -gt 0 -and $true -eq $mergeOnMatch){
                write-host "merging on match..."
                $merged = Merge-Matches -originalAsset $matchedlocation -newFields $fields -destassetlayout $LocationLayout -preferOriginal ($preferOriginal ?? $true)
                $NewAddressRequest["Fields"]=$merged.Fields
                $NewAddressRequest["id"]=$matchedlocation.id

            }
            

            try {
                $newLocation = $null
                if ($null -ne $NewAddressRequest.id){
                    $newlocation = set-huduasset @NewAddressRequest
                } else {
                    $newLocation = New-Huduasset @NewAddressRequest
                }
                $newLocation = $newLocation.asset ?? $newLocation
            } catch {
                write-host "Error $(if ($null -ne $matchedlocation) { "merging on match" } else { "creating new" }) location: $_"
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
} else {write-host "no locations in CSV! skipping."; return}
    $allHuduLocations = Get-HuduAssets -AssetLayoutId $LocationLayout.id

$ITBoostData.locations["matches"] | convertto-json -depth 99 | out-file $($(join-path $debug_folder -ChildPath "MatchedLocations.json")) -Force
