
## constants
$FIELD_SYNONYMS = @(
  @('id','identifier','unique id','unique identifier','uuid')
  @('name','full name','contact name','person','names'),
  @('first name','firstname','given name','forename','nombre','prénom','vorname'),
  @('last name','lastname','family name','surname','apellido','nom de famille','nachname'),
  @('title','job title','role','position','puesto','cargo'),
  @('department','dept','division','area','team'),
  @('email','e-mail','mail','email address','correo','correo electrónico','adresse e-mail','emails'),
  @('phone','phone number','telephone','telephone number','tel',
    'office phone','work phone','main phone','primary phone','direct phone',
    'mobile','cell','cell phone','mobile phone',"phones",'phone mumbers','telephones',
    'handy','gsm','teléfono','telefone','telefon'),
  @('contact preference','contact type','preferred communication','preferred contact','contact method','pref comms','pref contact'),
  @('gender','sex'),
  @('password','passwords','pass','secret pass','secret','secret password')
  @('status','stage','relationship','owner','active','inactive'),
  @('computer','workstation','pc','machine','host'),
  @('ip address','ip','workstation ip','primary computer ip'),
  @('notes','note','remarks','comments','observations','comentarios','bemerkungen'),
  @('location','branch','office location','site','building','sucursal','standort','filiale','vestiging','sede'),
  @('address line 1','address 1','address_1','address1','addr1','street','street address','line 1'),
  @('address line 2','address 2','address_2','address2','addr2','suite','unit'),
  @('city','town','locality','municipality','ciudad','ville','ort','gemeente'),
  @('postal code','zip code','zipcode','zip','postcode','cp','code postal','plz','código postal','cap', 'postal code', 'post'),
  @('region','state','province','county','departement','bundesland','estado','provincia'),
  @('country','country name','nation','país','pais','land','paese'),
  @('fax','fax number')
  @('important','notice','warning','vip','very important person')
)
$truthy = '(?ix)\b(?:y|yes|yeah|yep|true|t|on|ok|okay|enable|enabled|active)\b|(?<!\d)1(?!\d)'
$falsy  = '(?ix)\b(?:n|no|nope|false|f|off|disable|disabled|inactive)\b|(?<!\d)0(?!\d)'

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

# Build a small index once (variants per set for fast overlap checks)
function New-SynonymIndex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$SynonymSets)

    $idx = @()
    for ($i = 0; $i -lt $SynonymSets.Count; $i++) {
        $set = @($SynonymSets[$i])
        if ($set.Count -eq 0) { continue }

        $canon = [string]$set[0]  # canonical = first item
        $vars  = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

        # union of normalized variants for every term in the set
        foreach ($t in $set) {
            foreach ($v in (Get-NormalizedVariants $t)) { [void]$vars.Add($v) }
        }

        $idx += [pscustomobject]@{
            Index    = $i
            Canon    = $canon
            Terms    = $set
            Variants = $vars
        }
    }
    return ,$idx
}
function Get-SimilaritySafe { param([string]$A,[string]$B)
    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return 0.0 }
    Get-Similarity $A $B
}

function Get-BestSynonymSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][object[]]$SynonymSets,
        [object[]]$Index,              # optional: pass result of New-SynonymIndex
        [double]$MinScore = 1.0,       # require at least this much evidence
        [double]$MinGap   = 0.25,      # top must beat #2 by this margin
        [switch]$ReturnObject          # return full object (Index/Canon/Terms/Score)
    )

    if (-not $Index) { $Index = New-SynonymIndex $SynonymSets }

    $labelNorm = Normalize-Text $Label
    $labelVars = Get-NormalizedVariants $Label

    $cands = @()
    foreach ($item in $Index) {
        # 1) fast variant overlap
        $overlap = 0
        foreach ($v in $labelVars) { if ($item.Variants.Contains($v)) { $overlap++ } }

        # 2) whole-word equivalence count
        $eqCount = 0
        foreach ($t in $item.Terms) { if (Test-LabelEquivalent $Label $t) { $eqCount++ } }

        # 3) small fuzzy tie-breaker (max similarity across terms)
        $maxSim = 0.0
        foreach ($t in $item.Terms) {
            $s = Get-Similarity $Label $t
            if ($s -gt $maxSim) { $maxSim = $s }
        }

        # Weighted score: counts dominate; fuzzy cannot overpower counts
        $score = (3.0 * $overlap) + (1.5 * $eqCount) + (0.5 * $maxSim)
        if ($score -gt 0) {
            $cands += [pscustomobject]@{
                Index  = $item.Index
                Canon  = $item.Canon
                Terms  = $item.Terms
                Score  = [Math]::Round($score, 4)
                Parts  = [pscustomobject]@{Overlap=$overlap; Eq=$eqCount; Fuzzy=[Math]::Round($maxSim,4)}
            }
        }
    }

    if ($cands.Count -eq 0) { return ($ReturnObject ? $null : '') }

    # Sort (no pipeline inside conditionals)
    for ($i=0; $i -lt $cands.Count; $i++) {
        for ($j=$i+1; $j -lt $cands.Count; $j++) {
            if ($cands[$j].Score -gt $cands[$i].Score -or
               (($cands[$j].Score -eq $cands[$i].Score) -and ($cands[$j].Index -lt $cands[$i].Index))) {
                $tmp=$cands[$i]; $cands[$i]=$cands[$j]; $cands[$j]=$tmp
            }
        }
    }

    $top = $cands[0]
    if ($top.Score -lt $MinScore) { return ($ReturnObject ? $null : '') }
    if ($cands.Count -gt 1) {
        $gap = $top.Score - $cands[1].Score
        if ($gap -lt $MinGap) { return ($ReturnObject ? $null : '') }
    }

    return ($ReturnObject ? $top : (Normalize-Text $top.Canon))
}
function Test-IsDomainOrIPv4 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline=$true)] $InputObject
    )
    process {
        $s = if ($null -eq $InputObject) { '' } else { "$InputObject" }
        $s = $s.Trim()
        if ($s.Length -eq 0) { return $false }

        # strip scheme
        $s = $s -replace '^[A-Za-z][A-Za-z0-9+.\-]*://',''

        # strip path/query/fragment
        $s = $s -replace '[/?#].*$',''

        # trim trailing dot on FQDN
        if ($s.EndsWith('.')) { $s = $s.TrimEnd('.') }
        if ($s.Length -eq 0) { return $false }

        # IPv4[:port]
        $m = [regex]::Match($s,'^(?<ip>(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)(?:\.(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)){3})(?::(?<port>\d{1,5}))?$')
        if ($m.Success) {
            $p = $m.Groups['port'].Value
            if ($p) { $port = [int]$p; if ($port -lt 0 -or $port -gt 65535) { return $false } }
            return $true
        }

        # domain[:port]  (labels <=63 chars, total <=253, TLD >=2)
        $m = [regex]::Match($s,'^(?<host>(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,})(?::(?<port>\d{1,5}))?$')
        if ($m.Success) {
            $p = $m.Groups['port'].Value
            if ($p) { $port = [int]$p; if ($port -lt 0 -or $port -gt 65535) { return $false } }
            return $true
        }

        # localhost[:port]
        $m = [regex]::Match($s,'^(localhost)(?::(?<port>\d{1,5}))?$')
        if ($m.Success) {
            $p = $m.Groups['port'].Value
            if ($p) { $port = [int]$p; if ($port -lt 0 -or $port -gt 65535) { return $false } }
            return $true
        }

        return $false
    }
}
function Get-BestSynonymSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][object[]]$SynonymSets,
        [object[]]$Index,              # optional: pass result of New-SynonymIndex
        [double]$MinScore = 1.0,       # require at least this much evidence
        [double]$MinGap   = 0.25,      # top must beat #2 by this margin
        [switch]$ReturnObject          # return full object (Index/Canon/Terms/Score)
    )

    if (-not $Index) { $Index = New-SynonymIndex $SynonymSets }

    $labelNorm = Normalize-Text $Label
    $labelVars = Get-NormalizedVariants $Label

    $cands = @()
    foreach ($item in $Index) {
        # 1) fast variant overlap
        $overlap = 0
        foreach ($v in $labelVars) { if ($item.Variants.Contains($v)) { $overlap++ } }

        # 2) whole-word equivalence count
        $eqCount = 0
        foreach ($t in $item.Terms) { if (Test-LabelEquivalent $Label $t) { $eqCount++ } }

        # 3) small fuzzy tie-breaker (max similarity across terms)
        $maxSim = 0.0
        foreach ($t in $item.Terms) {
            $s = Get-Similarity $Label $t
            if ($s -gt $maxSim) { $maxSim = $s }
        }

        # Weighted score: counts dominate; fuzzy cannot overpower counts
        $score = (3.0 * $overlap) + (1.5 * $eqCount) + (0.5 * $maxSim)
        if ($score -gt 0) {
            $cands += [pscustomobject]@{
                Index  = $item.Index
                Canon  = $item.Canon
                Terms  = $item.Terms
                Score  = [Math]::Round($score, 4)
                Parts  = [pscustomobject]@{Overlap=$overlap; Eq=$eqCount; Fuzzy=[Math]::Round($maxSim,4)}
            }
        }
    }

    if ($cands.Count -eq 0) { return ($ReturnObject ? $null : '') }

    # Sort (no pipeline inside conditionals)
    for ($i=0; $i -lt $cands.Count; $i++) {
        for ($j=$i+1; $j -lt $cands.Count; $j++) {
            if ($cands[$j].Score -gt $cands[$i].Score -or
               (($cands[$j].Score -eq $cands[$i].Score) -and ($cands[$j].Index -lt $cands[$i].Index))) {
                $tmp=$cands[$i]; $cands[$i]=$cands[$j]; $cands[$j]=$tmp
            }
        }
    }

    $top = $cands[0]
    if ($top.Score -lt $MinScore) { return ($ReturnObject ? $null : '') }
    if ($cands.Count -gt 1) {
        $gap = $top.Score - $cands[1].Score
        if ($gap -lt $MinGap) { return ($ReturnObject ? $null : '') }
    }

    return ($ReturnObject ? $top : (Normalize-Text $top.Canon))
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

function Test-IsDigitsOnly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline=$true)]
        $InputObject,
        [switch]$AsciiOnly,
        [switch]$AllowEmpty
    )
    process {
        # If an array/collection comes in, evaluate each element
        if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
            foreach ($item in $InputObject) {
                Test-IsDigitsOnly -InputObject $item -AsciiOnly:$AsciiOnly -AllowEmpty:$AllowEmpty
            }
            return
        }

        $s = if ($null -eq $InputObject) { '' }
             elseif ($InputObject -is [string]) { $InputObject }
             else { "$InputObject" }

        $s = $s.Trim()
        if (-not $AllowEmpty -and $s.Length -eq 0) { $false; return }

        $pattern = if ($AsciiOnly) { '^[0-9]+$' } else { '^\p{Nd}+$' }
        $s -match $pattern
    }
}
function Test-LetterRatio {
    [CmdletBinding()]param(
        [Parameter(Mandatory,ValueFromPipeline=$true)]$InputObject,
        [switch]$AsciiOnly,           # else uses Unicode \p{L}
        [switch]$IgnoreWhitespace     # don't count spaces in the length
    )
    process {
        $s = if ($null -eq $InputObject) { '' } else { "$InputObject" }
        if ($IgnoreWhitespace) { $s = $s -replace '\s+', '' }
        if ($s.Length -eq 0) { return $false }
        $pat = if ($AsciiOnly) { '[A-Za-z]' } else { '\p{L}' }
        $letters = [regex]::Matches($s, $pat).Count
        return [double]$($letters / [double]$s.Length)
    }
}

function Test-IsHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline=$true)] $InputObject,
        [int]$MinTags = 1,            # how many tags must be present
        [switch]$RequirePaired,       # require at least one <tag>...</tag> (non-void)
        [switch]$DecodeEntities       # decode &lt;div&gt; first
    )
    process {
        # normalize to string
        $s = if ($null -eq $InputObject) { '' } else { "$InputObject" }
        if ($DecodeEntities) { $s = [System.Net.WebUtility]::HtmlDecode($s) }
        if ($s.Length -eq 0) { return $false }

        # quick root/doctype hit
        if ($s -match '(?is)<!DOCTYPE\s+html|<html\b') { return $true }

        # find tags
        $tagRegex = [regex]'(?is)<([a-z][a-z0-9]*)\b[^>]*>'
        $matches  = $tagRegex.Matches($s)
        if ($matches.Count -lt $MinTags) { return $false }
        if (-not $RequirePaired) { return $true }

        # require at least one non-void paired tag (or self-closing)
        $void = @('area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr')
        for ($i=0; $i -lt $matches.Count; $i++) {
            $name = $matches[$i].Groups[1].Value.ToLowerInvariant()
            if ($void -contains $name) { continue }
            if ($matches[$i].Value -match '/\s*>$') { return $true } # <tag />
            $closePattern = "(?is)</\s*$name\s*>"
            if ([regex]::IsMatch($s, $closePattern)) { return $true }
        }
        return $false
    }
}
function Find-RowValueByLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetLabel,
        [Parameter(Mandatory)][psobject]$Row,
        [object[]]$FieldSynonyms,   # full sets (e.g. $FIELD_SYNONYMS)
        [string[]]$SynonymBag,      # flat bag (e.g. from Get-FieldSynonymsSimple)
        [string]$fieldType,
        [double]$MinSimilarity = 1,
        [switch]$ReturnCandidate
    )

    if (-not $Row) { return $null }
    if ($fieldType -and $fieldType -eq "AssetTag"){return $null}



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
        # label scoring
        if (Test-LabelEquivalent $label $TargetLabel) {
            $score = 1.8; $reason = 'exact/equivalent'
        } else {
            $synHit = $false
            if ($bag.Count -gt 0) {
                foreach ($s in $bag) {
                    if (Test-LabelEquivalent $s $label) { $synHit = $true; break }
                }
            }
            if ($synHit) {
                $score = 1.4; $reason = 'synonym'
            } else {
                $sim = Get-Similarity $TargetLabel $label
                foreach ($s in $bag) { $sim = [Math]::Max($sim, (Get-Similarity $s $label)) }
                if ($sim -ge $MinSimilarity) { $score = 0.8 * $sim; $reason = 'fuzzy' }
            }
        }

        # field type scoring
        if ($fieldType -and $fieldType -eq "Number"){
            $score-=$($val | Test-LetterRatio -IgnoreWhitespace)
            if ($val | Test-IsDigitsOnly) { $score += 0.35 } 
            elseif (Test-MostlyDigits $val) { $score += 0.2 }
            else {$score -=0.35}
        }
        if ($fieldType -and $fieldType -eq "Phone"){
            if (Test-IsPhoneValue $val){$score+=0.7} else {$score-=0.7}
        }        
        if ($fieldType -and @("RichText","Heading","Embed") -contains $fieldType){
            if ($val | Test-IsHtml -MinTags 3){
                $score+=0.295
            } elseif ($val | Test-IsHtml -MinTags 2){
                $score+=0.275
            } elseif ($val | Test-IsHtml -MinTags 1){
                $score+=0.25
            } else {
                $score-=0.25
            }
        }
        if ($fieldType -eq "Website"){
            if ($val | Test-IsDomainOrIPv4) {$score+=0.195} else {$score-=0.195}
        }

        # label family + value scoring

        $family = Get-BestSynonymSet -Label $label -SynonymSets $FIELD_SYNONYMS
        switch ($family) {
            'contact preference' {
                if (Test-IsEmailValue $val) { $score -= 0.75 }
                if (Test-IsPhoneValue $val) { $score -= 0.65 }
                if (Test-MostlyDigits $val) { $score -= 0.65 }
                if ($val | Test-IsDigitsOnly) { $score -= 0.435 }
                foreach ($keyword in @("type","method")){
                    if ($label -ilike "*$keyword*"){ $score += ".135" }
                }
                $contactsynonyms = $FIELD_SYNONYMS | where-object {$_ -contains 'phone' -or $_ -contains 'email' -or $_ -contains 'sms'}
                foreach ($expectedvalue in $contactsynonyms){
                    if ($val -ilike "*$expectedvalue*"){ $score += ".425" }
                }                
            }            
            'email' {
                if (Test-IsEmailValue $val) { $score += 0.43 } else { $score -= 0.45 }
                foreach ($commonPhoneString in @("@",".")){
                    if (Get-NeedlePresentInHaystack -needle "@" -Haystack $val ) {$score += 0.24 } else { $score -= 0.24 }
                }
                if ($val | Test-IsDigitsOnly) { $score -= 0.4 }
            }
            'phone' {
                if (Test-IsPhoneValue $val) { $score += 0.33 } else { $score -= 0.35 }
                foreach ($commonPhoneString in @("(","ext",")","-")){
                    if (Get-NeedlePresentInHaystack -needle "(" -Haystack $val ) {$score += 0.125 }
                }
                if (Test-MostlyDigits $val) { $score += 0.25 }
                if (Test-IsEmailValue $val) { $score -= 0.46 }
                $score-= $($($val | Test-LetterRatio -IgnoreWhitespace)/1.25)
            }
            'title' {
                if (Test-MostlyDigits $val) { $score -= 0.55 }
                if ($val | Test-IsDigitsOnly) { $score -= 0.35 }
                if (Test-IsEmailValue $val) { $score -= 0.725 }
            }
            'notes' {
                $score += $($($val | Test-LetterRatio -IgnoreWhitespace)/2)
                $score += $($($val | Test-LetterRatio -IgnoreWhitespace)/2)
            }
            'postal code' {
                if ("$val".Trim().Length -lt 10){
                    $score+=0.1
                } else {$score-=0.1}
                if ("$val".Trim().Length -lt 7){
                    $score+=0.15
                } else {$score-=0.15}
                if ($val | Test-IsDigitsOnly) { $score += 0.25 }
                if ("$val".Trim().Length -eq 5){$score += 0.3}
            }            
            'important' {
                if ("$val".Tolower() -ilike $truthy -or "$val".Tolower() -ilike $falsy){
                    $score += 0.45
                }
            }            
            'first name' {
                if (Test-MostlyDigits $val) { $score -= 0.55 }
                if ($val | Test-IsDigitsOnly) { $score -= 0.35 }
                if (Test-IsEmailValue $val) { $score -= 0.46 }
                $score += $($($val | Test-LetterRatio -IgnoreWhitespace)/2)
            }
            'last name' {
                if (Test-MostlyDigits $val) { $score -= 0.55 }
                if ($val | Test-IsDigitsOnly) { $score -= 0.35 }
                if (Test-IsEmailValue $val) { $score -= 0.46 }
                $score += $($($val | Test-LetterRatio -IgnoreWhitespace)/2)
            }            
            'name' {
                if (Test-MostlyDigits $val) { $score -= 0.55 }
                if ($val | Test-IsDigitsOnly) { $score -= 0.35 }
                if (Test-IsEmailValue $val) { $score -= 0.46 }
                $score += $($($val | Test-LetterRatio -IgnoreWhitespace)/2)
            }
            default {
                if (Test-IsEmailValue $val) { $score -= 0.5 }
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
    $candidates | ConvertTo-json -depth 55 | out-file $(join-path $debug_folder "$($Row.id)-$($TargetLabel).json")

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

function Test-IsEmailValue([object]$v){
  if ($null -eq $v) { return $false }
  $s = "$v".Trim()
  return $s -match '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'
}
function Test-IsPhoneValue([object]$v){
  if ($null -eq $v) { return $false }
  $s = "$v"
  # relaxed phone: digits with optional +/x and separators
  $m = [regex]::Match($s,'(?:(?:\+|00)\d{1,3}[\s\-\.]*)?(?:\(?\d{2,4}\)?[\s\-\.]*){2,4}\d{2,6}(?:\s*(?:x|ext\.?|#)\s*\d{1,6})?')
  return $m.Success
}
function Test-MostlyDigits([object]$v){
  if ($null -eq $v) { return $false }
  $s = "$v".Trim()
  if ($s.Length -eq 0) { return $false }
  $digits = ($s -replace '\D','').Length
  return ($digits / [double]$s.Length) -ge 0.7
}
# map a target label to a canonical family (quick & simple)

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
    $chosenLabels = @()
    foreach ($field in $LayoutFields) {
      $label = $field.label
      if ([string]::IsNullOrWhiteSpace($label)) { continue }
    # special case assettag
      if ($field.field_type -eq "Email"){
        
        
      }

    #   if ($field.field_type -eq "AssetTag"){
    #     if (-not $field.linkable_id -or $field.linkable_id -lt 1){continue}
    #         $layoutForLinking = Get-HuduAssetLayouts -id $field.linkable_id
    #         $possiblyLinkedAssets=Get-HuduAssets -CompanyId $companyId -id $field.linkable_id
    #         $bag = Get-FieldSynonymsSimple -TargetLabel $layoutForLinking.name -IncludeVariants
    #         $val = Find-RowValueByLabel -TargetLabel $label -Row $Row -SynonymBag $bag -fieldType $field.field_type
    #         $bestItem  = $null
    #         $bestScore = -1.0            
    #         if ($val){
    #             foreach ($asset in $possiblyLinkedAssets) {
    #                 $name = [string]$asset.name
    #                 if ([string]::IsNullOrWhiteSpace($name)) { continue }
    #                 $nNorm = Normalize-Text $name
    #                 $score = if ($nNorm -eq $sNorm) { 1.0 } else { Get-Similarity $name $val }
    #                 if ($nNorm.StartsWith($sNorm) -or $sNorm.StartsWith($nNorm)) {
    #                     $score = [Math]::Min(1.0, $score + 0.02)
    #                 }
    #                 if ($score -gt $bestScore) {
    #                     $bestScore = $score
    #                     $bestItem  = $asset
    #                 }
    #             }
    #         }
    #         if ($bestItem -and $bestitem.id){ $val = $bestItem.id } else {continue}
    #         Write-Host "Matched Asset Tag field $label to $($layoutForLinking.name) asset $($bestItem.name) with score of $($bestScore)"
    #   }
      # special case addressdata
      if ($field.field_type -eq "AddressData"){
        $tmpVal=Build-FieldsFromRow -Row $Row -LayoutFields @(
            @{label = "address_line_1"},
            @{label = "address_line_2"},
            @{label = "city"},
            @{label = "state"},
            @{label = "zip"},
            @{label = "country_name"}
          )
          $address=[ordered]@{}
          foreach ($val in $TMPVAL | where-object {-not [string]::IsNullOrWhiteSpace($_.Value)}){
              $address[$val.Name]=$val.Value
          }
          $val = @{Address = $address}
      }

      $bag = Get-FieldSynonymsSimple -TargetLabel $label -IncludeVariants
      $val = Find-RowValueByLabel -TargetLabel $label -Row $Row -SynonymBag $bag -fieldType $field.field_type
      if ($field.field_type -eq "ListSelect" -and $null -ne $field.list_id){
        $val = $(Get-ListItemFuzzy -listid $field.list_id -source $val).id
      }


      if ($null -ne $val -and "$val".Trim() -ne '') { $out += @{ $label = $val } }
    }
    return $out
  }
}
