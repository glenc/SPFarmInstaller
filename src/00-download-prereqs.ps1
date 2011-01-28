# ---------------------------------------------------------------
# Download Prerequisites
# ---------------------------------------------------------------
# This script will download all prerequisites to your SharePoint
# server.
# ---------------------------------------------------------------

param
(
    [string]$InputFile = $(throw '- Need parameter input file (e.g. "farmConfig.xml")')
)

Import-Module BitsTransfer

# get destination path from config
[xml]$ConfigFile = Get-Content $InputFile
$Config = $ConfigFile.Configuration

$BitsPath = $Config.Installation.PathToBits
if (-not (Test-Path "$BitsPath" -Verbose)) {
	Write-Warning "Path to bits not found"
	break
}

$DestFolder = "$BitsPath\PrerequisiteInstallerFiles"
New-Item -ItemType Directory $DestFolder -ErrorAction SilentlyContinue

$UrlList = @{
	"Synchronization.msi" = "http://go.microsoft.com/fwlink/?LinkID=141237&clcid=0x409";
	"MSChart.exe" = "http://download.microsoft.com/download/c/c/4/cc4dcac6-ea60-4868-a8e0-62a8510aa747/MSChart.exe";
	"dotnetfx35.exe" = "http://go.microsoft.com/fwlink/?LinkId=131037";
	"Windows6.0-KB968930-x64.msu" = "http://download.microsoft.com/download/2/8/6/28686477-3242-4E96-9009-30B16BED89AF/Windows6.0-KB968930-x64.msu";
	"Windows6.1-KB974405-x64.msu" = "http://go.microsoft.com/fwlink/?LinkID=166363";
	"Windows6.0-KB976394-x64.msu" = "http://go.microsoft.com/fwlink/?linkID=160770";
	"Windows6.1-KB976462-v2-x64.msu" = "http://go.microsoft.com/fwlink/?LinkID=166231";
	"Windows6.0-KB974405-x64.msu" = "http://go.microsoft.com/fwlink/?LinkID=160381";
	"sqlncli.msi" = "http://go.microsoft.com/fwlink/?LinkId=123718&clcid=0x409";
	"SQLSERVER2008_ASADOMD10.msi" = "http://go.microsoft.com/fwlink/?LinkId=130651&clcid=0x409";
	"ADONETDataServices_v15_CTP2_RuntimeOnly.exe" = "http://go.microsoft.com/fwlink/?LinkId=158354";
	"iis7psprov_x64.msi" = "http://go.microsoft.com/?linkid=9655704";
	"rsSharePoint.msi" = "http://go.microsoft.com/fwlink/?LinkID=166379";
	"SpeechPlatformRuntime.msi" = "http://go.microsoft.com/fwlink/?LinkID=166378";
	"MSSpeech_SR_en-US_TELE.msi" = "http://go.microsoft.com/fwlink/?LinkID=166371"
}

foreach ($filename in $UrlList.Keys) {
	$url = $UrlList.Get_Item($filename)
	try {
		## Check if destination file already exists
		if (!(Test-Path "$DestFolder\$filename")) {
			## Begin download
			Start-BitsTransfer -Source $url -Destination $DestFolder\$filename -DisplayName "Downloading `'$filename`' to $DestFolder" -Priority High -Description "From $url..." -ErrorVariable err
			If ($err) {Throw ""}
		} else {
			Write-Host " - File $DestFileName already exists, skipping..."
		}
	} catch {
		Write-Warning " - An error occurred downloading `'$DestFileName`'"
		break
	}
}
## View the downloaded files in Windows Explorer
Invoke-Item $DestFolder
## Pause
Write-Host "- Downloads completed, press any key to exit..."
$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")