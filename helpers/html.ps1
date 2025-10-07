function As-HtmlString {
  param($Value)
  if ($Value -is [string]) { return $Value }
  if ($Value -is [System.Array]) {
    # keep only strings; drop non-strings like {}
    return (($Value | Where-Object { $_ -is [string] }) -join '')
  }
  return [string]$Value
}
function Get-LinksFromHTML {
    param (
        [string]$htmlContent,
        [string]$title,
        [bool]$includeImages = $true,
        [bool]$suppressOutput = $false

    )

    $allLinks = @()

    # Match all href attributes inside anchor tags
    $hrefPattern = '<a\s[^>]*?href=["'']([^"'']+)["'']'
    $hrefMatches = [regex]::Matches($htmlContent, $hrefPattern, 'IgnoreCase')
    foreach ($match in $hrefMatches) { 
        $allLinks += $match.Groups[1].Value
    }

    if ($includeImages) {
        # Match all src attributes inside img tags
        $srcPattern = '<img\s[^>]*?src=["'']([^"'']+)["'']'
        $srcMatches = [regex]::Matches($htmlContent, $srcPattern, 'IgnoreCase')
        foreach ($match in $srcMatches) {
            $allLinks += $match.Groups[1].Value
        }
    }
    if ($false -eq $suppressOutput){
        $linkidx=0
        foreach ($link in $allLinks) {
            $linkidx=$linkidx+1
            Set-PrintAndLog -message "link $linkidx of $($allLinks.count) total found for $title - $link" -Color Blue
        }
    }

    return $allLinks | Sort-Object -Unique
}
function Resolve-AbsoluteUrl {
  param([string]$Url, [string]$BaseUrl)
  if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
  $u = $Url.Trim()
  if ($u -match '^(?i)(data:|about:blank|javascript:|#)') { return $null }
  if ($u -match '^(?i)//') { $u = 'https:' + $u }
  try {
    $abs = if ($BaseUrl) { [Uri]::new([Uri]$BaseUrl, $u) } else { [Uri]$u }
    if (-not $abs.IsAbsoluteUri) { return $null }
    $b = [UriBuilder]$abs; $b.Fragment = $null
    # $b.Query = $null  # uncomment if queries should be ignored for matching
    $b.Uri.AbsoluteUri
  } catch { $null }
}

function Rewrite-SrcSet {
  param([string]$SrcSet, [hashtable]$Lookup)
  if ([string]::IsNullOrWhiteSpace($SrcSet)) { return $SrcSet }
  ($SrcSet -split '\s*,\s*' | ForEach-Object {
    if ($_ -match '^\s*(\S+)(\s+.+)?$'){
      $u = $Matches[1]; $desc = $Matches[2]
      $keyName = [IO.Path]::GetFileName($u)
      $rep = $Lookup[$u] ?? $Lookup[$keyName]
      if ($rep) { "$rep$desc" } else { $_ }
    } else { $_ }
  }) -join ', '
}

function Get-ReplacementUrl {
  param(
    [string]$RawUrl,            # src / href as found
    [string]$BaseUrl,           # page/base for relative resolution
    [hashtable]$Lookup,         # keys: absolute urls and/or filenames; values: replacement urls
    [string]$FallbackLocalPath  # optional: absolute file path on disk to derive filename
  )
  # try absolute url
  $abs = Resolve-AbsoluteUrl $RawUrl $BaseUrl
  if ($abs -and $Lookup.ContainsKey($abs)) { return $Lookup[$abs] }

  # try filename from URL
  $nameFromUrl = if ($abs) { [IO.Path]::GetFileName(([Uri]$abs).AbsolutePath) } else { [IO.Path]::GetFileName($RawUrl) }
  if ($nameFromUrl -and $Lookup.ContainsKey($nameFromUrl)) { return $Lookup[$nameFromUrl] }

  # try filename from local path (e.g., after you resolved a thumbnail/full path on disk)
  if ($FallbackLocalPath) {
    $nameFromPath = [IO.Path]::GetFileName($FallbackLocalPath)
    if ($nameFromPath -and $Lookup.ContainsKey($nameFromPath)) { return $Lookup[$nameFromPath] }
  }

  $null
}

function Rewrite-InlineLinksAndImages {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$InFile,
    [string]$BaseUrl,
    [Parameter(Mandatory)][hashtable]$Lookup,
    [switch]$PreferPublicPhoto,
    [switch]$KeepOriginals
  )

  # --- read as STRING and prove it ---
  $local:htmlText = Get-Content -LiteralPath $InFile -Raw -Encoding UTF8
  if (-not ($local:htmlText -is [string])) {
    throw "Expected string HTML, got $($local:htmlText?.GetType().FullName)"
  }
  if ([string]::IsNullOrWhiteSpace($local:htmlText)) { return $local:htmlText }

  # normalize nbsp
  $local:htmlText = [regex]::Replace($local:htmlText, '\xa0+', ' ')

  # --- COM doc ---
  $local:doc = New-Object -ComObject 'HTMLFile'
  $local:doc.Open()

  # Build a single-element *string[]* (NOT object[]) for safest interop
  $local:stringArray = [string[]]@($local:htmlText)

  try {
    # First try: direct write with string[]
    $local:doc.write($local:stringArray)
  } catch {
    # Fallback: InvokeMember (sometimes required on certain boxes)
    try {
      [void]$local:doc.GetType().InvokeMember('write','InvokeMethod',$null,$local:doc,@($local:stringArray))
    } catch {
      throw "IHTMLDocument2.write failed (type mismatch). Text type=$($local:htmlText.GetType().FullName), len=$($local:htmlText.Length). Inner: $($_.Exception.Message)"
    }
  }

  $local:doc.Close()

  # --- rest of your logic (unchanged), but use $local:doc / $local:htmlText variable names ---
  $local:baseNode = @($local:doc.getElementsByTagName('base'))[0]
  $local:effectiveBase = if ($local:baseNode -and $local:baseNode.href) { $local:baseNode.href } else { $BaseUrl }

  # IMAGES
  $local:imgs = @($local:doc.getElementsByTagName('img'))
  foreach ($local:img in $local:imgs) {
    $srcRaw = $local:img.getAttribute('src'); if (-not $srcRaw) { continue }
    $fullRaw = $local:img.getAttribute('data-src-original')
    $localPath = $null
    if (($srcRaw -notmatch '^https?://') -or ($BaseUrl -and $srcRaw -match [regex]::Escape($BaseUrl))) {
      $basepath = Split-Path -LiteralPath $InFile
      if ($fullRaw) {
        $fullPath = Join-Path $basepath ($fullRaw -replace '/','\')
        $found = Get-Item -LiteralPath $fullPath -ErrorAction SilentlyContinue
        if ($found) { $localPath = $found.FullName }
      }
      if (-not $localPath -and $srcRaw) {
        $tnPath = Join-Path $basepath ($srcRaw -replace '/','\')
        $found = Get-Item -LiteralPath $tnPath -ErrorAction SilentlyContinue
        if ($found) { $localPath = $found.FullName }
      }
    }
    $rep = Get-ReplacementUrl -RawUrl $srcRaw -BaseUrl $local:effectiveBase -Lookup $Lookup -FallbackLocalPath $localPath
    if ($rep) {
      if ($KeepOriginals) { $local:img.setAttribute('data-original-src', $srcRaw) }
      $local:img.setAttribute('src', $rep)

      $srcset = $local:img.getAttribute('srcset')
      if ($srcset) {
        $newSet = Rewrite-SrcSet -SrcSet $srcset -Lookup $Lookup
        if ($newSet -ne $srcset) {
          if ($KeepOriginals) { $local:img.setAttribute('data-original-srcset', $srcset) }
          $local:img.setAttribute('srcset', $newSet)
        }
      }
    }
  }

  # LINKS
  $local:as = @($local:doc.getElementsByTagName('a'))
  foreach ($local:a in $local:as) {
    $hrefRaw = $local:a.getAttribute('href'); if (-not $hrefRaw) { continue }
    $rep = Get-ReplacementUrl -RawUrl $hrefRaw -BaseUrl $local:effectiveBase -Lookup $Lookup
    if ($rep) {
      if ($KeepOriginals) { $local:a.setAttribute('data-original-href', $hrefRaw) }
      $local:a.setAttribute('href', $rep)
      $local:a.setAttribute('target','_blank'); $local:a.setAttribute('rel','noopener')
    }
  }

  # OUTPUT
  $local:root = @($local:doc.getElementsByTagName('html'))[0]
  $local:updated = if ($null -ne $local:root) { $local:root.outerHTML }
                   elseif ($local:doc.body -and $local:doc.body.parentElement) { $local:doc.body.parentElement.outerHTML }
                   else { $local:doc.documentElement.outerHTML }
  return $local:updated
}
