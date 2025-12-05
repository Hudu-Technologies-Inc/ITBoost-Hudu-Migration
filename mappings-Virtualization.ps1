 

$FlexiFields = @(
            @{label        = 'first Name'; field_type   = 'Text'; show_in_list = 'true'; position     = 1},
            @{label        = 'Last Name'; field_type   = 'Text'; show_in_list = 'false';position     = 2},
            @{label        = 'Title'; field_type   = 'Text'; show_in_list = 'true'; position     = 3},
            @{label        = 'flexi Type'; field_type   = 'Text'; show_in_list = 'true'; position     = 4},
            @{label        = 'Location'; field_type   = 'AssetTag'; show_in_list = 'false';linkable_id  = $LocationLayout.ID; position     = 5},
            @{label        = 'Important'; field_type   = 'Text'; show_in_list = 'false';position     = 6},
            @{label        = 'Notes'; field_type   = 'RichText'; show_in_list = 'false';position     = 7},
            @{label        = 'Emails'; field_type   = 'RichText'; show_in_list = 'false';position     = 8},
            @{label        = 'Phones'; field_type   = 'RichText'; show_in_list = 'false';position     = 9}
        )

$flexisMap = @{
    first_name="First Name"
    last_name="Last Name"
    flexi_type="flexi Type"
    primary_phone = "Phones"
    primary_email = "Emails"
    notes = "Notes"
    title = "Title"
}        

$flexiIcon = "fas fa-users"