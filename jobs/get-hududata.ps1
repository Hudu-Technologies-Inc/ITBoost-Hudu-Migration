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
