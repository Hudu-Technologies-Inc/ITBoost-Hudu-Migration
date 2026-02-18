
$configsLayout = $configsLayout ?? $(get-huduassetlayouts | Where-Object { ($(Get-NeedlePresentInHaystack -needle "config" -haystack $_.name) -or $($_.name -ilike "config*")) } | Select-Object -First 1); $configsLayout = $configsLayout.asset_layout ?? $configsLayout;
if ($null -eq $configsLayout){
    write-warning "make sure you have completed configurations layout setup steps, exiting."
    return
}
$allHuduConfigs = $allHuduConfigs ?? $(Get-HuduAssets -AssetLayoutId $configsLayout.id)
$fieldPayload = @(foreach ($f in $configsLayout.fields) { Copy-LayoutFieldPayload $f })
$configsMoved = @{}
foreach ($configType in $itboostdata.configurations.csvdata.configuration_type | select-object -unique) {
        $newlayout = new-huduassetlayout -name "$configType" -fields $fieldPayload -IncludePasswords $true -IncludePhotos $true -IncludeComments $true -IncludeFiles $true -Color "#6136ff" -Icon "fas fa-cogs" -IconColor "#ffffff" -Color "#6136ff"
        $newlayout = get-huduassetlayouts -name "$configType" | select-object -first 1
        $newlayout = $newlayout.asset_layout ?? $newlayout
        $configsMoved[$configType] = layout2layout -sourceLayoutName $configsLayout.name -targetLayoutName $newlayout.name -sourceAssets $($allHuduConfigs | Where-Object {($_.fields | Where-Object name -ieq 'Configuration Type').value -ieq $configType})
}
