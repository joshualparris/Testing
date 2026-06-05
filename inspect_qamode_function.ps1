. 'c:\dev\testing\ExchangeLabManager.ps1' -NoRun -QAMode:$true
Get-Command Show-ConfirmationDialog | Format-List Name,Source,CommandType
Write-Output "QAMode=$QAMode"
Write-Output "AutoConfirm=$Global:ELM_AutoConfirm"
Show-ConfirmationDialog -Title 'QA AutoConfirm' -Message 'Auto-confirm check' -AutoConfirm:$false
