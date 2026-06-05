$scriptPathEscaped = 'c:\dev\testing\ExchangeLabManager.ps1'
$scriptBodyQAMode = ". '$scriptPathEscaped' -NoRun -QAMode:`$true`nif ((Get-Variable -Name 'ELM_AutoConfirm' -Scope Global -ErrorAction SilentlyContinue).Value -and (Show-ConfirmationDialog -Title 'QA AutoConfirm' -Message 'Auto-confirm check' -AutoConfirm:`$false)) { Write-Output 'TRUE' } else { Write-Output 'FALSE' }"
$tmp = 'c:\dev\testing\temp_qamode.ps1'
$scriptBodyQAMode | Set-Content -LiteralPath $tmp -Encoding UTF8
Get-Content -LiteralPath $tmp
Write-Output '---RUN---'
& $tmp
