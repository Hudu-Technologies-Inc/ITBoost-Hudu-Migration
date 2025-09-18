
## constants
$FIELD_SYNONYMS = @(
  @('name','full name','contact name','person'),
  @('first name','firstname','given name','forename','nombre','prénom','vorname'),
  @('last name','lastname','family name','surname','apellido','nom de famille','nachname'),
  @('title','job title','role','position','puesto','cargo'),
  @('department','dept','division','area','team'),
  @('email','e-mail','mail','email address','correo','adresse e-mail'),
  @('phone','telephone','tel','direct','office','work','main','primary phone','did','mobile','cell','cell phone','mobile phone','handy','gsm'),
  @('preferred communication','preferred contact','contact method','pref comms','pref contact'),
  @('gender','sex'),
  @('status','state','stage','relationship','owner','active','inactive'),
  @('workstation','computer','pc','machine','host'),
  @('ip','ip address','primary co mputer ip','workstation ip'),
  @('notes','note','remarks','comments'),
  @('location','branch','office','site','building','sucursal','standort','filiale','vestiging','sede'),
  @('address 1','address1','addr1','street','street address','line 1','address line 1'),
  @('address 2','address2','addr2','line 2','address line 2','apt','suite','unit'),
  @('city','town','locality','municipality','ciudad','ville','ort'),
  @('postal code','zipcode','zip','postcode','cp','code postal','plz','codigo postal'),
  @('region','state','province','county','departement','bundesland','estado','provincia'),
  @('country','nation','pais','land','paese'),
  @('phone','telephone','tel','telefono','telefone','telefon'),
  @('fax'),
  @('notes','note','remarks','observations','comentarios','bemerkungen')
)

function Normalize-Text {
    param([string]$s)
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    $s = $s.Trim().ToLowerInvariant()
    $s = [regex]::Replace($s, '[\s_-]+', ' ')  # "primary_email" -> "primary email"
    # strip diacritics (prénom -> prenom)
    $formD = $s.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $formD.ToCharArray()){
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne
            [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    ($sb.ToString()).Normalize([System.Text.NormalizationForm]::FormC)
}

function Test-LabelEquivalent {
    param([string]$A, [string]$B)
    $a = Normalize-Text $A; $b = Normalize-Text $B
    if (-not $a -or -not $b) { return $false }
    if ($a -eq $b) { return $true }
    $reA = "(^| )$([regex]::Escape($a))( |$)"
    $reB = "(^| )$([regex]::Escape($b))( |$)"
    if ($b -match $reA -or $a -match $reB) { return $true }
    if ($a.Replace(' ', '') -eq $b.Replace(' ', '')) { return $true }
    return $false
}

function Get-Similarity {
    param([string]$A, [string]$B)

    $a = [string](Normalize-Text $A)
    $b = [string](Normalize-Text $B)
    if ([string]::IsNullOrEmpty($a) -and [string]::IsNullOrEmpty($b)) { return 1.0 }
    if ([string]::IsNullOrEmpty($a) -or  [string]::IsNullOrEmpty($b))  { return 0.0 }

    $n = [int]$a.Length
    $m = [int]$b.Length
    if ($n -eq 0) { return [double]($m -eq 0) }
    if ($m -eq 0) { return 0.0 }

    $d = New-Object 'int[,]' ($n+1), ($m+1)
    for ($i = 0; $i -le $n; $i++) { $d[$i,0] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[0,$j] = $j }

    for ($i = 1; $i -le $n; $i++) {
        $im1 = ([int]$i) - 1
        $ai  = $a[$im1]
        for ($j = 1; $j -le $m; $j++) {
            $jm1 = ([int]$j) - 1
            $cost = if ($ai -eq $b[$jm1]) { 0 } else { 1 }

            $del = [int]$d[$i,  $j]   + 1
            $ins = [int]$d[$i,  $jm1] + 1
            $sub = [int]$d[$im1,$jm1] + $cost

            $d[$i,$j] = [Math]::Min($del, [Math]::Min($ins, $sub))
        }
    }

    $dist   = [double]$d[$n,$m]
    $maxLen = [double][Math]::Max($n,$m)
    return 1.0 - ($dist / $maxLen)
}

function Find-RowValueByLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetLabel,
        [Parameter(Mandatory)][psobject]$Row,
        [object[]]$FieldSynonyms,   # full sets (e.g. $FIELD_SYNONYMS)
        [string[]]$SynonymBag,      # flat bag (e.g. from Get-FieldSynonymsSimple)
        [double]$MinSimilarity = 0.82,
        [switch]$ReturnCandidate
    )

    if (-not $Row) { return $null }

    # Build synonym bag without pipelines
    $bag = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    if ($SynonymBag) {
        foreach ($s in $SynonymBag) { if ($s) { [void]$bag.Add([string]$s) } }
    } elseif ($FieldSynonyms) {
        foreach ($set in $FieldSynonyms) {
            if (-not $set) { continue }
            $setHasMatch = $false
            foreach ($term in $set) {
                if (Test-LabelEquivalent $term $TargetLabel) { $setHasMatch = $true; break }
            }
            if ($setHasMatch) {
                foreach ($t in $set) { if ($t) { [void]$bag.Add([string]$t) } }
            }
        }
    }

    # Support hashtable rows
    $rowObj = if ($Row -is [hashtable]) { [pscustomobject]$Row } else { $Row }

    # Collect non-empty properties, no pipelines
    $props = @()
    foreach ($p in $rowObj.PSObject.Properties) {
        $v = $p.Value
        if ($null -eq $v) { continue }
        if ($v -isnot [string] -and $v -is [System.Collections.IEnumerable]) {
            if (@($v).Count -eq 0) { continue }
        } elseif ("$v".Trim() -eq '') {
            continue
        }
        $props += $p
    }

    # Score candidates, no pipelines in conditionals
    $candidates = @()
    foreach ($p in $props) {
        $label  = "$($p.Name)"
        $val    = $p.Value
        $score  = 0.0
        $reason = ''

        if (Test-LabelEquivalent $label $TargetLabel) {
            $score = 1.00; $reason = 'exact/equivalent'
        } else {
            $synHit = $false
            if ($bag.Count -gt 0) {
                foreach ($s in $bag) {
                    if (Test-LabelEquivalent $s $label) { $synHit = $true; break }
                }
            }
            if ($synHit) {
                $score = 0.95; $reason = 'synonym'
            } else {
                $sim = Get-Similarity $TargetLabel $label
                foreach ($s in $bag) { $sim = [Math]::Max($sim, (Get-Similarity $s $label)) }
                if ($sim -ge $MinSimilarity) { $score = 0.8 * $sim; $reason = 'fuzzy' }
            }
        }

        if ($score -gt 0) {
            $candidates += [pscustomobject]@{
                Property = $label
                Value    = $val
                Score    = [math]::Round($score, 4)
                Reason   = $reason
            }
        }
    }

    if (-not $candidates -or $candidates.Count -eq 0) { return $null }

    # Sort without pipeline
    $candidates = @($candidates)  # ensure array
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        for ($j = $i + 1; $j -lt $candidates.Count; $j++) {
            if ($candidates[$j].Score -gt $candidates[$i].Score) {
                $tmp = $candidates[$i]; $candidates[$i] = $candidates[$j]; $candidates[$j] = $tmp
            }
        }
    }

    if ($ReturnCandidate) { return $candidates[0] }
    return $candidates[0].Value
}

## methods
function Get-NormalizedVariants {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    $base = [regex]::Replace($Text.Trim(), '[\s_-]+', ' ').ToLowerInvariant()

    $variants = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $null = $variants.Add($base)
    $null = $variants.Add($base.Replace(' ', ''))  # no-spaces
    $null = $variants.Add($base.Replace(' ', '-')) # dashes
    $null = $variants.Add($base.Replace(' ', '_')) # underscores
    return $variants
}

function Test-NameEquivalent {
    param([string]$A, [string]$B)

    $va = Get-NormalizedVariants $A
    $vb = Get-NormalizedVariants $B

    $setB = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $vb.ForEach({ [void]$setB.Add($_) })

    foreach ($x in $va) {
        if ($setB.Contains($x)) {
            return $true
        }
    }
    return $false
}

function Get-NormalizedWebsiteHost {
    param(
        [Parameter(Mandatory)][string]$website
    )
    if ([string]::IsNullOrWhiteSpace($website)) { return $null }

    $s = $website.Trim()
    if ($s -notmatch '^\w+://') { $s = "http://$s" }

    try {
        $uri = [Uri]$s
        $hostname = $uri.IdnHost
        if ($hostname.StartsWith('[') -and $hostname.EndsWith(']')) { $hostname = $hostname.Trim('[',']') } # IPv6
        $hostname = $hostname.TrimEnd('.').ToLowerInvariant()
        return $hostname
    }
    catch {
        $t = $website.Trim()
        $t = $t -replace '^\w+://',''
        $t = $t -replace '^[^@/]*@',''
        $t = $t.TrimStart('[').TrimEnd(']')
        $t = $t -replace '[:/].*$',''
        return $t.TrimEnd('.').ToLowerInvariant()
    }
}
function Test-IsLocationLayoutName {
  param([string]$Name)
  foreach ($v in (Get-NormalizedVariants -Text $Name)) {
    if ($locationSet.Contains($v)) { return $true }
  }
  return $false
}

$locationSeed = @(
  'Location','Locations','Building','Branch',
  'Sucursal','Ubicación','Succursale','Standort','Filiale','Vestiging'
)

$PossibleLocationNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($term in $locationSeed) {
  foreach ($v in (Get-NormalizedVariants -Text $term)) {
    $null = $PossibleLocationNames.Add($v)
  }
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

function Get-NeedlePresentInHaystack {
    <#
    .SYNOPSIS
    Returns $true if $Needle occurs in $Haystack (case-insensitive).
    #>
    param(
        [Parameter(Mandatory)][string]$Haystack,
        [Parameter(Mandatory)][string]$Needle
    )
    if ($null -eq $Haystack -or $null -eq $Needle) { return $false }
    return ($Haystack.IndexOf($Needle, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Get-NotesFromArray {
    param ([array]$notesInput=@())
        $notes ="Migrated from ITBoost"
        if ($notesInput -and $notesInput.count -gt 0){
            foreach ($noteentry in $notesInput){
                $notes="$notes`n$noteentry"
            }
        }
        return $notes
}
function Normalize-Label([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  $t = $s.Trim().ToLowerInvariant()
  $t = $t.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}',''   # strip accents
  $t = [regex]::Replace($t, '[\s\-_]+', ' ')                                # collapse separators
  return $t
}
function Test-Fuzzy([string]$a,[string]$b) {
  $a = Normalize-Label $a; $b = Normalize-Label $b
  if ($a -eq $b) { return $true }
  if ($a -and $b -and ($a -like "*$b*" -or $b -like "*$a*")) { return $true }
  return $false
}
function Find-BestSourceKey($row, [string]$targetLabel, [string[]]$synonyms) {
  $targetN = Normalize-Label $targetLabel
  $cands = foreach ($p in $row.PSObject.Properties) {
    $pn = Normalize-Label $p.Name
    if ([string]::IsNullOrWhiteSpace($pn)) { continue }
    $score = 0
    if ($pn -eq $targetN) { $score = 100 }
    elseif ($synonyms | Where-Object { Test-Fuzzy $pn $_ }) { $score = 90 }
    elseif (Test-Fuzzy $pn $targetN) { $score = 80 }
    $val = $p.Value
    $isEmpty = ($null -eq $val) -or (($val -is [string]) -and [string]::IsNullOrWhiteSpace($val))
    if ($isEmpty) { $score -= 50 }
    if ($score -gt 0) { [pscustomobject]@{Name=$p.Name; Score=$score} }
  }
  $cands | Sort-Object Score -Descending | Select-Object -First 1 -ExpandProperty Name
}

function Get-EmailsFromRow($row) {
  $rx='[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'
  $vals = foreach ($p in $row.PSObject.Properties) {
    if (Normalize-Label $p.Name -match 'email|e mail|mail') { if ($p.Value -is [array]) { $p.Value -join "`n" } else { "$($p.Value)" } }
  }
  if (-not $vals) { return $null }
  (($vals -join "`n") | Select-String -AllMatches -Pattern $rx).Matches.Value | Sort-Object -Unique
}
function Get-PhonesFromRow($row) {
  $rx='(?:(?:\+|00)\d{1,3}[\s\-\.]*)?(?:\(?\d{2,4}\)?[\s\-\.]*){2,4}\d{2,6}(?:\s*(?:x|ext\.?|#)\s*\d{1,6})?'
  $vals = foreach ($p in $row.PSObject.Properties) {
    if (Normalize-Label $p.Name -match 'phone|tel|mobile|cell|direct|office|work') { if ($p.Value -is [array]) { $p.Value -join "`n" } else { "$($p.Value)" } }
  }
  if (-not $vals) { return $null }
  (($vals -join "`n") | Select-String -AllMatches -Pattern $rx).Matches.Value |
    ForEach-Object { ($_ -replace '[^\d\+xX#]','').Trim() } |
    Sort-Object -Unique
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
    $hit = $companyLocs | Where-Object { Test-NameEquivalent -A $_.name -B $cv } | Select-Object -First 1
    if ($hit) { return $hit }
  }
  return $null
}
function Get-ListItemFuzzy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][int]$ListId,
        [double]$MinSimilarity = 0.65   # tweak as needed
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

function Get-SynonymBag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Targets,         # e.g. 'email' or 'primary_phone'
        [Parameter(Mandatory)][object[]] $SynonymSets,    # e.g. $FIELD_SYNONYMS
        [switch]$IncludeVariants                          # also include - , _ , nospace variants
    )
    $targetVariants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($t in $Targets) {
        (Get-NormalizedVariants $t) | ForEach-Object { [void]$targetVariants.Add($_) }
    }
    $bag = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($set in $SynonymSets) {
        if (-not $set) { continue }

        $setMatches = $false
        foreach ($term in $set) {
            foreach ($v in (Get-NormalizedVariants $term)) {
                if ($targetVariants.Contains($v)) { $setMatches = $true; break }
            }
            if ($setMatches) { break }
        }

        if ($setMatches) {
            foreach ($term in $set) {
                (Get-NormalizedVariants $term) | ForEach-Object { [void]$bag.Add($_) }
            }
        }
    }

    ,@($bag)
}
function Get-FieldSynonymsSimple {
    param([Parameter(Mandatory)][string]$TargetLabel, [switch]$IncludeVariants)
    Get-SynonymBag -Targets @($TargetLabel) -SynonymSets $FIELD_SYNONYMS -IncludeVariants:$IncludeVariants
}


function Build-FieldsFromRow {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][array]$LayoutFields,
    [Parameter(Mandatory)][object]$Row,
    [int]$companyId
  )
  process {
    if (-not $Row) { return @() }

    $out = @()
    foreach ($field in $LayoutFields) {
      $label = $field.label
      if ([string]::IsNullOrWhiteSpace($label)) { continue }
    
      if ($field.field_type -eq "AssetTag"){
        if (-not $field.linkable_id -or $field.linkable_id -lt 1){continue}
            $layoutForLinking = Get-HuduAssetLayouts -id $field.linkable_id
            $possiblyLinkedAssets=Get-HuduAssets -CompanyId $companyId -id $field.linkable_id
            $bag = Get-FieldSynonymsSimple -TargetLabel $layoutForLinking.name -IncludeVariants
            $val = Find-RowValueByLabel -TargetLabel $label -Row $Row -SynonymBag $bag
            $bestItem  = $null
            $bestScore = -1.0            
            if ($val){
                foreach ($asset in $possiblyLinkedAssets) {
                    $name = [string]$asset.name
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }
                    $nNorm = Normalize-Text $name
                    $score = if ($nNorm -eq $sNorm) { 1.0 } else { Get-Similarity $name $val }
                    if ($nNorm.StartsWith($sNorm) -or $sNorm.StartsWith($nNorm)) {
                        $score = [Math]::Min(1.0, $score + 0.02)
                    }
                    if ($score -gt $bestScore) {
                        $bestScore = $score
                        $bestItem  = $asset
                    }
                }
            }
            if ($bestItem -and $bestitem.id){ $val = $bestItem.id } else {continue}
            Write-Host "Matched Asset Tag field $label to $($layoutForLinking.name) asset $($bestItem.name) with score of $($bestScore)"
      }

      if ($field.field_type -eq "AddressData"){
        $tmpVal=Build-FieldsFromRow -Row $Row -LayoutFields @(
            @{label = "address_line_1"},
            @{label = "address_line_2"},
            @{label = "city"},
            @{label = "state"},
            @{label = "zip"},
            @{label = "country_name"}
          )
          $address=@{}
          foreach ($val in $TMPVAL | where-object {-not [string]::IsNullOrWhiteSpace($_.Value)}){
              $address[$val.Name]=$val.Value
          }
          $val = @{Address = $address}
      }      

      $bag = Get-FieldSynonymsSimple -TargetLabel $label -IncludeVariants
      $val = Find-RowValueByLabel -TargetLabel $label -Row $Row -SynonymBag $bag
      if ($field.field_type -eq "ListSelect" -and $null -ne $field.list_id){
        $val = $(Get-ListItemFuzzy -listid $field.list_id -source $val).id
      }


      if ($null -ne $val -and "$val".Trim() -ne '') { $out += @{ $label = $val } }
    }
    return $out
  }
}
