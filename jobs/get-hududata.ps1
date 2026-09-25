Write-Host "Fetching Hudu AssetLayouts from $(Get-HuduBaseURL)"
$allHuduLayouts=Get-HuduAssetlayouts
Write-Host "Fetching Hudu Companies from $(Get-HuduBaseURL)"
$huduCompanies = Get-HuduCompanies
Write-Host "Fetching Hudu Websites from $(Get-HuduBaseURL)"
$allHuduWebsites=Get-HuduWebsites
$allHuduLocations=@()
$allHuduContacts=@()
Write-Host "Fetching Hudu Passwords from $(Get-HuduBaseURL)"
$allHuduPasswords=Get-HuduPasswords
$LocationLayout = $locationlayout ?? $(Get-HuduAssetLayouts | Where-Object { $_.name -ieq "location" -or $_.name -ieq "locations" } | Select-Object -First 1); $LocationLayout = $LocationLayout.asset_layout ?? $LocationLayout;

if ($null -eq $internalCompanyId){
    $internalCompanyName = $internalCompanyName ?? "Your internal Company"
    $internalcompany = $huduCompanies | where-object {$_.name -ieq $internalCompanyName} | select-object -first 1 
    $internalCompany= $internalCompany.company ?? $internalCompany
    $internalCompanyId = $internalCompany.id ?? $null
}


if ($null -eq $internalCompanyId){
    $internalCompanyName = $internalCompanyName ?? "Your internal Company"
    $internalCompany =New-HuduCompany -name "$internalCompanyName" -notes "Auto-created internal company for special attribution during ITBoost migration"
    $huduCompanies = Get-HuduCompanies
    $internalCompany= $internalCompany.company ?? $internalCompany
    $internalCompanyId = $internalCompany.id ?? $(read-host "please enter the id (integer) of internal hudu company")

}
if ($null -eq $internalCompanyId){
write-host "Cannot find or create internal company, please rerun and specify internal company id"
exit 1
}
write-host "using internal company $internalCompanyId for internal attributions"
$kbsEnabled = Get-HuduFeatureAvailability -Core_Feature articles
$assetsEnabled = Get-HuduFeatureAvailability -Core_Feature assets
$ipamenabled = Get-HuduFeatureAvailability -Core_Feature ipaddress
write-host -ForegroundColor Cyan @"
Knowledge of Hudu Feature Availability:
Articles Enabled: $kbsEnabled
Assets Enabled: $assetsEnabled
IP Address Management Enabled: $ipamenabled
"@