. 'c:\dev\testing\ExchangeLabManager.ps1' -NoRun -QAMode:$true
Write-Output "QAMode=$QAMode"
if (Get-Variable -Name QAMode -Scope Script -ErrorAction SilentlyContinue) {
    $scriptQAMode = (Get-Variable -Name QAMode -Scope Script -ErrorAction SilentlyContinue).Value
    Write-Output "ScriptScopeQAMode=$scriptQAMode Type=$($scriptQAMode.GetType().FullName)"
}
$var = (Get-Variable -Name 'ELM_AutoConfirm' -Scope Global -ErrorAction SilentlyContinue).Value
Write-Output "GLOBAUTOCONFIRM=$var Type=$($var.GetType().FullName)"
$call = Show-ConfirmationDialog -Title 'QA AutoConfirm' -Message 'Auto-confirm check' -AutoConfirm:$false
Write-Output "CALL=$call Type=$($call.GetType().FullName)"
Write-Output "AND=$($var -and $call)"
