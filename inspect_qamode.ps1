$scriptPathEscaped = 'c:\dev\testing\ExchangeLabManager.ps1'
$innerQAMode = ". '$scriptPathEscaped' -NoRun -QAMode:`$true; Write-Output `"QAMode=`$QAMode`"; Write-Output `"AutoConfirm=`$Global:ELM_AutoConfirm`"; if ((Get-Variable -Name 'ELM_AutoConfirm' -Scope Global -ErrorAction SilentlyContinue).Value -and (Show-ConfirmationDialog -Title 'QA AutoConfirm' -Message 'Auto-confirm check' -AutoConfirm:`$false)) { Write-Output 'TRUE' } else { Write-Output 'FALSE' }"
Write-Output 'STRING:'
Write-Output $innerQAMode
Write-Output 'ENCODED:'
Write-Output ([Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($innerQAMode)))
Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',([Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($innerQAMode))) -NoNewWindow -Wait -RedirectStandardOutput 'c:\dev\testing\inspect_qamode_out.txt'
Write-Output 'PROCESS OUTPUT:'
Get-Content 'c:\dev\testing\inspect_qamode_out.txt' | Write-Output
