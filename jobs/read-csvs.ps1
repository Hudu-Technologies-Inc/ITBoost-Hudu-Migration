$CSVFiles= Get-ChildItem -Path $ITBoostExportPath -Recurse -File -Filter "*.csv"
foreach ($f in $CSVFiles){
    try {
        $csvData=$(Import-Csv $f.FullName | Select-Object @{Name='CsvRow'; Expression={ $i++ }}, *)
    } catch {continue}
    if ($csvData){
        $keyName=$($f.name -ireplace ".csv","")
        write-host "importing $keyName from $($f.FullName)"
        $ITBoostData[$keyName]=@{
            CSVData=$csvData
            AttachmentsPath=$(join-path -Path $f.directory.fullname "attachments\$keyName")
            DocumentsPath=$(join-path -Path $f.directory.fullname "documents\$keyName")
            Matches=@()
        }
    }
}