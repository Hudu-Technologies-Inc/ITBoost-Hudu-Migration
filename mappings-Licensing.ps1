$flexiFields = @(
    @{label = 'Expiration Date'; field_type = 'date'; show_in_list = 'false'; position = 2; required = 'false'; hint = 'Expiration Date from script'},
    @{label = 'License Key(s)'; field_type = 'RichText'; show_in_list = 'false'; position = 5; required = 'false'; hint = 'License Key(s) from script'},
    @{label = 'Location'; field_type = 'AssetTag'; linkable_id=1; show_in_list = 'true'; position = 6; required = 'false'; hint = 'Location from script'},
    @{label = 'Manufacturer'; field_type = 'Text'; show_in_list = 'true'; position = 7; required = 'false'; hint = 'Manufacturer from script'},
    @{label = 'Notes'; field_type = 'RichText'; show_in_list = 'false'; position = 9; required = 'false'; hint = 'Notes: from script'},
    @{label = 'Purchase Date'; field_type = 'Date'; show_in_list = 'false'; position = 12; required = 'false'; hint = 'Purchase Date from script'},
    @{label = 'Seats'; field_type = 'Number'; show_in_list = 'true'; position = 15; required = 'false'; hint = 'Seats from script'},
    @{label = 'Version'; field_type = 'Text'; show_in_list = 'true'; position = 16; required = 'false'; hint = 'Version from script'}
)

$flexisMap = @{
    'Expiration_Date' = 'Expiration Date'
    'License_Key(s)' = 'License Key(s)'
    'Manufacturer' = 'Manufacturer'
    'Seats' = 'Seats'
    'Version' = 'Version'
}# smoosh source label items to destination smooshable
$smooshLabels = @("ITBNotes","Notes")
$smooshToDestinationLabel = "Notes"
$jsonSourceFields = @("Name")
$nameField = "Name"
