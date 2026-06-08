$errors = @()

# Scan repository root (parent of tools) and tools folder
$repoRoot = Split-Path -Parent $PSScriptRoot
Get-ChildItem -Path $repoRoot -Recurse -Filter *.ps1 -File | ForEach-Object {
    $full = $_.FullName
    try {
        $content = Get-Content -Path $full -Raw
        [scriptblock]::Create($content) | Out-Null
        Write-Output "PARSE_OK: $full"
    } catch {
        Write-Error "PARSE_ERROR: $full - $($_.Exception.Message)"
        $errors += @{ File = $full; Message = $_.Exception.Message }
    }
}

if ($errors.Count -gt 0) {
    Write-Output "PARSE_ERRORS=$($errors.Count)"
    exit 1
} else {
    Write-Output "ALL_PARSERS_OK"
    exit 0
}
