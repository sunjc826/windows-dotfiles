Write-Host "My profile is at $profile"
Set-PSReadlineKeyHandler -Key Tab -Function Complete
# Get-PSReadlineKeyHandler | Out-String -Stream | Select-String 'Tab'
Set-PSReadlineOption -BellStyle None
