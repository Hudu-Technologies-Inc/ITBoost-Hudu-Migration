
$ConfigExpansionMethod = $ConfigExpansionMethod ?? $(Select-ObjectFromList -message "Which Expansion Method for Config Data?" -objects @("IPAM-Only","RichText-Field","ALL"))

$ConfigsRichTextOverviewField = "Additional Information"

$FieldsAsArrays = @(
    "primary_ip",
    "default_gateway",
    "mac_address",
    "hostname",
    "configuration_interfaces"
)

if ($ITBoostData.ContainsKey("configurations") -and $true -eq $ConfigurationsHaveBeenApplied){
    $namesSeen = @()   
    $huduCompanies = $huduCompanies ?? $(get-huducompanies)
    $configsLayout = Get-HuduAssetLayouts -id $configsLayout.id; $configsLayout = $configsLayout.asset_layout ?? $configsLayout
    if (@("ALL","RichText-Field") -contains $ConfigExpansionMethod){
            $OverviewField = $configsLayout.fields | where-object {$_.label -eq $ConfigsRichTextOverviewField -and $_.field_type -eq "RichText"} | Select-Object -First 1
            if ($OverviewField){
                Write-Host "Additional Data richtext field is $($OverviewField.label) / $($OverviewField.id)"
            } else {
                $UpdateFields=@()
                foreach ($f in $configsLayout.fields){
                    $UpdateFields+=$f
                }
                $UpdateFields+=@{label=$ConfigsRichTextOverviewField; field_type = "RichText"; required=$false; position=259;}
                Set-HuduAssetLayout -id $configsLayout.id -fields $UpdateFields
                $configsLayout = Get-HuduAssetLayouts -id $configsLayout.id; $configsLayout = $configsLayout.asset_layout ?? $configsLayout
            }
    }
    else {Write-Host "Skipping check for richtext overview field"}
    $configsFields = $configsLayout.fields
    $uniqueCompanies = $ITBoostData.configurations.CSVData |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.organization) } | Select-Object -ExpandProperty organization -Unique
    $ConfigsGroupedByOrg = $ITBoostData.configurations.CSVData | Group-Object { $_.organization } -AsHashTable -AsString
    $ConfigsGroupedBySerial = $ITBoostData.configurations.CSVData | Group-Object { $_.serial_number } -AsHashTable -AsString
    $ConfigsGroupedByID = $ITBoostData.configurations.CSVData | Group-Object { $_.id } -AsHashTable -AsString
    Write-Host "Joining config data for $($uniqueCompanies.count) companies, $($ConfigsGroupedBySerial.Keys.Count) serials"
    
    foreach ($company in $uniqueCompanies) {
        Write-Host "starting $company"
        $configsForCompany = $ITBoostData.configurations.CSVData | Where-Object { $_.organization -eq $company }
        $matchedCompany = $huduCompanies | where-object { ($_.name -eq $company) -or [bool]$(Test-NameEquivalent -A $_.name -B "*$($company)*") -or [bool]$(Test-NameEquivalent -A $_.nickname -B "*$($company)*")} | Select-Object -First 1
        $matchedCompany = $matchedCompany ?? $huduCompanies | Where-Object { $_.name -eq $company -or (Test-NameEquivalent -A $_.name -B "*$company*") -or (Test-NameEquivalent -A $_.nickname -B "*$company*") } | Select-Object -First 1
        $matchedCompany = $matchedCompany ?? (Get-HuduCompanies -Name $company | Select-Object -First 1)
        if (-not $matchedCompany.id) { write-host "NO COMPANY matched for $Company"; continue;}
        foreach ($companyConfig in $configsForCompany) {
            $ConfigCollection = @()
            $matchedConfig = $allHuduConfigs | Where-Object {$_.company_id -eq $matchedCompany.id -and (Test-NameEquivalent -A $_.name -B $companyConfig.name)} | Select-Object -First 1
            $matchedConfig = $matchedConfig ?? $(Get-HuduAssets -AssetLayoutId $configsLayout.id -CompanyId $matchedCompany.id -Name $companyConfig.name | Select-Object -First 1)
            if (-not $matchedConfig) {
                Write-Host "No Match Found in all of configs for $($companyConfig.id)"; continue;
            }
            if (([string]::IsNullOrEmpty($companyConfig.id))){
                Write-Host "Single ID found in all of configs for $($companyConfig.id)"; continue;
            }
            foreach ($matchedById in $ConfigsGroupedByID["$($companyConfig.id)"]){
                $configCollectionEntry=@{}
                foreach ($collectionProp in $FieldsAsArrays){
                    $configCollectionEntry[$collectionProp] = $matchedById.$collectionProp
                }
                $ConfigCollection+=$configCollectionEntry
            }


            if (@("ALL","RichText-Field") -contains $ConfigExpansionMethod){


            }




        


        }
    }
}