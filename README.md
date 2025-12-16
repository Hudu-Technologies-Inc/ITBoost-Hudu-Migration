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
Other than that, it's best to start fresh. You can custom-map fields in the same way that you map fields which are templated to custom layouts, but it's generally easier if you start fresh.

### Environment File

Make your own copy of the environ.example template (as .ps1 file) and record the following items:

- `$hudubaseurl` (eg. ***https://myinstance.huducloud.com***),
- `$huduapikey` (preferably with full-access)
- `$ITBoostExportPath`, your absolute/full path to your ITBoost Export
- `TMPbasedir`, your designated temp directory for document, article, image processing
- `internalCompanyName`, your company name, whether existing, or to-be-created

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

During the process, Companies, Locations, Contacts, Websites, Passwords, Articles, and Configurations will be created automagically for you. It's best to start with a blank slate. If you are a go-getter, you'll find that you can map csv fields to existing layouts, but it's not really intended for that use, outside of the flexible layout template generator portion (flexi-layout job).

The process should be relatively quick and painless. It will descriptively tell you what's going on, and while things are going on, it's best to leave the process and hudu instance, not modifying layouts or data while in-transit, if at all possible


## Custom Asset Layouts

Custom asset layouts job is intended to be ran for core-entities. That is to say, assets that aren't locations, contacts, companies, websites, configurations, documents, passwords, locations, or runbooks. All the previous items are automagic, but custom flexible layouts (for now) require a touch of elbow-grease. Not to worry, if you goof something, you can simply remove the asset layout in Hudu and try again by re-invoking the flexi-layout job. It's pretty forgiving

```
. .\jobs\flexi-layout
```

This job can be ran as many times as needed until every entity is taken care of at any point after the initial / core items have been taken care of.

When starting, you'll be asked to select a non-core CSV entity from your $ITBoostdata object.
The properties from your selected CSV will be enumerated in a 'suggested' asset layout, which is placed in the main project directory.

This part is pretty easy once you get the hang of it, but could seem daunting at first. Not to worry- 

Your template file will be named after the entry you have chosen and will end with ".ps1", as it contains the definitions we need.
You'll mainly be concerned with the field_types in the generated asset layout. In the future, these will likely all be generated based on the data present in your CSV, but for now, it requires a little bit of user-interaction.

<img width="632" height="669" alt="image" src="https://github.com/user-attachments/assets/86a4d2fa-d020-44fa-bf5e-e8569ddfc198" />

First, is the FlexiFields object- these are the fields that are going to be placed into Hudu. These fields will default to a field_type of Text, which is fine for many cases, however, there are certain conditions where changing these is best.

- If a field contains passwords, you'll want to set the field_type to `ConfidentialText`
- If a field contains IP addresses or URLs, you'll want to set field_type to `Website`
- If a field contains embeds, links, or otherwise RichText, you'll want to use `RichText`
- For Linked Items, there's a few options.
    - For linked passwords which are their own entity, we can link those by name by placing the corresponding 'name' label for that layout in `LinkedAsPasswords` array
    - For Linked Documents, if there is a field that contains the approximate document title/name in this layout/asset, you can place it in the `DocFields` array

- If you have a FontAwesome Icon in mind that you'd like to use, you can place that as a string under variable for $GivenIcon variable. The icon will be guessed if this isnt set, so no trouble there.
- If you change the name of the label in $flexifields map, you'll want to update the right-hand label in the corresponding $flexismap to reflect your label change
- If you want to join multiple fields into a single field (usually as RichText), you can add these fields to $SmooshLabels array. Anything included in the Smooshlabels array will be joined together in Field - Value format in a pseudo-table within the target field you wish to use. So, for example, if you want to join, "Notes","Root user","general access user" fields into a single richtext field in Hudu, you'd do something like this, below
<img width="550" height="67" alt="image" src="https://github.com/user-attachments/assets/50391610-0c22-43bb-88ab-33e8cccc4553" />

It will surely get easier in the future with some automatic parsing stuff, but for the time being, this offers the most flexibility.

## Other Entity Types

### Runbooks
If you have a folder in your export, named 'RB', these runbooks will have their sub-docs joined together into a single Hudu Article, representing the data just as it was in ITBoost.

### Gallery
Not too common, but gallery items will be re-created as articles with your gallery images, similar to ITBoost

### Standalone-Notes
If you have a standalone notes type entity (notes.csv), these will be incorporated into new Articles in Hudu.

