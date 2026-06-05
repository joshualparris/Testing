<#
.SYNOPSIS
    Send a benign HTML test email to verify whether OWA XSS mitigation is active.
.DESCRIPTION
    This script sends a harmless HTML payload that is intended only to confirm whether
    Exchange OWA is blocking XSS-like content via the applied CSP/IIS rewrite rules.
#>

param(
    [Parameter(Mandatory=$false)][string]$Sender = 'attacker@yourlab.local',
    [Parameter(Mandatory=$false)][string]$Recipient = 'victim@yourlab.local',
    [Parameter(Mandatory=$false)][string]$SmtpServer = '192.168.100.10'
)

Write-Host "Sending benign control test email from $Sender to $Recipient via SMTP server $SmtpServer..."

$Body = @"
<h2>OWA XSS Control Test</h2>
<p>This is a safe lab validation payload. If the browser executes active HTML, a harmless alert should appear.</p>
<img src="x" onerror="alert('XSS_Test_Triggered')" />
"@

Send-MailMessage -From $Sender -To $Recipient -Subject 'OWA XSS Lab Validation' -Body $Body -BodyAsHtml -SmtpServer $SmtpServer -ErrorAction Stop

Write-Host "Test email sent. Open the message in OWA and watch for the alert or a CSP block in the browser console."
