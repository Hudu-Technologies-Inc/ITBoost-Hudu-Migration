# Hudu Destinatio Reference Section
<#
# {
  "id": 200,
  "label": "Role",
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
  "list_id": 8,
  "column_width": "variable",
  "position": 1,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 201,
  "label": "IP Address",
  "show_in_list": false,
  "field_type": "Website",
  "required": null,
  "hint": "Management IP Address",
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
  "id": 202,
  "label": "Configuration",
  "show_in_list": false,
  "field_type": "RichText",
  "required": null,
  "hint": "Copy & Paste the Configuration",
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
  "id": 203,
  "label": "Subscription/Support Renewal",
  "show_in_list": false,
  "field_type": "Date",
  "required": false,
  "hint": "",
  "min": null,
  "max": null,
  "linkable_id": 5,
  "expiration": true,
  "options": "",
  "multiple_options": null,
  "list_id": null,
  "column_width": "variable",
  "position": 6,
  "is_destroyed": false,
  "radar_data_point_id": null
} # for reference
# {
  "id": 204,
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
## Labels-only
(     | ForEach-Object {
    "# -  ()"
}) -join "
"
#>

    # 'CsvRow' = ' '
    # 'Host' = ' '
    # 'id' = ' '
    # 'Internal_\_External' = ' '
    # 'ITBNotes' = ' '
    # 'Location' = ' '
    # 'Mapped_Drive_(if_applicable)' = ' '
    # 'Notes:' = ' '
    # 'organization' = ' '
    # 'password' = ' '
    # 'Path' = ' '
    # 'resource_id' = ' '
    # 'resource_type' = ' '
    # 'Share_Name' = ' '

$flexisMap = @{
    'path' = 'IP Address'
}# smoosh source label items to destination smooshable
$contstants = @(
  @{"role" = "NAS"}
)
$smooshLabels = @("Share_Name","Mapped_Drive_(if_applicable)","host","Internal_\_External","ITBNotes","Notes")
$smooshToDestinationLabel = "Notes"
$jsonSourceFields = @("host","itbnotes")

# where to get name from on source?
$nameField = "path" 