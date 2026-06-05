function f { param([switch]$x); Write-Output $x; Write-Output ($x -is [switch]); Write-Output ([bool]$x); }; f -x:$false
