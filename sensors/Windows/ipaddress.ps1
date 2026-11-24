# Luminum "IP Address" Sensor (Windows)
# =====================================

(Get-NetIPAddress).IPAddress -replace '%.*' | Where-Object { $_ -notmatch '^(127\.|::1$)' }
