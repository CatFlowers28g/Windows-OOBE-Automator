$files = @(
    "setup-oobe.ps1",
    "decrap.ps1"
)

foreach ($f in $files) {
    $path = Join-Path $PSScriptRoot "..\$f"
    if (-not (Test-Path $path)) {
        Write-Error "File not found: $path"
        exit 2
    }
    try {
        $content = Get-Content -Path $path -Raw
        [scriptblock]::Create($content) | Out-Null
        Write-Output "$f : PARSE_OK"
    } catch {
        Write-Error "$f : PARSE_ERROR - $($_.Exception.Message)"
        exit 1
    }
}
Write-Output "ALL_PARSE_OK"