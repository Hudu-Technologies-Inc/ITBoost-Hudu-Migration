
# preload company matches
$ITBoostData.organizations["matches"] = $ITBoostData.organizations["matches"] ?? $(get-content $companiesIndex -Raw | convertfrom-json -depth 99) ?? @()
get-ensuredpath -path $TMPbasedir | Out-Null
$galleryItems = @()
if (-not $ITBoostData.ContainsKey("gallery")){write-host "No data for gallery"; exit 1}

foreach ($galleryitem in $ITBoostData.gallery.CSVData) {
    $rawUploadField = $galleryitem.image

    if (-not $rawUploadField) {
        Write-Host "No upload field on row; skipping"
        continue
    }
    $objects = SafeDecode $rawUploadField
    if ($null -eq $objects) {Write-Host "No image objects"
        continue
    }

    # Normalize to collection
    if ($objects -isnot [System.Collections.IEnumerable] -or $objects -is [string]) {
        $objects = @($objects)
    }

    $filenames = foreach ($o in $objects) {
        if ($o -is [string]) {
            Split-Path $o -Leaf
            continue
        }

        # JSON object-style
        $o.filename
        $o.originalname
        if ($o.imgPath) { Split-Path $o.imgPath -Leaf }
    }

    $filenames = $filenames |
        Where-Object { $_ -and -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique

    Write-Host ("Filenames: {0}" -f ($filenames -join ", "))
    $FilesPresent = @()
    foreach ($f in $filenames){
        get-childitem -Path $ITBoostExportPath -Recurse -Filter $f | ForEach-Object {
            $FilesPresent += $_
        }
    }
    if ($FilesPresent.count -eq 0){
        Write-Host "No files found for gallery item $($galleryitem.name), skipping"
        continue
    }
    $uuid = [guid]::NewGuid().ToString()
    $dest = Join-Path $TMPbasedir ("gallery-" + $uuid)    
    get-ensuredpath -path $dest | Out-Null
    foreach ($file in $FilesPresent){
        Copy-Item -Path $file.FullName -Destination (Join-Path $dest $file.Name) -Force
    }
    write-host "creating article for $($galleryitem.organization) - $($galleryitem.name)"
    try {
        $newArticle = Set-HuduArticleFromResourceFolder -resourcesFolder $dest -companyName $galleryitem.organization -title "$(if ([string]::IsNullOrWhiteSpace($galleryitem.name)) {"$($galleryitem.organization) - Gallery, $(($uuid -split "-")[0])"} else {$galleryitem.name})"
    } catch {
        Write-Host "Error creating article for gallery item $($galleryitem.name): $_"
        continue
    }
    if (-not $newArticle -or -not $newArticle.Title){
        Write-Host "Failed to create article for gallery item $($galleryitem.name), skipping"
        continue
    }
    $galleryItems+=$newArticle

}

$galleryItems | convertto-json -depth 99 | out-file $($(join-path $debug_folder -ChildPath "GalleryItems.json")) -Force
