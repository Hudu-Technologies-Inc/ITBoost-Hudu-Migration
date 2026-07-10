$PassProps = @{
  resource_type = "PasswordType"
  username      = "Username"
  password      = "Password"
  notes         = "Description"
  server        = "Url"
}

# load companies index if available
$ITBoostData.organizations["matches"] = $ITBoostData.organizations["matches"] ?? $(get-content $companiesIndex -Raw | convertfrom-json -depth 99) ?? @()

if ($ITBoostData.ContainsKey("passwords")) {
  $passwords = $ITBoostData.passwords.CSVData | Group-ObjectSafeHashTable { $_.organization }
  if (-not $ITBoostData.passwords.ContainsKey('matches')) { $ITBoostData.passwords['matches'] = @() }

  try { $null = Get-HuduPasswords } catch { } # warm the pipe

  foreach ($company in $passwords.Keys) {
    Write-Host "starting $company"
    $matchedCompany = Get-HuduCompanyFromName -CompanyName $company -deepCompanySearch $true -HuduCompanies $huduCompanies  -existingIndex $($ITBoostData.organizations["matches"] ?? $null)
    Write-Host "Matched to company $($matchedCompany.name)"
    if (-not $matchedCompany -or -not $matchedCompany.id -or $matchedCompany.id -lt 1) { 
        $matchedCompany = New-HuduCompany -name $company
        $matchedCompany = get-huducompanies -Name $company | select-object -first 1
        $matchedCompany = $matchedCompany.company ?? $matchedCompany
        Write-Host "Created and matched to company $($matchedCompany.name) with ID $($matchedCompany.id)"
     }

    $companyPasswords = Get-HuduPasswords -CompanyId $matchedCompany.id
    $companyAssets    = Get-HuduAssets    -CompanyId $matchedCompany.id
    $companyWebsites  = Get-HuduWebsites | Where-Object { $_.company_id -eq $matchedCompany.id }

    foreach ($companyPass in $passwords[$company]) {
      # try to find an existing password by name
      $matchedAsset = $null; $matchedpassword = $null; $matchedwebsite=$null;
      $matchedPassword = $companyPasswords | Where-Object { test-equiv -A $_.name -B $companyPass.name } | Select-Object -First 1
      $matchedAsset    = $companyAssets   | Where-Object { (test-equiv -A $_.name -B $companyPass.name) -or ($_.name.length -ge 5 -and $_.name -ilike "*$($companyPass.name)*") -or ($companyPass.name.length -ge 5 -and $companypass.name -ilike "*$($_.name)*") }
      $matchedWebsite  = $companyWebsites | Where-Object { test-equiv -A $_.name -B ($companyPass.server ?? $companyPass.name) } | Select-Object -First 1

      $NewPasswordRequest = @{
        Name      = ("$($companyPass.name)".Trim())
        CompanyId = $matchedCompany.id
      }

      if ($matchedPassword) {
        $NewPasswordRequest.Id = $matchedPassword.id
        if ($true -eq $skiponmatch){continue}

      }
      $matchedAsset = @($matchedAsset)

      $firstMatch  = $matchedAsset | Select-Object -First 1
      $restMatches = $matchedAsset | Select-Object -Skip 1
      if     ($null -ne $firstMatch -and $firstMatch.id -gt 0)   { $firstMatch = $firstMatch.asset ?? $firstMatch; $NewPasswordRequest.passwordable_id = $firstMatch.id; $NewPasswordRequest.passwordable_type = "Asset";}
      write-host "matched asset $($firstmatch.name) for password $($companyPass.name)... $($restmatches.count) other matches found" -foregroundcolor yellow


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
          $newpass = Set-HuduPassword @NewPasswordRequest
          Write-Host ("Updated: {0}" -f ($newpass | ConvertTo-Json -Depth 5))
        }
        else {
          $newpass = New-HuduPassword @NewPasswordRequest
          Write-Host ("Created: {0}" -f ($newpass | ConvertTo-Json -Depth 5))
        }
        $newPass= $newpass.asset_password ?? $newpass
      }
      catch {
        Write-Host "Error creating/updating password: $_"
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
        foreach ($othermatch in $($restMatches)){
            if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $true} catch {}}
            new-hudurelation -fromable_id $newpass.id -toable_id $othermatch.id -fromable_type "AssetPassword" -toable_type "Asset"
            if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $false} catch {}}
          }
          if ($matchedWebsite -ne $null){
            if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $true} catch {}}
            new-hudurelation -fromable_id $newpass.id -toable_id $matchedWebsite.id -fromable_type "AssetPassword" -toable_type "Website"
            if (get-command -name Set-HapiErrorsDirectory -ErrorAction SilentlyContinue){try {Set-HapiErrorsDirectory -skipRetry $false} catch {}}

          }

        }
      }
    }
  }


$passwordsFromEmbedded=@{}
write-host "processing embedded configurations passwords!"
foreach ($possiblepasswordEmbed in @(
"configurations","organizations","contacts","documents","domains","locations"
)){
  write-host "checking $possiblepasswordEmbed for embedded passwords"
   if ($ITBoostData.ContainsKey($possiblepasswordEmbed)){
    $passwordsFromEmbedded[$possiblepasswordEmbed] = Set-PasswordsFromEmbeddedCSVobjects -itboostdata $itboostdata -keyname "$possiblepasswordEmbed"
   }
}

foreach ($p in $(get-hudupasswords)){
    $pass = $p.asset_password ?? $p; $desc = $pass.description;
    if ([string]::IsNullOrEmpty($desc)){write-host "empty description on pass $($pass.id), skipping"; continue}
    $descupdated = ConvertFrom-HtmlToPlainText "$desc"
    if ($desc -ne $descupdated -and -not ([string]::IsNullOrWhiteSpace(($descupdated) -and $pass.id -ne $null))){Set-HuduPassword -id $pass.id -CompanyId $pass.company_id -Description "$descupdated"} else {write-host "Skipping description on pass - no change for $($pass.id)"; continue;}

}
$($passwordsFromEmbedded ?? @()) | convertto-json -depth 99 | out-file $($(join-path $debug_folder -ChildPath "PasswordsFromEmbeds.json")) -Force
($ITBoostData.passwords["matches"] ?? @()) | convertto-json -depth 99 | out-file $($(join-path $debug_folder -ChildPath "MatchedPasswords.json")) -Force
