

$FieldsAsArrays = @(
    ""

)

if ($ITBoostData.ContainsKey("configurations") -and $true -eq $ConfigurationsHaveBeenApplied){
    $namesSeen = @()   
    $huduCompanies = $huduCompanies ?? $(get-huducompanies)
    $configsLayout = Get-HuduAssetLayouts -id $configsLayout.id
    $configsFields = $configsLayout.fields
    $uniqueCompanies = $ITBoostData.configurations.CSVData |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.organization) } | Select-Object -ExpandProperty organization -Unique
    $ConfigsGroupedByOrg = $ITBoostData.configurations.CSVData | Group-Object { $_.organization } -AsHashTable -AsString
    $ConfigsGroupedBySerial = $ITBoostData.configurations.CSVData | Group-Object { $_. } -AsHashTable -AsString
    $ConfigsGroupedByMAC = $ITBoostData.configurations.CSVData | Group-Object { $_."macAddress" } -AsHashTable -AsString
    Write-Host "Joining config data for $($uniqueCompanies.count) companies, $($ConfigsGroupedBySerial.Keys.Count) serials"











}