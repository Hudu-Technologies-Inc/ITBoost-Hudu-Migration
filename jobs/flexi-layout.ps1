$standardlayouts = @('locations','configurations','contacts','domains','organizations','passwords')
$completedFlexlayouts = $completedFlexlayouts ?? @()
$flexiChoices = $ITBoostData.Keys | Where-Object { $_.ToLower() -notin $standardlayouts -and $_.ToLower() -notin  $completedFlexlayouts}
if (-not $flexiChoices -or $flexiChoices.count -eq 0){exit 0}

$FlexiLayoutName = Select-ObjectFromList -objects $flexiChoices -message "Which Flexi-Layout to process next?" -allowNull $false
$completedFlexlayouts+=$FlexiLayoutName
$flexiTemplate = "$project_workdir\mappings-$FlexiLayoutName.ps1"
Copy-Item "$project_workdir\jobs\flexi-map.ps1" $flexiTemplate -Force
Read-Host "Please fill out mappings in $flexiTemplate and ensure its completion. then, press enter."
$successRead = $false
while ($true) {
    try {
        . $flexiTemplate
        $successRead = $true
    } catch {
        Read-Host "Error reading your mappings file: $_ ($flexiTemplate); ensure its completion. then, press enter to try again."
    }
    if ($successRead) {break}
}

$LocationLayout = $allHuduLayouts | Where-Object { ($(Get-NeedlePresentInHaystack -needle "location" -haystack $_.name) -or $(Get-NeedlePresentInHaystack -needle "branch" -Haystack $_.name)) } | Select-Object -First 1; $LocationLayout = $LocationLayout.asset_layout ?? $LocationLayout;

if ($ITBoostData.ContainsKey("$FlexiLayoutName")){
    $flexisLayout = $allHuduLayouts | Where-Object { ($(Get-NeedlePresentInHaystack -needle "$FlexiLayoutName" -haystack $_.name) -or $(Get-NeedlePresentInHaystack -needle "$FlexiLayoutName" -Haystack $_.name)) } | Select-Object -First 1
    if (-not $flexisLayout){
        $flexisLayout=$(New-HuduAssetLayout -name "$FlexiLayoutName" -Fields $FlexiFields -Icon $($flexiIcon ?? "fas fa-users") -IconColor "#ffffff" -Color "#6136ff" -IncludePasswords $true -IncludePhotos $true -IncludeComments $true -IncludeFiles $true).asset_layout
        $flexisLayout = Get-HuduAssetLayouts -id $flexisLayout.id
    }
    $flexisFields = $flexisLayout.fields
    $groupedflexis = $ITBoostData.flexis.CSVData | Group-Object { $_.organization } -AsHashTable -AsString
    try {
        $allHuduflexis = Get-HuduAssets -AssetLayoutId $flexisLayout.id
    } catch {
        $allHuduflexis=@()
    }
   $flexiIndex    = if ($allHuduflexis.count -gt 0) {Build-HuduflexiIndex -flexis $allHuduflexis} else {@{    ByName  = @{}
    ByEmail = @{}
    ByPhone = @{}}}
    foreach ($company in $groupedflexis.Keys) {
        write-host "starting $company"
        $flexisForCompany = $groupedflexis[$company]
        $matchedCompany = $huduCompanies | where-object {
            ($_.name -eq $company) -or
            [bool]$(Test-NameEquivalent -A $_.name -B "*$($company)*") -or
            [bool]$(Test-NameEquivalent -A $_.nickname -B "*$($company)*")} | Select-Object -First 1
        $matchedCompany = $huduCompanies | Where-Object {
            $_.name -eq $company -or
            (Test-NameEquivalent -A $_.name -B "*$company*") -or
            (Test-NameEquivalent -A $_.nickname -B "*$company*")
            } | Select-Object -First 1

            $matchedCompany = $matchedCompany ?? (Get-HuduCompanies -Name $company | Select-Object -First 1)

        if (-not $matchedCompany -or -not $matchedCompany.id -or $matchedCompany.id -lt 1) { continue }
        foreach ($companyflexi in $flexisForCompany){
            $matchedflexi = Find-Huduflexi `
            -CompanyId  $matchedCompany.id `
            -FirstName  $companyflexi.first_name `
            -LastName   $companyflexi.last_name `
            -Email      $companyflexi.primary_email `
            -Phone      $companyflexi.primary_phone `
            -Index      $flexiIndex

            # Optional fallback to API search by name if still null:
            if (-not $matchedflexi -and ($companyflexi.first_name -or $companyflexi.last_name)) {
            $qName = ("{0} {1}" -f $companyflexi.first_name, $companyflexi.last_name).Trim()
            $matchedflexi = Get-HuduAssets -AssetLayoutId $flexisLayout.id -CompanyId $matchedCompany.id -Name $qName |
                                Select-Object -First 1
            }
            if ($matchedflexi){
                    $humanName = ("{0} {1}" -f $companyflexi.first_name, $companyflexi.last_name).Trim()
                    Write-Host "Matched $humanName to $($matchedflexi.name) for $($matchedCompany.name)"

                    # ensure the array exists once
                    if (-not $ITBoostData.flexis.ContainsKey('matches')) { $ITBoostData.flexis['matches'] = @() }

                    $ITBoostData.flexis['matches'] += @{
                        CompanyName      = $companyflexi.organization
                        CsvRow           = $companyflexi.CsvRow
                        ITBID            = $companyflexi.id
                        Name             = $humanName
                        HuduID           = $matchedflexi.id
                        HuduObject       = $matchedflexi
                        HuduCompanyId    = $matchedflexi.company_id
                        PasswordsToCreate= ($companyflexi.password ?? @())
                    }
                    continue

            } else {
                $newflexirequest=@{
                    Name="$($companyflexi.first_name) $($companyflexi.last_name)".Trim()
                    CompanyID = $matchedCompany.id
                    AssetLayoutId=$flexisLayout.id
                }
                if ($false -eq $UseSimpleMap){
                    $newflexirequest["Fields"]=Build-FieldsFromRow -row $companyflexi -layoutFields $flexisFields -companyId $matchedCompany.id
                
                } else {
                    $fields = @()
                    foreach ($key in $flexisMap.Keys | where-object {$_ -ne "location"}) {
                        # pull value from CSV row
                        $rowVal = $companyflexi.$key ?? $null
                        if ($null -eq $rowVal) { continue }
                        $rowVal = [string]$rowVal
                        if ([string]::IsNullOrWhiteSpace($rowVal)) { continue }

                        $huduField = $flexisMap[$key]
                        $fields+=@{ $($huduField) = $rowVal.Trim() }
                        }

                        if (-not $([string]::IsNullOrWhiteSpace($companyflexi.location))){
                                $matchedlocation = Get-HuduAssets -AssetLayoutId ($LocationLayout.id ?? 2) -CompanyId $matchedCompany.id |
                                                Where-Object { Test-NameEquivalent -A $_.name -B $companyflexi.location } |
                                                Select-Object -First 1
                                               if ($matchedlocation){
                                $fields+=@{"Location" = "[$($matchedlocation.id)]"}
                            }
                        }
                        $newflexirequest["Fields"]=$fields

                    }



                }


                try {
                    $newflexi = New-Huduasset @newflexirequest
                } catch {
                    write-host "Error creating location: $_"
                }
                if ($newflexi){
                    $ITBoostData.flexis["matches"]+=@{
                        CompanyName=$companyflexi.organization
                        CsvRow=$companyflexi.CsvRow
                        ITBID=$companyflexi.id
                        Name=$companyflexi.name
                        HuduID=$newflexi.id
                        HuduObject=$newflexi
                        HuduCompanyId=$newflexi.company_id
                        PasswordsToCreate=$($companyflexi.password ?? @())
                    }            
                }
            }
        }
    }
 else {write-host "no flexis in CSV! skipping."} 

foreach ($dupeflexi in $(Get-HuduAssets -AssetLayoutId $flexisLayout.id | Group-Object { '{0}|{1}' -f $_.company_id, (($_.'name' -as [string]).Trim() -replace '\s+',' ').ToLower() } | Where-Object Count -gt 1 | ForEach-Object { $_.Group | Sort-Object id | Select-Object -Skip 1 } )){
    if ($dupeflexi.archived -eq $true){continue}
    Remove-HuduAsset -id $dupeflexi.id -CompanyId $dupeflexi.company_id -Confirm:$false}