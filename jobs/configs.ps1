$configsMap = @{
    model                 = "model"
    configuration_type    = "configuration type"
    resource_type         = "resource type"
    configuration_status  = "configuration status"
    hostname              = "hostname"
    primary_ip            = "primary ip"
    default_gateway       = "default gateway"
    mac_address           = "macAddress"
    serial_number         = "serial number"
    asset_tag             = "asset tag"
    manufacturer          = "manufacturer"
    operating_system      = "operating system"
    operating_system_notes= "operating system notes"
    position              = "position"
    notes                 = "notes"
    installed_at          = "installed at"
    purchased_at          = "purchased at"
    warranty_expires_at   = "warranty expires at"
    contact              = "contact"
    configuration_interfaces = "configuration interfaces"
}

$ConfigurationsHaveBeenApplied=$false

# load companies index if available
$ITBoostData.organizations["matches"] = $ITBoostData.organizations["matches"] ?? $(get-content $companiesIndex -Raw | convertfrom-json -depth 99) ?? @()

if ($ITBoostData.ContainsKey("configurations")){
    if (-not $ITBoostData.configurations.ContainsKey('matches')) { $ITBoostData.configurations['matches'] = @() }
    $huduCompanies = $huduCompanies ?? $(get-huducompanies)

    $configsLayout = $allHuduLayouts | Where-Object { ($(Get-NeedlePresentInHaystack -needle "config" -haystack $_.name) -or $($_.name -ilike "config*")) } | Select-Object -First 1; $configsLayout = $configsLayout.asset_layout ?? $configsLayout
    write-host "Configs layout id $($configsLayout.id)"
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
        $configsLayout = Get-HuduAssetLayouts -id $configsLayout.id; $configsLayout = $configsLayout.asset_layout ?? $configsLayout
    }
    $configsFields = $configsLayout.fields
$allHuduConfigs = Get-HuduAssets -AssetLayoutId $configsLayout.id

$uniqueCompanies = $ITBoostData.configurations.CSVData |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_.organization) } |
    Select-Object -ExpandProperty organization -Unique

foreach ($company in $uniqueCompanies) {

    $matchedCompany = Get-HuduCompanyFromName -CompanyName $company -HuduCompanies $huduCompanies -existingIndex ($ITBoostData.organizations["matches"] ?? $null)

    if (-not $matchedCompany -or -not $matchedCompany.id) {
        Write-Host "NO COMPANY matched for $company"
        continue
    } else {
        Write-Host "Processing configs for company $($matchedCompany.name)"
    }
    $configsForCompany = $ITBoostData.configurations.CSVData |
        Where-Object { $_.organization -eq $company }
    $configsForCompany =
        $configsForCompany |
        Group-Object { $_.name.Trim().ToLowerInvariant() } |
        ForEach-Object { $_.Group[0] }
    foreach ($companyConfig in $configsForCompany) {

        # Find existing config
        $matchedConfig = $null
        $matchedConfig = get-huduassets -AssetLayoutId $configsLayout.id -CompanyId $matchedCompany.id |
            Where-Object {
                (test-equiv -A $_.name -B $companyConfig.name)
            } |
            Select-Object -First 1

        $newConfigRequest = @{
            Name          = ($companyConfig.name).Trim()
            CompanyID     = $matchedCompany.id
            AssetLayoutId = $configsLayout.id
        }

        if ($null -ne $matchedConfig) {
                    $ITBoostData.configurations['matches'] += @{
                        CompanyName      = $companyConfig.organization
                        CsvRow           = $companyConfig.CsvRow
                        ITBID            = $companyConfig.id
                        Name             = $(($companyConfig.name).Trim())
                        HuduID           = $matchedConfig.id
                        HuduObject       = $matchedConfig
                        HuduCompanyId    = $matchedConfig.company_id
                    }
                    continue
        }

        # Build fields from map (excluding location/name)
        $fields = @()     # <– MUST be an array

        foreach ($key in $configsMap.Keys | Where-Object { $_ -notin @('location','name') }) {
            $rowVal = $companyConfig.$key
            if ([string]::IsNullOrWhiteSpace([string]$rowVal)) { continue }
            $label = $configsMap[$key]
            $fields += @{ $label = ([string]$rowVal).Trim() }
        }
        # Location
        if (-not [string]::IsNullOrWhiteSpace($companyConfig.location)) {
            $matchedLocation = Get-HuduAssets -AssetLayoutId ($LocationLayout?.id ?? 2) -CompanyId $matchedCompany.id |
                               Where-Object { test-equiv -A $_.name -B $companyConfig.location } |
                               Select-Object -First 1
            if ($matchedLocation) { $fields += @{ 'location' = "[$($matchedLocation.id)]" } }
        }

        # Purchased by
        if (-not [string]::IsNullOrWhiteSpace($companyConfig.purchased_by)) {
            $matchedPurchaser = Get-HuduAssets -AssetLayoutId ($contactslayout?.id ?? 2) -CompanyId $matchedCompany.id |
                                Where-Object { test-equiv -A $_.name -B $companyConfig.purchased_by } |
                                Select-Object -First 1
            if ($matchedPurchaser) { $fields += @{ 'purchased by' = "[$($matchedPurchaser.id)]" } }
        }

        # Installed by
        if (-not [string]::IsNullOrWhiteSpace($companyConfig.installed_by)) {
            $matchedInstaller = Get-HuduAssets -AssetLayoutId ($contactslayout?.id ?? 2) -CompanyId $matchedCompany.id |
                                Where-Object { test-equiv -A $_.name -B $companyConfig.installed_by } |
                                Select-Object -First 1
            if ($matchedInstaller) { $fields += @{ 'installed by' = "[$($matchedInstaller.id)]" } }
        }

        $newConfigRequest['Fields'] = $fields

        try {
            $huduconfig = $null
            if ($newConfigRequest.Id) {
                Write-Host "updating with $($newConfigRequest | ConvertTo-Json -Depth 5)"
                $huduconfig = Set-HuduAsset @newConfigRequest
            } else {
                Write-Host "creating with $($newConfigRequest | ConvertTo-Json -Depth 5)"
                $huduconfig = New-HuduAsset @newConfigRequest
                if ($created) { $allHuduConfigs += $created }
            }
        } catch {
            Write-Host "Error upserting config '$($newConfigRequest.Name)' for '$($matchedCompany.name)': $_"
        }
        if ($null -ne $huduconfig) {
            $ITBoostData.configurations['matches'] += @{
                CompanyName      = $companyConfig.organization
                CsvRow           = $companyConfig.CsvRow
                ITBID            = $companyConfig.id
                Name             = $(($companyConfig.name).Trim())
                HuduID           = $huduconfig.id
                HuduObject       = $huduconfig
                HuduCompanyId    = $huduconfig.company_id
            }
        }

    }
    $ConfigurationsHaveBeenApplied=$true
}

}

$ITBoostData.configurations["matches"] | convertto-json -depth 99 | out-file $($(join-path $debug_folder -ChildPath "MatchedConfigurations.json")) -Force
