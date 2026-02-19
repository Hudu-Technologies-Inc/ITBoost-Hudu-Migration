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
    Set-HuduCompanyArchive -id $matchedCompany.id -archive $true -Confirm:$false
}