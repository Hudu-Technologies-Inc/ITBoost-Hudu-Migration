# Hudu Destinatio Reference Section
<#
# {
  "id": 41,
  "label": "Category",
  "show_in_list": false,
  "field_type": "ListSelect",
  "required": false,
  "hint": "",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": true,
  "list_id": 9,
  "column_width": "variable",
  "position": 1,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 42,
  "label": "Version",
  "show_in_list": false,
  "field_type": "Text",
  "required": null,
  "hint": "Major and minor version number - e.g. 2008 R2, XP, 7.3 SP1, etc.",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 2,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 43,
  "label": "Importance",
  "show_in_list": false,
  "field_type": "ListSelect",
  "required": null,
  "hint": "Importance of application to organization - e.g. downtime tolerance",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": true,
  "list_id": 10,
  "column_width": "variable",
  "position": 3,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 44,
  "label": "Business Impact",
  "show_in_list": false,
  "field_type": "RichText",
  "required": null,
  "hint": "Describe business impact of outage - e.g. sales unable to occur",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 4,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 45,
  "label": "Application Champion",
  "show_in_list": false,
  "field_type": "Text",
  "required": null,
  "hint": "Who is the primary champion?",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 5,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 46,
  "label": "Licensing & Support Information",
  "show_in_list": false,
  "field_type": "Heading",
  "required": null,
  "hint": "",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 6,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 47,
  "label": "Notes",
  "show_in_list": false,
  "field_type": "RichText",
  "required": null,
  "hint": "",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 7,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 48,
  "label": "New Computer/User setup",
  "show_in_list": false,
  "field_type": "RichText",
  "required": null,
  "hint": "",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 8,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
## Labels-only
(        | ForEach-Object {
    "# -  ()"
}) -join "
"
#>

$flexisMap = @{
    'Manufacturer' = 'Licensing & Support Information'
    'User_Access\Login_URL' = 'New Computer/User setup'
}# smoosh source label items to destination smooshable
$smooshLabels = @("Notes:","Status","Host(s)_(if_on-premise):","On-Premise_\_Cloud","Install_File(s)_Location_\_URL")
$smooshToDestinationLabel = "Notes"
$jsonSourceFields = @()
$PasswordsFields = @()

# where to get name from on source?
$nameField = "Application Name"
