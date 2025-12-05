# load companies index if available
$ITBoostData.organizations["matches"] = $ITBoostData.organizations["matches"] ?? $(get-content $companiesIndex -Raw | convertfrom-json -depth 99) ?? @()
# Match or create websites from domains data
if ($ITBoostData.ContainsKey("domains")){
    $allHuduWebsites = Get-HuduWebsites
    
    foreach ($row in $($ITBoostData.domains.CSVData | Sort-Object organization -Descending)){

        if (-not [string]::IsNullOrEmpty(($row.organization))){
            $matchedCompany = Get-HuduCompanyFromName -CompanyName $row.organization -HuduCompanies $huduCompanies  -existingIndex $($ITBoostData.organizations["matches"] ?? $null)
        } else {
            #internal
            $matchedCompany = get-huducompanies -id 5555; $matchedCompany = $matchedCompany.company ?? $matchedCompany;
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
                $newWebsite=New-HuduWebsite @newWebsiteRequest
            } catch {
                Write-Host "Error during company create $_"
            }
            if ($newWebsite){
                # $ITBoostData.domains["matches"]+=@{
                #     CsvRow=-1
                #     ITBID=$row.id
                #     Name=$row.name
                #     HuduID=$newWebsite.id
                #     HuduObject=$newWebsite
                #     CompanyName=$row.organization
                #     HuduCompanyId=$newWebsite.company_id
                #     PasswordsToCreate=$($row.password ?? @())
                # }
            }
            continue
        } else {
                Write-Host "match for website $($row.name) found in Hudu for $($matchedCompany.name)"

            # Write-Host "Matched website $($MatchedWebsite.name) to $($row.name)"
            # $ITBoostData.organizations["matches"]+=@{
            #     CompanyName=$row.organization
            #     CsvRow=$row.CsvRow
            #     ITBID=$row.id
            #     Name=$row.name
            #     HuduID=$MatchedWebsite.id
            #     HuduObject=$MatchedWebsite
            #     HuduCompanyId=$MatchedWebsite.company_id
            #     PasswordsToCreate=$($row.password ?? @())
            # }
            continue
        }
    }
} else {write-host "no websites in CSV! skipping."}
$allHuduWebsites=Get-HuduWebsites
$allHuduWebsites | Foreach-Object {write-host "Enabling advanced monitoring features for $($(Set-HuduWebsite -id $_.id -EnableDMARC 'true' -EnableDKIM 'true' -EnableSPF 'true' -DisableDNS 'false' -DisableSSL 'false' -DisableWhois 'false' -Paused 'false').name)" -ForegroundColor DarkCyan}