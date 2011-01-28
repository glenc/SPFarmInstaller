# ---------------------------------------------------------------
# Security Functions
# ---------------------------------------------------------------

function GetSecureString([string]$str) {
    return Convert-ToSecureString "$str" -AsPlaintext -Force
}

function GetCredential([string]$accountName, $config) {
    $account = $config.ManagedAccounts.Account | Where-Object {$_.name -eq $accountName}

    if ($account.username -eq $null -or $account.username -eq "" -or $account.password -eq $null -or $account.password -eq "") {
        return $host.ui.PromptForCredential("SharePoint Managed Account ($accountName)", "Enter the password for this account", $account.username, "NetBiosUserName")
    } else {
        return New-Object System.Management.Automation.PsCredential $account.username,$account.password
    }
}

function GetOrCreateManagedAccount([string]$accountName, $config) {
    $account = $config.ManagedAccounts.Account | Where-Object {$_.name -eq $accountName}
    $managedAccount = Get-SPManagedAccount | Where-Object {$_.UserName -eq $account.username}

    if ($managedAccount -eq $null) {
        $cred = GetCredential $accountName $config
        New-SPManagedAccount -Credential $cred | Out-Null
        $managedAccount = Get-SPManagedAccount | Where-Object {$_.UserName -eq $account.username}
    }
    
    return $managedAccount
}