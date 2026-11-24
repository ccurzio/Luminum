# Luminum "Local Time" Sensor (Windows)
# =====================================

$now = Get-Date
$tz  = [TimeZoneInfo]::Local
$dst = [int]$tz.IsDaylightSavingTime($now)
$ci  = [Globalization.CultureInfo]::InvariantCulture

$abbr = @{
	'Eastern Standard Time'		= 'EST','EDT'
	'US Eastern Standard Time'	= 'EST','EDT'
	'Central Standard Time'		= 'CST','CDT'
	'Mountain Standard Time'	= 'MST','MDT'
	'US Mountain Standard Time'	= 'MST','MST'
	'Pacific Standard Time'		= 'PST','PDT'
	'Alaskan Standard Time'		= 'AKST','AKDT'
	'Aleutian Standard Time'	= 'HST','HDT'
	'Hawaiian Standard Time'	= 'HST','HST'
	'Atlantic Standard Time'	= 'AST','ADT'
	'Newfoundland Standard Time'	= 'NST','NDT'
	'UTC'				= 'UTC','UTC'
	'Greenwich Standard Time'	= 'GMT','GMT'
	'GMT Standard Time'		= 'GMT','BST'
	'W. Europe Standard Time'	= 'CET','CEST'
	'Central Europe Standard Time'	= 'CET','CEST'
	'Central European Standard Time'= 'CET','CEST'
	'Romance Standard Time'		= 'CET','CEST'
	'E. Europe Standard Time'	= 'EET','EEST'
	'FLE Standard Time'		= 'EET','EEST'
	'GTB Standard Time'		= 'EET','EEST'
	'Israel Standard Time'		= 'IST','IDT'
	'Russian Standard Time'		= 'MSK','MSK'
	'South Africa Standard Time'	= 'SAST','SAST'
	'India Standard Time'		= 'IST','IST'
	'China Standard Time'		= 'CST','CST'
	'Tokyo Standard Time'		= 'JST','JST'
	'Korea Standard Time'		= 'KST','KST'
	'W. Australia Standard Time'	= 'AWST','AWST'
	'AUS Central Standard Time'	= 'ACST','ACST'
	'Cen. Australia Standard Time'	= 'ACST','ACDT'
	'E. Australia Standard Time'	= 'AEST','AEST'
	'AUS Eastern Standard Time'	= 'AEST','AEDT'
	'New Zealand Standard Time'	= 'NZST','NZDT'
	}

if ($abbr.ContainsKey($tz.Id)) { $zone = $abbr[$tz.Id][$dst] }
else {
	$off  = $tz.GetUtcOffset($now)
	$sign = if ($off -lt [TimeSpan]::Zero) { '-' } else { '+' }
	$zone = '{0}{1:hh}{1:mm}' -f $sign, $off
	}

$now.ToString('ddd MMM ', $ci) +
$now.Day.ToString().PadLeft(2) +
$now.ToString(' HH:mm:ss ', $ci) +
$zone + ' ' +
$now.ToString('yyyy', $ci)
