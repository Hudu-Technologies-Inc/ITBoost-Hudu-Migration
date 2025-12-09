
if (-not $ITBoostData.ContainsKey('Internal Notes for PCA Only')){write-host "No direct notes data in csvs, skppping"; exit 0}

$articlesFromSTandalonenotes = @{}

foreach ($noteEntry in $ITBoostData.Notes.CSVData){
    $articleRequest = @{
        Name = $noteEntry.name
    }
    $matchedCompany = Get-HuduCompanyFromName -CompanyName $company -HuduCompanies $huduCompanies  -existingIndex $($ITBoostData.organizations["matches"] ?? $null)
    if (-not $matchedCompany){
        $internalCompanyId = $internalCompanyId ?? $(read-host "enter internal company id"); $articleRequest["CompanyId"]=$internalCompanyId;
    } else {
        $matchedCompany = $matchedCompany.company ?? $matchedCompany; $articleRequest["CompanyId"]=$matchedCompany.id
    }
    $content = $null
    $content = Get-ValueFromCSVKeyVariants -Row $noteEntry -Label $($noteEntry.keys | Where-Object {$_ -ilike "Notes" -or $_ -ilike "information"} | Select-Object -first 1)
    if ([string]::IsNullOrWhiteSpace($content)){continue}
    $existingArticle = $null
    $existingArticle = get-huduarticles -CompanyId $matchedCompany.id -name $articleRequest.name | select-object -first 1
    if ($null -ne $existingArticle){$articleRequest["Id"]=$existingArticle}
    if ($articleRequest.ContainsKey("Id")) {
        Set-HuduARticle @articleRequest
    } else {   
        $existingArticle = New-HuduARticle @articleRequest; $existingArticle = $existingArticle.article ?? $existingArticle;
    }

    if ($([string]::IsNullOrWhiteSpace($noteEntry.location) -or $null -eq $existingArticle)){continue}
    $articlesFromSTandalonenotes["$($existingArticle.slug)"]=$existingArticle

    $locationDeserialized = SafeDecode $noteEntry.location
    $locationDeserialized = $locationDeserialized.value ?? $locationDeserialized.text ?? $locationDeserialized.location ?? $locationDeserialized
    if ($([string]::IsNullOrWhiteSpace($locationDeserialized))){continue}
    $matchedlocation = Get-HuduAssets -AssetLayoutId ($LocationLayout.id ?? 2) -CompanyId $matchedCompany.id |
                        Where-Object { test-equiv -A $_.name -B $locationDeserialized } |
                        Select-Object -First 1
    $matchedlocation = $matchedlocation.asset ?? $matchedlocation
    if (-not $matchedlocation){continue} else {New-Hudurelation -ToableType "Article" -FromableType "Asset" -ToableID $existingArticle.id -FromableID $matchedlocation.id}

    

}