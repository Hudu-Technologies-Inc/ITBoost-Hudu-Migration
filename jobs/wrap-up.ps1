
foreach ($layout in Get-HuduAssetLayouts) {write-host "setting $($(Set-HuduAssetLayout -id $layout.id -Active $true -color "#6136ff" -icon_color "#ffffff").asset_layout.name) as active" }
get-huduwebsites | Foreach-Object {write-host "Enabling advanced monitoring features for $($(Set-HuduWebsite -id $_.id -EnableDMARC 'true' -EnableDKIM 'true' -EnableSPF 'true' -DisableDNS 'false' -DisableSSL 'false' -DisableWhois 'false' -Paused 'false').name)" -ForegroundColor DarkCyan}

foreach ($p in $(get-hudupasswords)){
    $pass = $p.asset_password ?? $p; $desc = $pass.description;
    if ([string]::IsNullOrEmpty($desc)){write-host "empty description on pass $($pass.id), skipping"; continue}
    $descupdated = ConvertFrom-HtmlToPlainText "$desc"
    if ($desc -ne $descupdated -and -not ([string]::IsNullOrWhiteSpace(($descupdated) -and $pass.id -ne $null))){Set-HuduPassword -id $pass.id -CompanyId $pass.company_id -Description "$descupdated"} else {write-host "Skipping description on pass - no change for $($pass.id)"; continue;}

}

# dedupe websites from all DNS, domain, ssl combined for internal company, since these usually come from multiple sources
$webByName = $(Get-HuduWebsites | Group-Object { $_.name.ToLowerInvariant() })
 foreach ($w in $(Get-HuduWebsites  | where-object {$_.company_id -eq $internalCompanyId})) {
     $WSGroup = $webByName | Where-Object { $_.Name -eq $($w.name.ToLowerInvariant()) }
     if (-not $WSGroup) { continue }
     $externalDupes = $WSGroup.Group | Where-Object { $_.company_id -ne $internalCompanyId }
     if ($externalDupes.Count -ge 1) {
        Write-Host "Removing duplicate '$($w.name)' from company $internalCompanyId (keeping other company copy)"
        Remove-HuduWebsite -Id $w.id -Confirm:$false
     }
 }



foreach ($inactiveOrg in $itboostdata.organizations.csvdata | where-object {$_.organization_status -ilike "Inactive"}){
    $matchedCompany = Get-HuduCompanyFromName -CompanyName $inactiveOrg.name -HuduCompanies $huduCompanies  -existingIndex $($ITBoostData.organizations["matches"] ?? $null)
    if (-not $matchedCompany) {continue}
    write-host "Deactivating company $($matchedCompany.name) as per ITBoost data"
    # Set-HuduCompanyArchive -id $matchedCompany.id -archive $true -Confirm:$false
}