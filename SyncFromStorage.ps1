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
$SourceStorageContext = New-AzureStorageContext -StorageAccountName $SourceStorageAccountName -StorageAccountKey $SourceStorageAccountKey -Endpoint $SourceStorageEndpoint -ErrorAction Stop

# Defining functions
function SyncContainer
{
    Param(
        [Parameter(Mandatory=$true)]
        $destDir,
        [Parameter(Mandatory=$true)]
        $sourceContainer
    )
    
    Write-Output "   * Syncing '$($sourceContainer.Name)'"

    $SourceBlobs = Get-AzureStorageBlob -Context $SourceStorageContext -Container $sourceContainer.Name
    $SourceBlobs | foreach {
        $SourceBlob = $_
        if (-not $SourceBlob.ICloudBlob.IsSnapshot) {
            Write-Output "     @Blob '$($SourceBlob.Name)'"

            <#$FilePath = $destDir + "\" + $SourceBlob.Name.Replace("/", "\")
            $DirPath = Split-Path -Path $FilePath
            if (-not (Test-Path $DirPath))
            {
		        New-Item -Path $DirPath -ItemType Directory
            }#>
            $tmp = $SourceBlob | Get-AzureStorageBlobContent -Destination $destDir -Force
        }
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

    $SourceBlobs = Get-AzureStorageBlob -Context $SourceStorageContext -Container $destContainer.Name
    $SourceBlobs | foreach {
        $SourceBlob = $_
        if (-not $SourceBlob.ICloudBlob.SnapshotTime) {
            Write-Output "     @Blob '$($SourceBlob.Name)'"

            $FilePath = $rootDir.FullName + "\" + $SourceBlob.Name
            if (-not (Test-Path $FilePath))
            {
		        Write-Output "      : Deleting blob"
                $SourceBlob.ICloudBlob.Delete("IncludeSnapshots")
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
    Write-Output "Syncing containers to dir '$($rootDir)'"

    $SourceContainers = Get-AzureStorageContainer -Context $SourceStorageContext -ErrorAction Stop

    $SourceContainers | foreach {
        $SourceContainer = $_
        if ($SourceContainer.Name -ne "parameters")
        {
            Write-Output " - Syncing container '$($SourceContainer.Name)'"
            $DestinationDir = "$($rootDir)\$($SourceContainer.Name)"
            if (-not (Test-Path $DestinationDir))
            {
		        Write-Output "   + Creating local dir for container"
                New-Item -ItemType Directory -Path $DestinationDir
            }
            SyncContainer -destDir $DestinationDir -sourceContainer $SourceContainer
            #CleanDirectory -rootDir $SourceDir -destContainer $DestinationDir
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
