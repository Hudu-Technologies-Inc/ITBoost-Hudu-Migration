$configsMap = @{
model="model"
configuration_type="configuration type"
resource_type="resource type"
configuration_status="configuration status"
hostname="hostname"
ptimary_ip="primary ip"
default_gateway="default gateway"
mac_address="macAddress"
serial_number="serial number"
asset_tag="asset tag"
manufacturer="manufacturer"
operating_system="operating system"
operating_system_notes="operating system notes"
position="position"
notes="notes"
installed_at="installed at"
purchased_at="purchased at"
warranty_expires_at="warranty expires at"
contract="contact"
configuration_interfaces="configuration interfaces"
}
if ($ITBoostData.ContainsKey("configurations")){

    $huduCompanies = $huduCompanies ?? $(get-huducompanies)
    $contactsLayout = $allHuduLayouts | Where-Object { ($(Get-NeedlePresentInHaystack -needle "contact" -haystack $_.name) -or $(Get-NeedlePresentInHaystack -needle "people" -Haystack $_.name)) } | Select-Object -First 1

    $configsLayout = $allHuduLayouts | Where-Object { ($(Get-NeedlePresentInHaystack -needle "config" -haystack $_.name) -or $(Get-NeedlePresentInHaystack -needle "people" -Haystack $_.name)) } | Select-Object -First 1
    if (-not $configsLayout){
        $configsLayout=$(New-HuduAssetLayout -name "configs" -Fields @(
                    @{label = "model"; field_type = "Text"; show_in_list = $false; position=24},
                    @{label = "configuration type"; field_type = "Text"; show_in_list = $false; position=23},
                    @{label = "resource type"; field_type = "Text"; show_in_list = $false; position=22},
                    @{label = "configuration status"; field_type = "Text"; show_in_list = $false; position=21},
                    @{label = "hostname"; field_type = "Text"; show_in_list = $false; position=20},
                    @{label = "primary ip"; field_type = "Text"; show_in_list = $false; position=19},
                    @{label = "default gateway"; field_type = "Text"; show_in_list = $false; position=18},
                    @{label = "macAddress"; field_type = "Text"; show_in_list = $false; position=17},
                    @{label = "serial number"; field_type = "Text"; show_in_list = $false; position=16},
                    @{label = "asset tag"; field_type = "Text"; show_in_list = $false; position=1},
                    @{label = "manufacturer"; field_type = "Text"; show_in_list = $false; position=2},
                    @{label = "operating system"; field_type = "Text"; show_in_list = $false; position=3},
                    @{label = "operating system notes"; field_type = "Text"; show_in_list = $false; position=4},
                    @{label = "position"; field_type = "Text"; show_in_list = $false; position=5},
                    @{label = "notes"; field_type = "Text"; show_in_list = $false; position=6},
                    @{label = "installed at"; field_type = "Text"; show_in_list = $false; position=7},
                    @{label = "installed by"; field_type = "Text"; show_in_list = $false; position=8},
                    @{label = "purchased at"; field_type = "Text"; show_in_list = $false; position=9},
                    @{label = "purchased by"; field_type = "Text"; show_in_list = $false; position=10},
                    @{label = "warranty expires at"; field_type = "Text"; show_in_list = $false; position=11},
                    @{label = "contact"; field_type = "Text"; show_in_list = $false; position=12},
                    @{label = "location"; field_type = "Text"; show_in_list = $false; position=13},
                    @{label = "configuration interfaces"; field_type = "Text"; show_in_list = $false; position=14}
        ) -Icon "fas fa-users" -IconColor "#ffffff" -Color "#6136ff" -IncludePasswords $true -IncludePhotos $true -IncludeComments $true -IncludeFiles $true).asset_layout
        $configsLayout = Get-HuduAssetLayouts -id $configsLayout.id
    }
    $configsFields = $configsLayout.fields
    $uniqueCompanies = $ITBoostData.configurations.CSVData |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.organization) } | Select-Object -ExpandProperty organization -Unique
    write-host "Uniq companies $($uniqueCompanies.count)"
    foreach ($company in $uniqueCompanies) {
    Write-Host "starting $company"
    $configsForCompany = $ITBoostData.configurations.CSVData | Where-Object { $_.organization -eq $company }
    write-host "$($configsForCompany.count) configs for company"
        $matchedCompany = $huduCompanies | where-object {
            ($_.name -eq $company) -or
            [bool]$(Test-NameEquivalent -A $_.name -B "*$($company)*") -or
            [bool]$(Test-NameEquivalent -A $_.nickname -B "*$($company)*")} | Select-Object -First 1
        $matchedCompany = $huduCompanies | Where-Object {
            $_.name -eq $company -or
            (Test-NameEquivalent -A $_.name -B "*$company*") -or
            (Test-NameEquivalent -A $_.nickname -B "*$company*")
            } | Select-Object -First 1

            $matchedCompany = $matchedCompany ?? (Get-HuduCompanies -Name $company | Select-Object -First 1)

    if (-not $matchedCompany.id) {
        write-host "NO COMPANY matched for $Company"
         continue 
        } else {}

    foreach ($companyConfig in $configsForCompany) {
        # 4a) find existing
        $matchedConfig = $allHuduConfigs | Where-Object {
        $_.company_id -eq $matchedCompany.id -and (Test-NameEquivalent -A $_.name -B $companyConfig.name)
        } | Select-Object -First 1

        if (-not $matchedConfig) {
        $matchedConfig = Get-HuduAssets -AssetLayoutId $configsLayout.id -CompanyId $matchedCompany.id -Name $companyConfig.name |
                        Select-Object -First 1
        }
        if ($matchedConfig) {continue}

        # 4b) build request
        $newConfigRequest = @{
        Name          = ($companyConfig.name).Trim()
        CompanyID     = $matchedCompany.id
        AssetLayoutId = $configsLayout.id
        }
        if ($matchedConfig) { $newConfigRequest['Id'] = $matchedConfig.id }

        # 4c) fields from map (exclude location; it’s special)
        $fields = @()
        foreach ($key in $configsMap.Keys | Where-Object { $_ -notin @('location','name') }) {
        $rowVal = $companyConfig.$key
        if ([string]::IsNullOrWhiteSpace([string]$rowVal)) { continue }
        $label = $configsMap[$key]
        $fields += @{ $label = ([string]$rowVal).Trim() }
        }

        # 4d) link location (only if field exists as AssetTag)
        if (-not [string]::IsNullOrWhiteSpace($companyConfig.location)) {
        $matchedLocation = Get-HuduAssets -AssetLayoutId ($LocationLayout?.id ?? 2) -CompanyId $matchedCompany.id |
                            Where-Object { Test-NameEquivalent -A $_.name -B $companyConfig.location } |
                            Select-Object -First 1
        if ($matchedLocation) { $fields += @{ 'location' = "[$($matchedLocation.id)]" } }
        }
        if (-not [string]::IsNullOrWhiteSpace($companyConfig.purchased_by)) {
        $matchedpurchaser = Get-HuduAssets -AssetLayoutId ($contactslayout?.id ?? 2) -CompanyId $matchedCompany.id |
                            Where-Object { Test-NameEquivalent -A $_.name -B $companyConfig.purchased_by } |
                            Select-Object -First 1
        if ($matchedLocation) { $fields += @{ 'purchased by' = "[$($matchedpurchaser.id)]" } }
        }        
        if (-not [string]::IsNullOrWhiteSpace($companyConfig.installed_by)) {
        $matchedinstaller = Get-HuduAssets -AssetLayoutId ($contactslayout?.id ?? 2) -CompanyId $matchedCompany.id |
                            Where-Object { Test-NameEquivalent -A $_.name -B $companyConfig.installed_by } |
                            Select-Object -First 1
        if ($matchedLocation) { $fields += @{ 'installed by' = "[$($matchedinstaller.id)]" } }
        }                

        $newConfigRequest['Fields'] = $fields

        # 4e) create or update (INSIDE the loop)
        try {
        if ($newConfigRequest.Id) {
            write-host "updating with $($($newConfigRequest | convertto-json).ToString())"
            $null = Set-HuduAsset @newConfigRequest
        } else {
            write-host "creating with $($($newConfigRequest | convertto-json).ToString())"
            $null = New-HuduAsset @newConfigRequest
        }
        } catch {
        Write-Host "Error upserting config '$($newConfigRequest.Name)' for '$($matchedCompany.name)': $_"
        }
    }
    }
}