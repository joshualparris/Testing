$Global:ELM_NetworkOps = New-Object System.Collections.Generic.List[int]
function Test {
    if ($Global:ELM_NetworkOps) {
        $Global:ELM_NetworkOps.Add(1)
    }
}
Test
Write-Output $Global:ELM_NetworkOps.Count
