function Normalize-Region {
    param([string]$State)
    if (-not $State) { return $null }
    $s = $State.Trim()

    # Already 2 letters?
    if ($s -match '^[A-Za-z]{2}$') { return $s.ToUpper() }

    $us = @{
        'alabama'='AL'; 'alaska'='AK'; 'arizona'='AZ'; 'arkansas'='AR'; 'california'='CA'
        'colorado'='CO'; 'connecticut'='CT'; 'delaware'='DE'; 'florida'='FL'; 'georgia'='GA'
        'hawaii'='HI'; 'idaho'='ID'; 'illinois'='IL'; 'indiana'='IN'; 'iowa'='IA'
        'kansas'='KS'; 'kentucky'='KY'; 'louisiana'='LA'; 'maine'='ME'; 'maryland'='MD'
        'massachusetts'='MA'; 'michigan'='MI'; 'minnesota'='MN'; 'mississippi'='MS'; 'missouri'='MO'
        'montana'='MT'; 'nebraska'='NE'; 'nevada'='NV'; 'new hampshire'='NH'; 'new jersey'='NJ'
        'new mexico'='NM'; 'new york'='NY'; 'north carolina'='NC'; 'north dakota'='ND'
        'ohio'='OH'; 'oklahoma'='OK'; 'oregon'='OR'; 'pennsylvania'='PA'; 'rhode island'='RI'
        'south carolina'='SC'; 'south dakota'='SD'; 'tennessee'='TN'; 'texas'='TX'; 'utah'='UT'
        'vermont'='VT'; 'virginia'='VA'; 'washington'='WA'; 'west virginia'='WV'; 'wisconsin'='WI'; 'wyoming'='WY'
        'district of columbia'='DC'; 'washington dc'='DC'; 'dc'='DC'
    }
    $key = $s.ToLower()
    if ($us.ContainsKey($key)) { return $us[$key] }
    return $s  # fallback (leave as-is)
}

function Normalize-CountryName {
    param([string]$Country)
    if (-not $Country) { return $null }
    $c = $Country.Trim()
    $map = @{
        'us'='USA'; 'u.s.'='USA'; 'u.s.a'='USA'; 'usa'='USA'; 'united states'='USA'; 'united states of america'='USA'
        'uk'='United Kingdom'; 'u.k.'='United Kingdom'; 'gb'='United Kingdom'; 'gbr'='United Kingdom'
        'uae'='United Arab Emirates'
    }
    $key = $c.ToLower().Replace('.','')
    if ($map.ContainsKey($key)) { return $map[$key] }
    # Title-case fallback
    return -join ($c.ToLower().Split(' ') | ForEach-Object { if ($_){ $_.Substring(0,1).ToUpper()+$_.Substring(1) } })
}

function Normalize-Zip {
    param([string]$Zip)
    if (-not $Zip) { return $null }
    $z = $Zip -replace '\s+', ''  # collapse spaces (e.g., “802 02”)
    return $z.Trim()
}