# ---------------------------------------------------------------
# Create a new SharePoint Farm
# ---------------------------------------------------------------
# This script will create a new farm - primarily the config db
# and central admin content db
# ---------------------------------------------------------------

function CreateFarm {
    $passPhrase = Convert-ToSecureString "$FarmPassPhrase" -AsPlaintext -Force
    $cred = GetCredential $FarmSvcAccount $FarmSvcPwd
    New-SPConfigurationDatabase -DatabaseName "$ConfigDB" -DatabaseServer "$DatabaseServer" -AdministrationContentDatabaseName "$CentralAdminContentDB" -Passphrase $passPhrase -FarmCredentials $cred
	if (-not $?) {throw}
	else {$farmMessage = "Done creating configuration database for farm."}
}

CreateFarm