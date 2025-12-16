# load companies index if available
$ITBoostData.organizations["matches"] = $ITBoostData.organizations["matches"] ?? $(get-content $companiesIndex -Raw | convertfrom-json -depth 99) ?? @()
# Match or create websites from domains data
if ($ITBoostData.ContainsKey("domains")){
    if (-not $ITBoostData.domains.ContainsKey('matches')) { $ITBoostData.domains['matches'] = @() }
    $allHuduWebsites = Get-HuduWebsites
    
    foreach ($row in $($ITBoostData.domains.CSVData | Sort-Object organization -Descending)){

        if (-not [string]::IsNullOrEmpty(($row.organization))){
            $matchedCompany = Get-HuduCompanyFromName -CompanyName $row.organization -HuduCompanies $huduCompanies  -existingIndex $($ITBoostData.organizations["matches"] ?? $null)
        } else {
            #internal
            $internalCompanyId = $internalCompanyId ?? $(read-host "please enter the id (integer) of internal hudu company")
            $matchedCompany = Get-HuduCompanies -id $internalCompanyId; $matchedCompany = $matchedCompany.company ?? $matchedCompany;
        }
        if ($null -eq $matchedCompany -or $null -eq $matchedCompany.id) {
            continue
        }

        $notes = Get-NotesFromArray -notesInput $($row.notes ?? @())
        $MatchedWebsite=$null
        $MatchedWebsite=$null
        $MatchedWebsite = $allHuduWebsites | Where-Object {
            ($_.name -ilike "*$($row.name)") -and $_.company_id -eq $matchedCompany.id
        } | Select-Object -First 1

        if ($null -eq $MatchedWebsite){
            $allHuduWebsites = Get-HuduWebsites
            $MatchedWebsite = $allHuduWebsites | Where-Object {
                ($_.name -ilike "*$($row.name)") -and $_.company_id -eq $matchedCompany.id
            } | Select-Object -First 1
        }
        if ($null -eq $MatchedWebsite){
                Write-Host "No match for website $($row.name) found in Hudu for $($matchedCompany.name)"
                $newWebsiteRequest=@{
                    Name = "$($($row.name -replace '[\\/]+$', '') -replace '^(?!https://)', 'https://')".Trim()
                    Notes=$notes; CompanyID=$matchedCompany.id
                    DisableSSL='false'; DisableDNS='false'; DisableWhois='false'; EnableDMARC='true'; EnableDKIM='true'; EnableSPF='true';}            
            try {
                $newwebsite = $null
                $newWebsite=New-HuduWebsite @newWebsiteRequest
                $newWebsite = $newwebsite.website ?? $newWebsite
            } catch {
                Write-Host "Error during company create $_"
            }
            if ($null -ne $newWebsite){
                write-host "Created new website $($newWebsite.name) with ID $($newWebsite.id) for company $($matchedCompany.name)"
                $ITBoostData.domains["matches"]+=@{
                    ITBID=$row.id
                    Name=$row.name
                    HuduID=$newWebsite.id
                    HuduObject=$newWebsite
                    CompanyName=$row.organization
                    HuduCompanyId=$newWebsite.company_id
                }
            }
            continue
        } else {
            Write-Host "Matched website $($MatchedWebsite.name) to $($row.name)"
            $ITBoostData.domains["matches"]+=@{
                CompanyName=$row.organization
                ITBID=$row.id
                Name=$row.name
                HuduID=$MatchedWebsite.id
                HuduObject=$MatchedWebsite
                HuduCompanyId=$MatchedWebsite.company_id
            }
            continue
        }
    }
} else {write-host "no websites in CSV! skipping."}
$allHuduWebsites=Get-HuduWebsites
$allHuduWebsites | Foreach-Object {write-host "Enabling advanced monitoring features for $($(Set-HuduWebsite -id $_.id -EnableDMARC 'true' -EnableDKIM 'true' -EnableSPF 'true' -DisableDNS 'false' -DisableSSL 'false' -DisableWhois 'false' -Paused 'false').name)" -ForegroundColor DarkCyan}

if ($itboostdata.ContainsKey('ssl-certificates')){
    if (-not $ITBoostData.'ssl-certificates'.ContainsKey('matches')) { $ITBoostData.'ssl-certificates'['matches'] = @() }
}

$ITBoostData.'ssl-certificates'.CSVData | ForEach-Object {
    $company = $null
    if ([string]::IsNullOrEmpty($_.organization)) {
        $company = Get-HuduCompanies -id $internalCompanyId; $company = $company.company ?? $company;
    } else {
        $company = Get-HuduCompanies -name $_.organization; $company = $company.company ?? $company;
    }
    $ws = $null
    $existing = get-huduwebsites -name "https://$($_.host)" | where-object { $_.company_id -eq $company.id } | Select-Object -first 1
    if ($existing) {
        Write-Host "Found existing website $($existing.name) for SSL cert $($_.host)"x
        $existing = $existing.website ?? $existing
        $itboostdata.'ssl-certificates'['matches']+=@{
            CompanyName=$_.organization
            CsvRow=$_.CsvRow
            ITBID=$_.id
            Name=$existing.name
            HuduID=$existing.id
            HuduObject=$existing
            HuduCompanyId=$existing.company_id
        }
        continue
    }
    $ws = New-HuduWebsite -Name "https://$($_.host)" -CompanyId $company.id ?? $internalCompanyId -Notes "From ITBoost -SSL"
    if ($ws) {
            Write-Host "Created website $($ws.name) for SSL cert $($_.host)"
        $ws = $ws.website ?? $ws
        $itboostdata.'ssl-certificates'['matches']+=@{
            CompanyName=$_.organization
            CsvRow=$_.CsvRow
            ITBID=$_.id
            Name=$ws.name
            HuduID=$ws.id
            HuduObject=$ws
            HuduCompanyId=$ws.company_id
        }


    } else {
            Write-Host "Error creating website for SSL cert $($_.host)"

    }


}


$ITBoostData.domains["matches"] | convertto-json -depth 99 | out-file $($(join-path $debug_folder -ChildPath "Matched-websites.json")) -Force
$ITBoostData.'ssl-certificates'["matches"] | convertto-json -depth 99 | out-file $($(join-path $debug_folder -ChildPath "Matched-ssl.json")) -Force
