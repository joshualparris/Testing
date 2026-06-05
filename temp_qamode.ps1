. 'c:\dev\testing\ExchangeLabManager.ps1' -NoRun -QAMode:$true
if ((Get-Variable -Name 'ELM_AutoConfirm' -Scope Global -ErrorAction SilentlyContinue).Value -and (Show-ConfirmationDialog -Title 'QA AutoConfirm' -Message 'Auto-confirm check' -AutoConfirm:$false)) { Write-Output 'TRUE' } else { Write-Output 'FALSE' }
