# Hudu Destinatio Reference Section
<#
# {
  "id": 76,
  "label": "Network SSID",
  "show_in_list": false,
  "field_type": "Text",
  "required": false,
  "hint": "e.g. Head Office Wireless",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 1,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 77,
  "label": "Encryption Type",
  "show_in_list": false,
  "field_type": "ListSelect",
  "required": null,
  "hint": "",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": true,
  "list_id": 18,
  "column_width": "variable",
  "position": 2,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 78,
  "label": "Management",
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
  "position": 4,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 79,
  "label": "Management IP Address/URL",
  "show_in_list": false,
  "field_type": "Website",
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
  "position": 5,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 80,
  "label": "Manufacturer",
  "show_in_list": false,
  "field_type": "ListSelect",
  "required": null,
  "hint": "",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": false,
  "options": "",
  "multiple_options": true,
  "list_id": 19,
  "column_width": "variable",
  "position": 8,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 81,
  "label": "Description/Notes",
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
  "position": 9,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
## Labels-only
(      | ForEach-Object {
    "# -  ()"
}) -join "
"
#>

$flexisMap = @{
    'IP_Address' = 'Management IP Address/URL'
    'Manufacturer' = 'Manufacturer'
}# smoosh source label items to destination smooshable
$smooshLabels = @("Notes","ITBNotes","MAC_Address","Model_#","If_WG_managed,_select_appropriate_WG.","Serial_Number")
$smooshToDestinationLabel = "Description/Notes"
$jsonSourceFields = @("If_WG_managed,_select_appropriate_WG.")

# where to get name from on source?
$nameField = "Name_(Scheme:__Name_-_Location)"
