#Requires -Version 3.0

# Parameters
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)]
    $skipModuleTest = $true,
    [Parameter(Mandatory=$false)]
    $syncParent = $true
)

# Configuration
$DestinationStorageAccountName = "!!PleaseSpecify!!" # The destination stroage account name
$DestinationStorageAccountKey = Read-Host "Please enter storage key" # The destination stroage account key
$DestinationStorageEndpoint = "core.windows.net" # The source stroage endpoint. For Microsoft Azure it is always core.windows.net

# Getting latest azure storage cmdlt if not already present
function DownloadAndImportCmdlet($moduleName)
{
    Write-Host " - Checking module $moduleName"
	$actVersion = (Find-Module -Name $moduleName ).Version.ToString()
	if (-not (Test-Path "$PSScriptRoot\$moduleName\$actVersion"))
	{
        Write-Host " - Downloading module $moduleName $actVersion"
		Save-Module -Name $moduleName -MinimumVersion $actVersion -Path $PSScriptRoot
	}
    Write-Host " - Importing module $moduleName $actVersion"
    Get-ChildItem "$PSScriptRoot\$moduleName\$actVersion\*.psm1" | Import-Module -Scope Local
}
function ImportCmdlet($moduleName)
{
	if (-not (Test-Path "$PSScriptRoot\$moduleName"))
	{
        DownloadAndImportCmdlet $moduleName
	}
    else
    {
        $actVersion = (Get-ChildItem "$PSScriptRoot\$moduleName" -Directory).Name
        Write-Host " - Importing module $moduleName $actVersion"
        Get-ChildItem "$PSScriptRoot\$moduleName\$actVersion\*.psm1" | Import-Module -Scope Local
    }
}
Write-Host "Checking modules"
$env:PSModulePath = $env:PSModulePath + ";" + $PSScriptRoot
if ($skipModuleTest)
{
    ImportCmdlet "Azure.Storage"
}
else
{
    DownloadAndImportCmdlet "Azure.Storage"
}

# Members
$DestinationStorageContext = New-AzureStorageContext -StorageAccountName $DestinationStorageAccountName -StorageAccountKey $DestinationStorageAccountKey -Endpoint $DestinationStorageEndpoint -ErrorAction Stop

# Defining functions
function SyncDir
{
    Param(
        [Parameter(Mandatory=$true)]
        $rootDir,
        [Parameter(Mandatory=$true)]
        $actDir,
        [Parameter(Mandatory=$true)]
        $destContainer
    )
    
    $relPath = $actDir.FullName.Replace($rootDir.FullName, "")
    Write-Output "   * Syncing '$($actDir.FullName)'"

    $SourceFiles = Get-ChildItem ($rootDir.FullName + $relPath) | ?{ -not $_.PSIsContainer }
    $SourceFiles | foreach {

        $SourceFile = $_
        Write-Output "     @File '$($SourceFile.Name)'"

        $BlobName = ($relPath + "\" + $SourceFile.Name).Substring(1)

        $DestinationBlob = Get-AzureStorageBlob -Context $DestinationStorageContext -Container $destContainer.Name -Blob $BlobName -ErrorAction SilentlyContinue
        $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
        $hash = [System.Convert]::ToBase64String($md5.ComputeHash([System.IO.File]::ReadAllBytes($SourceFile.FullName)))
        if ($DestinationBlob)
        {
            $DestinationBlob.ICloudBlob.FetchAttributes()
            if ($DestinationBlob.ICloudBlob.Properties.ContentMD5 -ne $hash)
            {
			    Write-Output "      : Creating Snapshot"
			    $Tmp = $DestinationBlob.ICloudBlob.CreateSnapshot()
		        Write-Output "      : Copying blob"
                $DestinationBlob = Set-AzureStorageBlobContent -File $SourceFile.FullName -Context $DestinationStorageContext -Container $destContainer.Name -Blob $BlobName -Force
            }
        }
        else
        {
		    Write-Output "      : Copying blob"
            $DestinationBlob = Set-AzureStorageBlobContent -File $SourceFile.FullName -Context $DestinationStorageContext -Container $destContainer.Name -Blob $BlobName -Force
        }
    }

    $SourceDirs = Get-ChildItem ($rootDir.FullName + "\" + $relPath) | ?{ $_.PSIsContainer }
    $SourceDirs | foreach {
        SyncDir -rootDir $rootDir -actDir $_ -destContainer $destContainer
    }
}

function CleanContainer
{
    Param(
        [Parameter(Mandatory=$true)]
        $rootDir,
        [Parameter(Mandatory=$true)]
        $destContainer
    )
    
    Write-Output "   * Cleaning container '$($destContainer.Name)'"

    $DestinationBlobs = Get-AzureStorageBlob -Context $DestinationStorageContext -Container $destContainer.Name
    $DestinationBlobs | foreach {
        $DestinationBlob = $_
        if (-not $DestinationBlob.ICloudBlob.IsSnapshot) {
            Write-Output "     @Blob '$($DestinationBlob.Name)'"

            $FilePath = $rootDir.FullName + "\" + $DestinationBlob.Name
            if (-not (Test-Path $FilePath))
            {
		        Write-Output "      : Deleting blob"
                $DestinationBlob.ICloudBlob.Delete("IncludeSnapshots")
            }
        }
    }
}

function Sync
{
    Param(
        [Parameter(Mandatory=$true)]
        $rootDir
    )
    Write-Output "Syncing containers in dir '$($rootDir)'"

    $DestinationContainers = Get-AzureStorageContainer -Context $DestinationStorageContext -ErrorAction Stop

    $SourceDirs = Get-ChildItem $rootDir | ?{ $_.PSIsContainer }
    $SourceDirs | foreach {
        $SourceDir = $_
        if ($SourceDir.Name -ne "parameters")
        {
            Write-Output " - Syncing container '$($SourceDir)'"
            $DestinationContainer = $DestinationContainers | where { $_.name -eq $SourceDir }
            if (-not $DestinationContainer) {
                Write-Output "   + Creating container '$($SourceDir)'"
                $DestinationContainer = New-AzureStorageContainer -Context $DestinationStorageContext -Name $SourceDir -ErrorAction Stop
            }
            SyncDir -rootDir $SourceDir -actDir $SourceDir -destContainer $DestinationContainer
            CleanContainer -rootDir $SourceDir -destContainer $DestinationContainer
        }
    }

    $DestinationContainers | foreach {
        $DestinationContainer = $_
        $SourceDir = $SourceDirs | where { $_.Name -eq $DestinationContainer.Name }
        if (-not $SourceDir) {
            Write-Output "   + Deleting container '$($DestinationContainer.Name)'"
            $tmp = Remove-AzureStorageContainer -Context $DestinationStorageContext -Name $DestinationContainer.Name -Force -ErrorAction Stop
        }
    }
}

if ($syncParent)
{
    Sync (Get-Item $PSScriptRoot).Parent.FullName
}
else
{
    Sync (Get-Item $PSScriptRoot).FullName
}
