$CSVFiles = @(Get-ITBoostCsvFiles -ExportPath $ITBoostExportPath)
if ($CSVFiles.Count -eq 0) { throw "No entity CSV files found in '$ITBoostExportPath'." }
$csvImportSummary = @()
foreach ($f in $CSVFiles) {
    $headerMap = $null
    # Import errors must stop discovery, rather than silently omit a company's only reference.
    $csvData = @(Import-ITBoostCsv -LiteralPath $f.FullName -HeaderMap ([ref]$headerMap) -ErrorAction Stop)
    $keyName = $f.BaseName
    Write-Host "Importing $keyName from $($f.FullName): $($csvData.Count) rows"
    $csvFileInfo = [pscustomobject]@{ Path = $f.FullName; Headers = @($headerMap); RowCount = $csvData.Count }
    $csvImportSummary += $csvFileInfo
    if ($ITBoostData.ContainsKey($keyName)) {
        if ($ITBoostData[$keyName] -isnot [hashtable] -or -not $ITBoostData[$keyName].ContainsKey('CSVData')) {
            throw "CSV '$($f.FullName)' conflicts with reserved migration state '$keyName'."
        }
        # Multiple exports of the same entity type must not overwrite previously imported rows.
        $ITBoostData[$keyName].CSVData = @($ITBoostData[$keyName].CSVData) + $csvData
        $ITBoostData[$keyName].CsvFiles += $csvFileInfo
    } else {
        $ITBoostData[$keyName] = @{
            CSVData = $csvData
            AttachmentsPath = Join-Path $f.Directory.FullName "attachments/$keyName"
            DocumentsPath = Join-Path $f.Directory.FullName "documents/$keyName"
            Matches = @()
            CsvFiles = @($csvFileInfo)
        }
    }
}

$organizationCatalog = @(Get-ITBoostOrganizationCatalog -ITBoostData $ITBoostData)
$organizationSummary = @(Get-ITBoostOrganizationSummary -Catalog $organizationCatalog)
Write-Host "Discovered $($organizationCatalog.Count) unique organization names across $($CSVFiles.Count) CSV files."
Export-MigrationJson -InputObject $csvImportSummary -LiteralPath (Join-Path $debug_folder 'ImportedCsvHeaders.json')
Export-MigrationJson -InputObject $organizationSummary -LiteralPath (Join-Path $debug_folder 'DiscoveredOrganizations.json')

Write-Host 'Enumerating unique properties for automatic mapping.'
$uniqueProps = @{}
foreach ($key in $ITBoostData.Keys) {
    $dataset = $ITBoostData[$key]
    if ($dataset -isnot [hashtable] -or -not $dataset.ContainsKey('CSVData')) { continue }
    $uniqueProps[$key] = @($dataset.CSVData | ForEach-Object { $_.PSObject.Properties.Name } | Sort-Object -Unique)
}
