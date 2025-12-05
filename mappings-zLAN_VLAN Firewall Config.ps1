$flexiFields = @(
    @{label = 'Editor'; field_type = 'Text'; show_in_list = 'true'; position = 2; required = 'false'; hint = 'Editor from script'},
    @{label = 'Notes'; field_type = 'RichText'; show_in_list = 'false'; position = 4; required = 'false'; hint = 'ITBNotes from script'},
)

$flexisMap = @{
    'Editor' = 'Editor'
    'ITBNotes' = 'Notes'
    'Text_Box_Test' = 'Text Box Test'
}# smoosh source label items to destination smooshable
$smooshLabels = @()
$smooshToDestinationLabel = $null
$jsonSourceFields = @()
$nameField = "Name"
