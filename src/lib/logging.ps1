# ---------------------------------------------------------------
# Logging Functions
# ---------------------------------------------------------------

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