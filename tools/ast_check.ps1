try {
    $script = Get-Content 'e:\Windows-OOBE-Automator\decrap.ps1' -Raw
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$null, [ref]$null)
    $funcs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($f in $funcs) {
        Write-Output (("FUNC: {0} @ {1}-{2}") -f $f.Name, $f.Extent.StartLineNumber, $f.Extent.EndLineNumber)
    }
    Write-Output 'AST_OK'
} catch {
    Write-Output ('ERROR: ' + $_.Exception.Message)
    if ($_.InvocationInfo) { Write-Output $_.InvocationInfo.PositionMessage }
    exit 2
}
