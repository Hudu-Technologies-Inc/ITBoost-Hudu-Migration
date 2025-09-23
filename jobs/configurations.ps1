$props = @(
"name",
"model",
"configuration_type",
"resource_type",
"configuration_status",
"hostname",
"primary_ip",
"default_gateway",
"serial_number",
"asset_tag",
"manufacturer",
"operating_system",
"operating_system_notes",
"position",
"installed_at",
"purchased_at",
"warranty_expires_at",
"contact",
"location",
"configuration_interfaces"
)

$passwords = @(
    "password"
)
$linkedFieldNames=@(
"installed_by",
"purchased_by"
)
$allcontacts = get-huduassets -assetlayoutId 2 -companyId 8
$namesSeen = @()

foreach ($config in $configurations) { 
    if ($namesSeen -contains $config.name){continue} else {$namesSeen+=$config.name}

     # build a single hashtable of fields
     $fields = [ordered]@{}

     $notes = "$($config.notes)"
     if ($config.IBnotes){
        $notes="$notes<br>$($config.ibnotes)"
     }
     $mac = $config."mac_address" ?? $config."macAddress"
    if (-not $([string]::IsNullOrWhiteSpace($mac))) { $fields["macAddress"]=$mac }
    if (-not $([string]::IsNullOrWhiteSpace($notes))) { $fields["notes"]=$notes }


     foreach ($fieldName in $linkedFieldNames) {
         $srvname = $config.$fieldName
         if ([string]::IsNullOrWhiteSpace($srvname)) { continue }

         # find a server in this company first, else any
         $linkedAsset =
             $allcontacts | Where-Object { $_.name -eq $srvname} | Select-Object -First 1
         if (-not $linkedAsset) {
             $linkedAsset = $allcontacts | Where-Object { $_.name -eq $srvname } | Select-Object -First 1
         }

         if ($linkedAsset) {
             Write-Host "matched $($linkedAsset.name)"
             # Hudu linked field often expects a JSON array of IDs as text
             $fields[$fieldName] = ($linkedAsset.id | ConvertTo-Json -Compress -AsArray).Trim()
         }
     }

     foreach ($prop in $props) {
         $val = $config.$prop
         if (-not [string]::IsNullOrWhiteSpace($val)) {
             $fields[$prop] = $val
         }
     }

     $assetName =
         if ($config.Name) {$config.name} else { "$($config.model) $($config.'configuration_type')" }

     $validatedFields = @()
     foreach ($f in $fields.GetEnumerator().Name){
        $keyname = $("$($f -replace '_',' ')".Trim())
        $validatedFields+=@{$keyname = $fields[$f]}
     }

     New-HuduAsset -CompanyId 8 -AssetLayoutId 6 -Name $assetName -Fields $validatedFields
 }