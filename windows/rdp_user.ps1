# Variables
$Username = "research"   # Replace with your desired username
$Password = "SecureP@ssw0rd!" # Replace with your desired password

# Enable Remote Desktop
Write-Host "Enabling Remote Desktop..." -ForegroundColor Green
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0

# Enable the RDP firewall rule
Write-Host "Enabling RDP firewall rule..." -ForegroundColor Green
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# # Disable NLA (Network Level Authentication)
# Write-Host "Disabling Network Level Authentication (NLA)..." -ForegroundColor Yellow
# Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0

# # Disable SSL
# Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "SecurityLayer" -Value 0
# Restart-Service -Name TermService -Force


# Create a new user
Write-Host "Creating a new user: $Username..." -ForegroundColor Green
$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
New-LocalUser -Name $Username -Password $SecurePassword -FullName "RDP User" -Description "User for RDP access"

# Add the user to the Remote Desktop Users group
Write-Host "Adding $Username to Remote Desktop Users group..." -ForegroundColor Green
Add-LocalGroupMember -Group "Remote Desktop Users" -Member $Username

Write-Host "Configuration complete! Remote Desktop is enabled, and user $Username has been added for RDP access." -ForegroundColor Green
