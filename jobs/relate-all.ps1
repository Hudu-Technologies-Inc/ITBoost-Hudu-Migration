$ITBoostData.organizations["matches"] = $ITBoostData.organizations["matches"] ?? $(get-content $companiesIndex -Raw | convertfrom-json -depth 99) ?? @()
$huduCompanies = $huduCompanies ?? $(get-huducompanies)
$nameKeys = @{}
$uploads = @()
foreach ($key in $itboostdata.keys){
    $attachments = $(Get-ChildItem -Recurse -File $itboostdata.$key.AttachmentsPath)
    foreach ($attachment in $attachments){
        $parentFolder = $attachment.Directory.Name
        $matched = $itboostdata.$key.csvdata | Where-Object {"$($_.id)" -ieq "$parentFolder"} | select-object -first 1
        if (-not $matched){continue}

        $matchedCompany = Get-HuduCompanyFromName -CompanyName $matched.organization -HuduCompanies $huduCompanies  -existingIndex $($ITBoostData.organizations["matches"] ?? $null)
        if (-not $matchedCompany){continue}
        
        if ($nameKeys.ContainsKey($key)){
            $AltNameKey = $nameKeys[$key]
        } else {
            $AltNameKey = Get-CSVProperties $matched | where-object {"$_" -ilike "*name*" -or "$_" -ilike "*$key*"} | select-object -first 1
        }
        if ($key -ilike "*contacts*"){$givenName="$($matched.first_name) $($matched.last_name)"} else {
            $GivenName = $($matched.name ?? $matched.$AltNameKey ?? $matched.$key ?? $null)
        }
        if ([string]::IsNullOrEmpty($givenName)){
            $nameProp = select-objectfromlist -message "which NameProp for $key?" -objects $(Get-CSVProperties $matched)
            $GivenName = $matched.$nameProp
        }
        if ([string]::IsNullOrEmpty($givenName)){
                continue
        }

        $matchedAssets = Get-HuduAssets -companyId $matchedCompany.id -name $GivenName | select-object -first 1
        $matchedAssets = $matchedAssets.asset ?? $matchedAssets
        if (-not $matchedAssets -or -not $matchedAssets.id){continue}
        $existingupload=$null
        $existingUpload = get-huduuploads | where-object {$_.uploadable_type -ieq "Asset" -and $_.uploadable_id -eq $matchedAssets.id -and $_.name -ieq $attachment.name}
        $existingUpload = $existingUpload.upload ?? $existingUpload
        if ($null -ne $existingUpload -and $null -ne $existingUpload.id -and $null -ne $existingUpload.name){write-host "Skipping existing upload $($existingUpload.name)"; continue;}
        
        write-host "Matched attachment $($attachment.fullname) for $($matchedCompany.name) in $Key"
        $u = New-HuduUpload -uploadable_type "Asset" -uploadable_id $matchedAssets.id -FilePath $attachment.FullName
        $u = $u.upload ?? $u
        $uploads+=$u

    }
}
