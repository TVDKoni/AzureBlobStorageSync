# Azure Blob Storage Sync
With this PowerShell script you are able to sync a local folder structure to a blob storage account. File versions are handled with snapshots in the destination blob.

## Installation
Installation is not more than downloading the PowerShell script [SyncFromStorage.ps1](https://raw.githubusercontent.com/TVDKoni/AzureBlobStorageSync/master/SyncFromStorage.ps1) or [SyncToStorage.ps1](https://raw.githubusercontent.com/TVDKoni/AzureBlobStorageSync/master/SyncToStorage.ps1)and configuring it to your needs

## Prerequisites
* An existing Azure blob storage

## Usage
Start a PowerShell session and run the script SyncFromStorage.ps1 or SyncToStorage.ps1. The scripts have a parameter syncParent to specify if the folder above the script location or the script location itself has to be synced.

## Known issues
None at this time