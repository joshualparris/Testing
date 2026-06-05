. 'c:\dev\testing\ExchangeLabManager.ps1' -NoRun -QAMode:$true
Write-Output "QAMode=$QAMode"
Write-Output "AutoConfirm=$Global:ELM_AutoConfirm"
Write-Output (Show-ConfirmationDialog -Title 'QA AutoConfirm' -Message 'Auto-confirm check' -AutoConfirm:$false)
