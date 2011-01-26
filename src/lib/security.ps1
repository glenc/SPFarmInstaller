# ---------------------------------------------------------------
# Security Functions
# ---------------------------------------------------------------

function GetSecureString([string]$str) {
    return Convert-ToSecureString "$str" -AsPlaintext -Force
}

function GetCredential([string]$accountName, [string]$accountPassword) {
    if ($accountPassword -eq $null) {
        return $host.ui.PromptForCredential("SharePoint Managed Account", "Enter the password for this account", "$accountName", "NetBiosUserName")
    } else {
        return New-Object System.Management.Automation.PsCredential $accountName,$accountPassword
    }
}