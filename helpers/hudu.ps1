function Clear-DupeDocuments {
    param ([array]$HuduArticles, [array]$huduUploads)

    $HuduArticles |
        Group-Object { '{0}|{1}' -f ($_.company_id ?? -1), (([string]$_.name).Trim() -replace '\s+',' ').ToLower() } |
        Where-Object Count -gt 1 |
        ForEach-Object {
        $_.Group |
            Sort-Object @{Expression={ 
                $d=$_.updated_at ?? $_.created_at; try{[datetime]$d}catch{Get-Date '1900-01-01'} }; Descending=$true
            }, @{
                Expression='id'; Descending=$true
            } | Select-Object -Skip 1
        } |
        Where-Object { $_.archived -ne $true } |
        ForEach-Object { Remove-HuduArticle -Id $_.id -Confirm:$false }

    $huduUploads |
        Group-Object {
            $uid = $_.uploadable_id
            $utype = $_.uploadable_type
            $nm  = (([string]$_.name).Trim() -replace '\s+',' ').ToLower()
            { "{0}|{1}|{2}" -f $uid,$utype,$nm }
        }  | Where-Object Count -gt 1 | ForEach-Object {
            $_.Group |  Sort-Object @{Expression={
                $d=$_.created_at ?? $_.created_date; try{[datetime]$d}catch{Get-Date '1900-01-01'} }; Descending=$true
            }, @{Expression='id'; Descending=$true} | Select-Object -Skip 1
         } | ForEach-Object { Invoke-HuduRequest -Method delete -Resource "/api/v1/uploads/$($_.id)" }
}

function remove-dupeassets {
    param ([bool]$dryRun = $true)
    write-host "RUNNING IN $($dryRun -eq $true ? 'DRY RUN' : 'LIVE') MODE. NO ASSETS WILL BE REMOVED IN DRY RUN MODE." -ForegroundColor Yellow

$candidates =
    Get-HuduAssets |
    Group-Object {
        '{0}|{1}|{2}' -f (
            $_.company_id ?? -1
        ), (
            $_.asset_layout_id ?? -1
        ), (
            (([string]$_.name).Trim() -replace '\s+', ' ').ToLower()
        )
    } |
    Where-Object Count -gt 1 |
    ForEach-Object {
        $sorted = $_.Group | Sort-Object `
            @{ Expression = {
                    $d = $_.created_at ?? $_.updated_at;
                    try { [datetime]$d } catch { Get-Date '1900-01-01' }
                }; Descending = $false
            },
            @{ Expression = 'id'; Descending = $false }

        $keeper = $sorted | Select-Object -First 1
        $dupes  = $sorted | Select-Object -Skip 1

        foreach ($d in $dupes) {
            [pscustomobject]@{
                LayoutId       = $d.asset_layout_id
                CompanyId      = $d.company_id
                Name           = $d.name
                KeepId         = $keeper.id
                RemoveId       = $d.id
                KeepCreated    = $keeper.created_at
                RemoveCreated  = $d.created_at
                KeepUpdated    = $keeper.updated_at
                RemoveUpdated  = $d.updated_at
                Archived       = $d.archived
            }
        }
    }

$candidates | Format-Table -AutoSize
if ($true -eq $dryRun) {
    Write-Host "Dry run mode enabled. No assets will be removed."
    return $candidates
} else {
    foreach ($c in $candidates) {
        Remove-HuduAsset -Id $c.RemoveId -Confirm:$false
    }
    return $candidates
}
}

function Omni-Relate {
    
    function _Normalize-AssetName {
        param([string]$Name)
        if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
        $n = $Name.Normalize([Text.NormalizationForm]::FormKC)
        $n = $n -replace '&nbsp;',' ' -replace '\s+',' '
        $n = $n.Trim().ToLowerInvariant()
        return $n
    }

    function _Normalize-WebsiteURL {
        param([string]$Url)
        if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
        $u = $Url.Trim()
        if ($u -match '^(https?://)?(?<host>[^/]+)(?<rest>/.*)?$') {
            $hostname = $matches.host.ToLowerInvariant()
            return $hostname.ToLowerInvariant()
        }
        return $u.ToLowerInvariant()
    }

    if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $true} catch {}}
    write-host "obtaining companies..."; $allcompanies = get-huducompanies;
    write-host "obtaining assets (please be patient, this can take some time.)"; $allAssets = get-huduassets;
    write-host "obtaining websites..."; $allWebsites = get-huduwebsites;
    write-host "obtaining articles... (please be patient, this can take some time.)"; $allArticles = get-huduarticles;

    foreach ($c in $allcompanies) { 

        $companyAssets = $allAssets | Where-Object { $_.company_id -eq $c.id }
        $companywebsites = $allWebsites | Where-Object { $_.company_id -eq $c.id }
        $companyArticles = $allArticles | Where-Object { $_.company_id -eq $c.id }

        $companyAssetsByName = $companyAssets | Group-Object { _Normalize-AssetName $_.name } -AsHashTable -AsString

        foreach ($a in $companyAssets) {
            $normalizedAssetName = _Normalize-AssetName $a.name

            $mentionedWebsites = @()
            $mentionedArticles = @()
            $mentionedAssets = @()

            # websites and articles matched by name/description -> name of asset
            if ($companywebsites) {
                $mentionedWebsites = $companywebsites | Where-Object { $_.Notes -and $_.Notes.Contains($normalizedAssetName) }
            }
            if ($companyArticles) {
                $mentionedArticles = $companyArticles | Where-Object { ($_.Name -and $_.Content.Contains($a.name)) -or ($_.Content -and $_.Content.Contains($normalizedAssetName)) }
            }


            # websites where name or url is mentioned in text/richtext fields of the asset
            # articles with content or name mentioned in a website field (either website field or text/richtext fields)
            $a.fields | Where-Object {$_.field_type -eq "Website"} | ForEach-Object {
                $fieldValue = $_.value
                $mentionedWebsites += $companywebsites | Where-Object { "$(_Normalize-WebsiteURL $fieldValue)*" -ilike "$(_Normalize-WebsiteURL $_.name)*" -or $_.name -icontains "$(_Normalize-WebsiteURL $fieldValue)" -or $_.name -icontains $normalizedAssetName }
                $mentionedArticles += $companyArticles | Where-Object { $_.content -and $_.content.Contains("$(_Normalize-WebsiteURL $fieldValue)") -or ($_.Name -and $_.Name.Contains("$(_Normalize-WebsiteURL $fieldValue)")) }
                $mentionedAssets += $companyAssets | Where-Object { $_.name -and $_.name.Contains("$(_Normalize-WebsiteURL $fieldValue)") }
            }
            $a.fields | Where-Object {$_.field_type -eq "RichText" -or $_.field_type -eq "Header" -or $_.field_type -eq "Embed"} | ForEach-Object {
                $fieldValue = $_.value
                $mentionedWebsites += $companywebsites | Where-Object { $fieldValue -icontains $normalizedAssetName -or $(_Normalize-AssetName $_.name) -ieq $normalizedAssetName -or $fieldValue -icontains $_.name -or $_.notes -icontains $normalizedAssetName -or $_.notes -icontains $a.name }
                $mentionedArticles += $companyArticles | Where-Object { $_.content -and $_.content.Contains($normalizedAssetName) -or $_.content -icontains $a.name -or $normalizedAssetName -ieq (_Normalize-AssetName $_.name) }
                $mentionedAssets += $companyAssets | Where-Object { $fieldValue -and $fieldValue.Contains($normalizedAssetName) -or $fieldValue.Contains($a.name) }
            }       
            $a.fields | Where-Object {$_.field_type -eq "Text" -or $_.field_type -eq "Phone" -or $_.field_type -eq "Email"} | ForEach-Object {
                $fieldValue = $_.value
                $mentionedArticles += $companyArticles | Where-Object { $(_Normalize-AssetName $_.name) -ieq $(_Normalize-AssetName $fieldValue) }
                $mentionedWebsites += $companywebsites | Where-Object { $(_Normalize-AssetName $_.value) -ieq $normalizedAssetName }
            }
    
            # "siblings": other assets with same normalized name but different id
            $siblings = @($companyAssetsByName[$normalizedAssetName] | Where-Object { $_.id -ne $a.id })
            $siblings | ForEach-Object {write-host "Sibling Asset $($a.name)@($($a.asset_layout_id)) -> $($_.name)@($($_.asset_layout_id))"; New-HuduRelation -FromableType "Asset" -ToableType "Asset" -FromableID $a.id -ToableID $_.id}
            $mentionedWebsites | ForEach-Object {Write-Host "[$($c.name)] '$($a.name)' ($($a.id)) mentions website -> '$($_.name)' ($($_.id))"; New-HuduRelation -FromableType "Asset" -ToableType "Website" -FromableID $a.id -ToableID $_.id}
            $mentionedArticles | ForEach-Object {Write-Host "[$($c.name)] '$($a.name)' ($($a.id)) mentions article -> '$($_.name)' ($($_.id))"; New-HuduRelation -FromableType "Asset" -ToableType "Article" -FromableID $a.id -ToableID $_.id}
            $mentionedAssets | ForEach-Object {Write-Host "[$($c.name)] '$($a.name)' ($($a.id)) mentions asset -> '$($_.name)' ($($_.id))"; New-HuduRelation -FromableType "Asset" -ToableType "Asset" -FromableID $a.id -ToableID $_.id}        
            write-host @"
Siblings: $($siblings.count)
Websites Mentioned: $($mentionedWebsites.count)
Articles Mentioned: $($mentionedArticles.count)
Assets Mentioned: $($mentionedAssets.count)
"@
        }
    }
    if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $false} catch {}}

}

function New-HuduAddress {
    param([Parameter(Mandatory)][object]$Input)

    # Parse JSON strings; pass through objects
    $o = if ($Input -is [string]) { try { $Input | ConvertFrom-Json } catch { $null } } else { $Input }
    if (-not $o) { return $null }

    # Helper to grab the first present alias
    $first = {
        param($obj, [string[]]$names)
        foreach ($n in $names) { if ($obj.PSObject.Properties.Name -contains $n) { return $obj.$n } }
        return $null
    }

    $addr1 = & $first $o @('address_line_1','address1','address_1','line1','street','street1','address')
    $addr2 = & $first $o @('address_line_2','address2','address_2','line2','street2')
    $city           = & $first $o @('city','town')
    $state          = & $first $o @('state','province','region')
    $zip            = & $first $o @('zip','zipcode','postal','postal_code')
    $cntry   = & $first $o @('country_name','country')
    if ($addr1 -or $addr2 -or $city -or $state -or $zip -or $cntry) {
    $NewAddress = [ordered]@{
        address_line_1 = $addr1
        city           = $city
        state          = $state
        zip            = $zip
        country_name   = $cntry
    }
    if ($addr2) { $NewAddress['address_line_2'] = $addr2 }
    return $NewAddress
    } else {return $null}
}

function Resolve-LocationForCompany {
  param(
    [Parameter(Mandatory)][int]$CompanyId,
    [Parameter(Mandatory)]$Row,
    [Parameter(Mandatory)]$AllHuduLocations,
    [string[]]$Hints
  )

  # If $Hints can be null at call-time, set a safe default here (avoid default param expr that depends on external vars)
  if (-not $Hints) { $Hints = @('location','branch','office','site','building') }

  $candKeys = @()
  foreach ($prop in $Row.PSObject.Properties) {
    $propName = $prop.Name
    if ($Hints.Where({ param($h) (Test-Fuzzy $propName $h) }, 'First')) {
      $candKeys += $propName
    }
  }
  $candKeys = $candKeys | Sort-Object -Unique

  $candVals = @()
  foreach ($k in $candKeys) {
    $v = $Row.$k
    if ($null -ne $v -and "$v".Trim()) { $candVals += "$v" }
  }
  if (-not $candVals) { return $null }

  $companyLocs = $AllHuduLocations | Where-Object { $_.company_id -eq $CompanyId }
  foreach ($cv in $candVals) {
    $hit = $companyLocs | Where-Object { test-equiv -A $_.name -B $cv } | Select-Object -First 1
    if ($hit) { return $hit }
  }
  return $null
}
function Get-ListItemFuzzy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][int]$ListId,
        [double]$MinSimilarity = 0.85   # tweak as needed
    )

    if ([string]::IsNullOrWhiteSpace($Source)) { return $null }

    $list = Get-HuduLists -Id $ListId
    if (-not $list -or -not $list.list_items) { return $null }

    $sNorm = Normalize-Text $Source

    $bestItem  = $null
    $bestScore = -1.0

    foreach ($item in $list.list_items) {
        $name = [string]$item.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $nNorm = Normalize-Text $name

        $score = if ($nNorm -eq $sNorm) { 1.0 } else { Get-Similarity $name $Source }
        if ($nNorm.StartsWith($sNorm) -or $sNorm.StartsWith($nNorm)) {
            $score = [Math]::Min(1.0, $score + 0.02)
        }

        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestItem  = $item
        }
    }

    if ($bestScore -lt $MinSimilarity) { return $null }
    return $bestItem
}

function Get-UniqueHuduListName {
  param([Parameter(Mandatory)][string]$BaseName,[bool]$allowReuse=$false)

  $name = $BaseName.Trim()
  $i = 0
  while ($true) {
    $existing = Get-HuduLists -name $name
    if (-not $existing) { return $name }
    if ($existing -and $true -eq $allowReuse) {return $existing}
    $i++
    $name = "{0}-{1}" -f $BaseName.Trim(), $i
  }
}

function Get-HuduLayoutLike {
  param ([array]$LabelSet)

  foreach ($layout in $(get-huduassetlayouts)){
    foreach ($Label in $LabelSet){
      if ($true -eq $(Test-Equiv -A $locationLabel -$layout.name)){
        return $layout
      }
    }
  }
  Write-Host "No location layout found. Ensure your location layout name is in LocationLayoutNames array ($LocationLayoutNames)"
  return $null
}

function Ensure-HuduListItemByName {
    param(
        [Parameter(Mandatory)][int]$ListId,
        [Parameter(Mandatory)][string]$Name,
        [hashtable]$listNameExistsByListId
    )

    $nameTrim = $Name.Trim()
    $needle = $nameTrim.ToLowerInvariant()

    if (-not $listNameExistsByListId.ContainsKey($ListId)) {
        Refresh-ListCache
    }

    $map = $listNameExistsByListId[$ListId]
    if ($map -and $map.ContainsKey($needle)) {
        return $map[$needle]  # return canonical name as stored
    }

    # Add item to list
    $list = Get-HuduLists -Id $ListId
    $listName = $list.name

    $items = @()
    foreach ($existing in ($list.list_items ?? @())) {
        $items += @{ id = [int]$existing.id; name = [string]$existing.name }
    }
    $items += @{ name = $nameTrim }

    $null = Set-HuduList -Id $ListId -Name $listName -ListItems $items

    # refresh cache and return
    $listNameExistsByListId = Refresh-ListCache
    $map = $listNameExistsByListId[$ListId]
    if ($map.ContainsKey($needle)) { return $map[$needle] }

    throw "Failed to add/list item '$Name' to list $ListId"
}
function Refresh-ListCache {
    $listNameExistsByListId = @{}
    foreach ($l in Get-HuduLists) {
        $lid = [int]$l.id
        $map = @{}
        foreach ($it in ($l.list_items ?? @())) {
            if ($it.name) {
                $map[$it.name.ToString().Trim().ToLowerInvariant()] = [string]$it.name
            }
        }
        $listNameExistsByListId[$lid] = $map
    }
    return $listNameExistsByListId
}

function normalize-companyName {
    param([string]$Text)

    ($Text `
        -replace '(?i)\binc\b', '' `
        -replace '[\.,]', '' `
        -replace '\s+', ' '
    ).Trim()
}
function Get-HuduCompanyFromName {
    # use index first. Then existing list. Then API call.
    param (
        [Parameter(Mandatory = $true)]
        [string]$CompanyName,
        [array]$HuduCompanies,
        [bool]$includenicknames = $false,
        [array]$existingIndex = @(),
        [bool]$deepCompanySearch = $false
    )
    if ([string]::IsNullOrWhiteSpace($CompanyName)) { return $null }

        $normalizedCompanyName = normalize-companyName -Text $CompanyName
    # matched first
    $matchedCompany = $null
    if ($deepCompanySearch -eq $true){
        $matchedCompany = get-huducompanies | Where-Object {$(normalize-companyName -Text $_.name) -ieq (normalize-companyName -Text $normalizedCompanyName)} | Select-Object -First 1
    }
    if ($existingIndex -ne $null -and $existingIndex.count -gt 0 -and $matchedCompany -eq $null){
        $matchedCompany = $matchedCompany ?? $existingIndex | where-object {
            ($_.CompanyName -ieq $CompanyName) -or ($_.HuduCompany.name -ieq $CompanyName) -or
            ($normalizedCompanyName -ieq (normalize-companyName -Text $_.CompanyName)) -or ($normalizedCompanyName -ieq (normalize-companyName -Text $_.HuduCompany.name)) -or
            ($normalizedCompanyName -icontains (normalize-companyName -Text $_.CompanyName)) -or ($normalizedCompanyName -icontains (normalize-companyName -Text $_.HuduCompany.name)) -or
            [bool]$(test-equiv -A $_.CompanyName -B $CompanyName) } | Select-Object -First 1
        if ($includenicknames){
            $matchedCompany = $matchedCompany ?? $existingIndex | where-object {
                (-not [string]::IsNullOrWhiteSpace($_.HuduCompany.nickname)) -and (
                    ($_.HuduCompany.nickname -ieq $CompanyName) -or
                    [bool]$(test-equiv -A $_.HuduObject.nickname -B $CompanyName))
            } | Select-Object -First 1
        }   
    }
    if ($null -ne $matchedCompany){
      $matchedCompany = $matchedCompany.HuduCompany ?? $matchedCompany
      write-host "matched company using prematched companies: $($matchedCompany.name)"
      return $matchedCompany
    }    

    # then existing list
    $matchedCompany = $matchedCompany ?? $HuduCompanies | where-object {
            ($_.name -ieq $CompanyName) -or
            [bool]$(test-equiv -A $_.name -B $CompanyName)`
        } | Select-Object -First 1

    if ($true -eq $includenicknames){
        $matchedCompany =$matchedCompany ?? $HuduCompanies | where-object {
                ($_.nickname -ieq $CompanyName) -or
                [bool]$(test-equiv -A $_.nickname -B $CompanyName)`
            } | Select-Object -First 1
    }
    if ($null -ne $matchedCompany){
      $matchedCompany = $matchedCompany.HuduCompany ?? $matchedCompany
      write-host "matched company using companies array: $($matchedCompany.name)"
      return $matchedCompany
    }


    # finally API call
    if ($deepCompanySearch -eq $false){return $matchedCompany}

    $matchedCompany = $matchedCompany ?? $(Get-HuduCompanies -Name $CompanyName | select-object -first 1)
    if ($null -eq $matchedCompany){
          $matchedCompany = $matchedCompany ?? $(Get-HuduCompanies) | where-object {
            ($_.name -ieq $CompanyName) -or
            [bool]$(test-equiv -A $_.name -B $CompanyName) -or 
            ($normalizedCompanyName -ieq (normalize-companyName -Text $_.name))  -or
            ($normalizedCompanyName -icontains (normalize-companyName -Text $_.name)) 
        } | Select-Object -First 1
    }
    if ($null -ne $matchedCompany){
      write-host "matched company using API call: $($matchedCompany.name)"
      $matchedCompany = $matchedCompany.HuduCompany ?? $matchedCompany
      return $matchedCompany
    }
    $matchedCompany = $matchedCompany.HuduCompany ?? $matchedCompany
    return $matchedCompany
}

function Get-HuduFieldValue {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][object]$Asset,
    [Parameter(Mandatory)][string[]]$Labels
  )
  $labelsLC = $Labels | ForEach-Object { $_.ToLower() }
  $Asset.fields |
    Where-Object { $_.label -and $labelsLC -contains ([string]$_.label).ToLower() } |
    Select-Object -First 1 -ExpandProperty value
}

function Get-HuduAssetFromName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [int]$AssetLayoutId,
        [array]$Assets
    )
    if ([string]::IsNullOrWhiteSpace($Name) -or -not $AssetLayoutId -or $AssetLayoutId -lt 1) { return $null }
    $matchedAsset = $null
    $matchedAsset = $Assets | where-object {
            ($_.name -ieq $Name) -or
            [bool]$(test-equiv -A $_.name -B $Name)`
        } | Select-Object -First 1
    $matchedAsset = $matchedAsset ?? 
        $(Get-HuduAssets -AssetLayoutId $AssetLayoutId -Name $CompanyName) ?? 
         (get-huduassets -AssetLayoutId $AssetLayoutId | where-object {[bool]$(test-equiv -A $_.name -B $Name)} | select-object -first 1)
    return $matchedCompany
}


