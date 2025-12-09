
foreach ($layout in Get-HuduAssetLayouts) {write-host "setting $($(Set-HuduAssetLayout -id $layout.id -Active $true -color "#6136ff" -icon_color "#ffffff").asset_layout.name) as active" }
get-huduwebsites | Foreach-Object {write-host "Enabling advanced monitoring features for $($(Set-HuduWebsite -id $_.id -EnableDMARC 'true' -EnableDKIM 'true' -EnableSPF 'true' -DisableDNS 'false' -DisableSSL 'false' -DisableWhois 'false' -Paused 'false').name)" -ForegroundColor DarkCyan}

foreach ($p in $(get-hudupasswords)){
    $pass = $p.asset_password ?? $p; $desc = $pass.description;
    if ([string]::IsNullOrEmpty($desc)){write-host "empty description on pass $($pass.id), skipping"}
    $descupdated = ConvertFrom-HtmlToPlainText $desc
    if ($desc -ne $descupdated){Set-HuduPassword -id $pass.id -CompanyId $pass.company_id -Description $descupdated} else {write-host "Skipping description on pass - no change for $($pass.id)"}

}