$PassProps = @{
  resource_type = "PasswordType"   # verify this param name exists; many modules use PasswordTypeId or similar
  username      = "Username"
  password      = "Password"
  notes         = "Description"    # confirm the param is Description (not Notes)
  server        = "Url"            # many cmdlets use Url, not URL
}

# load companies index if available
$ITBoostData.organizations["matches"] = $ITBoostData.organizations["matches"] ?? $(get-content $companiesIndex -Raw | convertfrom-json -depth 99) ?? @()

if ($ITBoostData.ContainsKey("passwords")) {
  $passwords = $ITBoostData.passwords.CSVData | Group-Object { $_.organization } -AsHashTable -AsString
  if (-not $ITBoostData.passwords.ContainsKey('matches')) { $ITBoostData.passwords['matches'] = @() }

  try { $null = Get-HuduPasswords -ErrorAction Stop } catch { } # warm the pipe

  foreach ($company in $passwords.Keys) {
    Write-Host "starting $company"
    $matchedCompany = Get-HuduCompanyFromName -CompanyName $company -HuduCompanies $huduCompanies  -existingIndex $($ITBoostData.organizations["matches"] ?? $null)
    Write-Host "Matched to company $($matchedCompany.name)"
    if (-not $matchedCompany -or -not $matchedCompany.id -or $matchedCompany.id -lt 1) { 
        continue
     }

    $companyPasswords = Get-HuduPasswords -CompanyId $matchedCompany.id
    $companyAssets    = Get-HuduAssets    -CompanyId $matchedCompany.id
    $companyWebsites  = Get-HuduWebsites | Where-Object { $_.company_id -eq $matchedCompany.id }

    foreach ($companyPass in $passwords[$company]) {
      # try to find an existing password by name
      $matchedPassword = $companyPasswords | Where-Object { test-equiv -A $_.name -B $companyPass.name } | Select-Object -First 1
      $matchedAsset    = $companyAssets   | Where-Object { test-equiv -A $_.name -B $companyPass.name } | Select-Object -First 1
      $matchedWebsite  = $companyWebsites | Where-Object { test-equiv -A $_.name -B ($companyPass.server ?? $companyPass.name) } | Select-Object -First 1

      $NewPasswordRequest = @{
        Name      = "$($companyPass.name)".Trim()
        CompanyId = $matchedCompany.id
      }

      if ($matchedPassword) {
        Write-Host "matched existing password: $($matchedPassword.name)"
                    $ITBoostData.passwords["matches"]+=@{
                        CompanyName=$companyPass.organization
                        ITBID=$companyPass.id
                        Name=$matchedPassword.name
                        HuduID=$matchedPassword.id
                        HuduObject=$matchedPassword
                        HuduCompanyId=$matchedPassword.company_id
                    }            
        continue
      }

      if     ($matchedAsset)   { $asset = $matchedAsset.asset ?? $matchedAsset; $NewPasswordRequest.passwordable_id = $asset.id;          $NewPasswordRequest.passwordable_type = "Asset"   }
      elseif ($matchedWebsite) { $NewPasswordRequest.passwordable_id = $($matchedWebsite.website.id ?? $matchedWebsite.id);                                               $NewPasswordRequest.passwordable_type = "Website" }
      else                     { $NewPasswordRequest.passwordable_id = $null;                                               $NewPasswordRequest.passwordable_type = $null }

      foreach ($prop in $PassProps.Keys) {
        $val = $companyPass.$prop
        if ([string]::IsNullOrWhiteSpace([string]$val)) { continue }
        $keyname = $PassProps[$prop]
        $NewPasswordRequest[$keyname] = $val
      }

      Write-Host ($NewPasswordRequest | ConvertTo-Json -Depth 99)
      $newPass = $null
      try {
        $newPass = $null
        if ($NewPasswordRequest.ContainsKey("Id") -and $NewPasswordRequest["Id"] -gt 0) {
          $newpass = Set-HuduPassword @NewPasswordRequest -ErrorAction Stop
          Write-Host ("Updated: {0}" -f ($newpass | ConvertTo-Json -Depth 5))
        }
        else {
          $newpass = New-HuduPassword @NewPasswordRequest -ErrorAction Stop
          Write-Host ("Created: {0}" -f ($newpass | ConvertTo-Json -Depth 5))
        }
        $newPass= $newpass.asset_password ?? $newpass
      }
      catch {
        Write-Host "Error creating/updating password:"
        $_ | Format-List * -Force | Out-String | Write-Host
      }
      if ($null -ne $newpass) {
        $newpass = $newpass.asset_password ?? $newpass
        $ITBoostData.passwords["matches"]+=@{
            CompanyName=$companyPass.organization
            ITBID=$companyPass.id
            Name=$newpass.name
            HuduID=$newpass.id
            huduCompanyId = $($newPass.company_id ?? $matchedCompany.id)
            HuduObject=$newpass
        }
      }
    }
  }
}
