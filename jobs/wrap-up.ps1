
foreach ($layout in Get-HuduAssetLayouts) {write-host "setting $($(Set-HuduAssetLayout -id $layout.id -Active $true).asset_layout.name) as active" }
