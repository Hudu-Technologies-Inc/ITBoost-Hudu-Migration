# ITBoost-Hudu-Migration

Easy Migration from ITBoost to Hudu

## Setup

### Prerequisites

- Hudu Instance of 2.38.0 or newer
- Hudu API Key
- ITBoost API Export
- Powershell 7.5.1 or later


### Setup ITBoost

You'll need to initiate a full-instance export (in advanced settings) to start. This may take a while, but when finished, you can extract the resulting .zip file to a destination of your choosing (best to use 7zip if possible)

Then, you may want to take a look at your csv's. Namely, the configurations csv, which often has two columns named 'model' on the first line. You'll need to rename the first one to any unque name. I usually choose 'modelo'

### Setup Hudu

You'll need to add an API key that has full access, if possible.

## Getting Started

### Launching Script

Getting started is really as simple as starting the main script.

---

There are a few ways to start. Probably the easiest way is to simply start the script with PowerShell.

```
 . .\migrate-itboost-hudu.ps1
```
Alternatively, you can make a copy of the environment example file, edit in your values, and run when filled out.
```
copy .\environ.example .\environment1.ps1
notepad .\myenviron.ps1
write-host "...everything is edited!"
 . .\migrate-itboost-hudu.ps1
```

