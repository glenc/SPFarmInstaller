# ---------------------------------------------------------------
# Utility Functions
# ---------------------------------------------------------------

function LoadSharePointPowershell {
    if ((Get-PsSnapin |?{$_.Name -eq "Microsoft.SharePoint.PowerShell"})-eq $null) {
        Add-PsSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue | Out-Null
    }
}

function Pause {
    #From http://www.microsoft.com/technet/scriptcenter/resources/pstips/jan08/pstip0118.mspx
    Write-Host "Press any key to exit..."
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function info {
    Write-Host -ForegroundColor Black $args
}

function debug {
    Write-Host -ForegroundColor Gray $args
}

function error {
    Error $args
}

function warn {
    Write-Warning $args
}

function show-progress {
    Write-Host -ForegroundColor Blue "." -NoNewLine
}