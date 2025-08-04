# Test script to simulate Windows local mode behavior
# This script extracts and tests the critical logic from setup-windows.ps1 for local mode

param(
    [switch]$Local = $false,
    [switch]$Development = $false,
    [switch]$Server = $false,
    [switch]$SkipFirewall = $false
)

# Test logging functions
function Write-Info { 
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success { 
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning { 
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

# Simulate the firewall configuration logic from setup-windows.ps1
function Test-FirewallConfiguration {
    Write-Info "Testing Firewall Configuration Logic"
    Write-Info "Parameters: Local=$Local, Development=$Development, Server=$Server, SkipFirewall=$SkipFirewall"
    
    if ($SkipFirewall) {
        Write-Info "Skipping firewall configuration due to -SkipFirewall parameter"
        return "SKIPPED_EXPLICIT"
    }
    
    # Determine deployment mode from parameters (same logic as setup-windows.ps1)
    $deploymentMode = ""
    if ($Server) {
        $deploymentMode = "1"
    } elseif ($Local -or $Development) {
        $deploymentMode = "2"
    }
    
    Write-Info "Deployment mode determined: '$deploymentMode'"
    
    # If no parameter specified, would prompt user (but we'll simulate)
    if ([string]::IsNullOrEmpty($deploymentMode)) {
        Write-Info "No deployment mode specified - would prompt user in real script"
        $deploymentMode = "1"  # Default to server mode
    }
    
    switch ($deploymentMode) {
        "1" {
            Write-Info "Server deployment mode selected - would configure firewall..."
            return "SERVER_FIREWALL_CONFIGURED"
        }
        "2" {
            Write-Info "Local development mode selected - skipping firewall configuration"
            Write-Info "Assuming local firewall/router handles port access"
            return "LOCAL_FIREWALL_SKIPPED"
        }
        default {
            Write-Warning "Invalid selection. Defaulting to server deployment mode."
            return "DEFAULT_SERVER_FIREWALL"
        }
    }
}

# Test different parameter combinations
Write-Host "=== Windows Local Mode Behavior Test ===" -ForegroundColor Magenta
Write-Host ""

Write-Host "Test 1: Local mode (-Local)" -ForegroundColor Yellow
$result1 = Test-FirewallConfiguration -Local
Write-Host "Result: $result1" -ForegroundColor $(if ($result1 -eq "LOCAL_FIREWALL_SKIPPED") { "Green" } else { "Red" })
Write-Host ""

Write-Host "Test 2: Development mode (-Development)" -ForegroundColor Yellow
$result2 = Test-FirewallConfiguration -Development
Write-Host "Result: $result2" -ForegroundColor $(if ($result2 -eq "LOCAL_FIREWALL_SKIPPED") { "Green" } else { "Red" })
Write-Host ""

Write-Host "Test 3: Server mode (-Server)" -ForegroundColor Yellow
$result3 = Test-FirewallConfiguration -Server
Write-Host "Result: $result3" -ForegroundColor $(if ($result3 -eq "SERVER_FIREWALL_CONFIGURED") { "Green" } else { "Red" })
Write-Host ""

Write-Host "Test 4: No parameters (default behavior)" -ForegroundColor Yellow
$result4 = Test-FirewallConfiguration
Write-Host "Result: $result4" -ForegroundColor $(if ($result4 -eq "DEFAULT_SERVER_FIREWALL") { "Green" } else { "Red" })
Write-Host ""

Write-Host "Test 5: Explicit skip (-SkipFirewall)" -ForegroundColor Yellow
$result5 = Test-FirewallConfiguration -SkipFirewall
Write-Host "Result: $result5" -ForegroundColor $(if ($result5 -eq "SKIPPED_EXPLICIT") { "Green" } else { "Red" })
Write-Host ""

# Test authentication behavior simulation
function Test-AuthenticationBehavior {
    param([switch]$Local)
    
    Write-Info "Testing Authentication Behavior"
    
    if ($Local) {
        Write-Info "Local development mode detected"
        Write-Info "GitHub authentication will use device code flow"
        Write-Info "Message will indicate local development mode"
        return "LOCAL_AUTH_DEVICE_CODE"
    } else {
        Write-Info "Server mode detected"
        Write-Info "GitHub authentication will use device code flow"
        Write-Info "Message will indicate server deployment mode"
        return "SERVER_AUTH_DEVICE_CODE"
    }
}

Write-Host "Test 6: Authentication behavior in local mode" -ForegroundColor Yellow
$result6 = Test-AuthenticationBehavior -Local
Write-Host "Result: $result6" -ForegroundColor Green
Write-Host ""

Write-Host "Test 7: Authentication behavior in server mode" -ForegroundColor Yellow
$result7 = Test-AuthenticationBehavior
Write-Host "Result: $result7" -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "=== Test Summary ===" -ForegroundColor Magenta
$tests = @(
    @{Name="Local Mode Firewall"; Expected="LOCAL_FIREWALL_SKIPPED"; Actual=$result1},
    @{Name="Development Mode Firewall"; Expected="LOCAL_FIREWALL_SKIPPED"; Actual=$result2},
    @{Name="Server Mode Firewall"; Expected="SERVER_FIREWALL_CONFIGURED"; Actual=$result3},
    @{Name="Default Mode Firewall"; Expected="DEFAULT_SERVER_FIREWALL"; Actual=$result4},
    @{Name="Skip Firewall Parameter"; Expected="SKIPPED_EXPLICIT"; Actual=$result5}
)

$passed = 0
$total = $tests.Count

foreach ($test in $tests) {
    $status = if ($test.Expected -eq $test.Actual) { "PASS"; $passed++ } else { "FAIL" }
    $color = if ($status -eq "PASS") { "Green" } else { "Red" }
    Write-Host "$($test.Name): $status" -ForegroundColor $color
}

Write-Host ""
Write-Host "Overall Result: $passed/$total tests passed" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Red" })

if ($passed -eq $total) {
    Write-Success "All tests passed! Windows local mode behavior is correct."
    Write-Info "Key behaviors verified:"
    Write-Info "  - Local mode (-Local) skips firewall configuration"
    Write-Info "  - Development mode (-Development) skips firewall configuration"
    Write-Info "  - Server mode (-Server) configures firewall"
    Write-Info "  - Default behavior configures firewall"
    Write-Info "  - Explicit skip (-SkipFirewall) works correctly"
} else {
    Write-Warning "Some tests failed! Review the logic in setup-windows.ps1"
}