Write-Host "Fetching Hudu AssetLayouts fron $(Get-HuduBaseURL)"
$allHuduLayouts=Get-HuduAssetlayouts
Write-Host "Fetching Hudu Companies fron $(Get-HuduBaseURL)"
$huduCompanies = Get-HuduCompanies
Write-Host "Fetching Hudu Websites fron $(Get-HuduBaseURL)"
$allHuduWebsites=Get-HuduWebsites
$allHuduLocations=@()
$allHuduContacts=@()
Write-Host "Fetching Hudu Passwords fron $(Get-HuduBaseURL)"
$allHuduPasswords=Get-HuduPasswords

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