# ITBoost-Hudu-Migration

Easy Migration from ITBoost to Hudu


### Prerequisites

- Hudu Instance of 2.38.0 or newer
- Hudu API Key
- ITBoost API Export
- Powershell 7.5.1 or later on Windows PC
- Libreoffice


## Getting Started

You'll need just a few items to start
The default configurations csv is invalid. You'll need to replace the 2nd column named 'model' to 'modelo' first, using excel or libreoffice


### Setup Hudu

You'll need to add an API key that has full access, if possible. copy it to clipboard for later or add it to your environment file.

### Environment File

Make your own copy of the environ.example template (as .ps1 file) and record the following items:

- `$hudubaseurl` (eg. ***https://myinstance.huducloud.com***),
- `$huduapikey` (preferably with full-access)
- `$ITBoostExportPath`, your absolute/full path to your ITBoost Export


>Here's a snippet to move you in the right direction (make sure you're in project folder first)
>```
>copy .\environ.example .\environment1.ps1
>notepad .\environment1.ps1
>```

---

### Setup ITBoost

You'll need to initiate a full-instance export (in advanced settings) to start. This may take a while, but when finished, you can extract the resulting .zip file to a destination of your choosing (best to use 7zip if possible).

It's good to make sure that your exported documents contain html file and images. Occasionally, an ITBoost export will not include these in full and a new export will need to be initiated.

## Getting Started

If you've set up your environment file (and have named it with .ps1 extention), you can dot-source invoke that directly

```
. .\environment1.ps1
```
Otherwise, if you invoke the script directly, you'll be asked for required information directly.
```
. .\migrate-itboost-hudu.ps1
```

## Custom Asset Layouts

Custom asset layouts job is intended to be ran for core-entities. That is to say, assets that aren't locations, contacts, companies, websites, configurations, documents, passwords, locations, or runbooks.

This job can be ran as many times as needed until every entity is taken care of at any point after the initial / core items have been taken care of.

When starting, you'll be asked to select a non-core CSV entity from your $ITBoostdata object.
The properties from your selected CSV will be enumerated in a 'suggested' asset layout, which is placed in the main project directory.

This part is pretty easy once you get the hang of it, but could seem daunting at first. Not to worry- 

Your template file will be named after the entry you have chosen and will end with ".ps1", as it contains the definitions we need.






## Notes on Runbooks

