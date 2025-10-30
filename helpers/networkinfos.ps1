

function Get-Mask32 {
  param([Parameter(Mandatory)][int]$Prefix)
  if ($Prefix -le 0) { return [uint32]0 }
  if ($Prefix -ge 32){ return [uint32]0xFFFFFFFF }
  $mask = [uint32]0
  # set the first $Prefix bits to 1 (big-endian bit positions 31..0)
  for($i = 0; $i -lt $Prefix; $i++){
    $mask = $mask -bor ([uint32]1 -shl (31 - $i))
  }
  return $mask
}

function Convert-IPv4ToUInt32 {
  param([Parameter(Mandatory)][string]$Ip)
  $bytes = [System.Net.IPAddress]::Parse($Ip).GetAddressBytes()
  if ($bytes.Length -ne 4) { throw "IPv4 only: $Ip" }
  [Array]::Reverse($bytes)
  [BitConverter]::ToUInt32($bytes, 0)
}

function Parse-Cidr {
  param([Parameter(Mandatory)][string]$Cidr) # e.g. "10.0.33.0/24"
  $ip, $prefix = $Cidr -split '/', 2
  $prefix = [int]$prefix
  if ($prefix -lt 0 -or $prefix -gt 32) { throw "Bad prefix: $prefix in $Cidr" }

  $netU = Convert-IPv4ToUInt32 $ip

  if ($prefix -eq 0) {
    $mask = [uint32]0
  } else {
    $rightZeros = 32 - $prefix
    # Build a mask of top $prefix 1-bits by inverting $rightZeros low 1-bits.
    $lowOnes = ([uint32]1 -shl $rightZeros) - 1      # 0…00011111111
    $mask    = -bnot $lowOnes                        # 1…11100000000
  }

  $start = $netU -band $mask
  $end   = $start -bor ((-bnot $mask) -band 0xFFFFFFFF)

  [pscustomobject]@{
    Cidr   = $Cidr
    Prefix = $prefix
    Start  = $start
    End    = $end
  }
}

function Test-CidrContains {
  param([Parameter(Mandatory)][string]$Outer,
        [Parameter(Mandatory)][string]$Inner)
  try {
    $o = Parse-Cidr $Outer
    $i = Parse-Cidr $Inner
    ($i.Start -ge $o.Start -and $i.End -le $o.End)
  } catch { $false }
}


function Get-NetworkChain {
  param(
    [Parameter(Mandatory)]$Network,
    [Parameter(Mandatory)][object[]]$AllNetworks
  )
  $chain = New-Object System.Collections.Generic.List[object]
  $chain.Add($Network) | Out-Null

  if ($Network.ancestry) {
    $ids = $Network.ancestry -split '/' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    foreach ($parentId in $ids) {
      $p = $AllNetworks | Where-Object id -eq $parentId | Select-Object -First 1
      if ($p) { $chain.Add($p) | Out-Null }
    }
  } else {
    foreach ($p in $AllNetworks) {
      if ($p.id -ne $Network.id -and $p.address -and (Test-CidrContains -Outer $p.address -Inner $Network.address)) {
        $chain.Add($p) | Out-Null
      }
    }
  }

  $chain | Sort-Object { (Parse-Cidr $_.address).Prefix } -Descending
}

function Build-NetworkIndex {
  param([Parameter(Mandatory)][object[]]$Networks)
  $rows = @()
  foreach ($n in @($Networks)) {
    $cidrObj = if ($n.address) { Parse-Cidr $n.address } else { $null }
    if ($cidrObj) {
      $rows += [pscustomobject]@{ Network = $n; Cidr = $cidrObj }
    } else {
      # Log once but do not throw
      Write-Host "Skip bad network address: $($n.address)" -ForegroundColor Yellow
    }
  }
  # Always return an array (possibly empty), never $null
  @($rows | Sort-Object { $_.Cidr.Prefix } -Descending)
}

function Find-NetworkForIp {
  param(
    [Parameter(Mandatory)][string]$Ip,
    [Parameter(Mandatory)][object[]]$NetworkIndex,
    [int]$CompanyId = $null
  )
  if (-not $NetworkIndex) { return $null }   # guard
  $ipU = Convert-IPv4ToUInt32 $Ip
  if ($null -eq $ipU) { return $null }

  foreach ($row in $NetworkIndex) {
    $n = $row.Network
    if ($CompanyId -and $n.company_id -ne $CompanyId) { continue }
    $c = $row.Cidr
    if ($ipU -ge $c.Start -and $ipU -le $c.End) { return $n }
  }
  $null
}
function Group-IpAddressesByNetwork {
  param(
    [Parameter(Mandatory)][object[]]$IpAddresses,
    [Parameter(Mandatory)][object[]]$Networks,
    [int]$CompanyId = $null
  )

  $idx = Build-NetworkIndex -Networks $Networks
  if ($null -eq $idx) { $idx = @() }  # harden

  $groups = @{}
  foreach ($ip in @($IpAddresses)) {
    if (-not $ip.address) { continue }
    if ($CompanyId -and $ip.company_id -ne $CompanyId) { continue }

    $net = Find-NetworkForIp -Ip $ip.address -NetworkIndex $idx -CompanyId $CompanyId
    $key = if ($net) { "net:$($net.id)" } else { "unmatched" }

    if (-not $groups.ContainsKey($key)) {
      $groups[$key] = [pscustomobject]@{ Network = $net; IPs = New-Object System.Collections.Generic.List[object] }
    }
    $groups[$key].IPs.Add($ip) | Out-Null
  }

  $groups.Values
}