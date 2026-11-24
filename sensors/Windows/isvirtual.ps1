# Luminum "Is Virtual" Sensor (Windows)
# =====================================

try {
	$computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
	$manufacturer = $computer.Manufacturer
	$model = $computer.Model

	$vmPatterns = 'VMware|VirtualBox|KVM|QEMU|Xen|Microsoft Corporation|Parallels|Amazon EC2|Google'

	if ($manufacturer -match $vmPatterns -or
	$model -match 'Virtual|VMware|VirtualBox|KVM|QEMU|Xen|HVM|Parallels|EC2|Google') {
		Write-Output "TRUE"
		exit 0
		}

	Write-Output "FALSE"
	exit 1
	}

catch {
	Write-Error "Unable to determine virtualization status: $_"
	exit 2
	}

