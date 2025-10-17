# Install SQL Client (sqlcmd)
$msiUrl = "https://github.com/microsoft/go-sqlcmd/releases/download/v1.8.2/sqlcmd-amd64.msi"
$outputPath = "$env:TEMP\sqlcmd-amd64.msi"

Write-Host "Downloading sqlcmd from $msiUrl..."
Invoke-WebRequest -Uri $msiUrl -OutFile $outputPath

Write-Host "Installing sqlcmd from $outputPath..."
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$outputPath`" /qn" -Wait

Write-Host "sqlcmd installation complete."

$newPath = "C:\Program Files\SqlCmd\"
$currentPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
$newPathValue = "$currentPath;$newPath"
[System.Environment]::SetEnvironmentVariable("Path", $newPathValue, [System.EnvironmentVariableTarget]::Machine)

# Install AD DS (Only for Managed AD Debugging)
Install-WindowsFeature -name AD-Domain-Services -IncludeManagementTools
Write-Host "AD-Domain-Services installed for debugging"