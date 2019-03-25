<#
.SYNOPSIS
    Starts the language and debug services from the PowerShellEditorServices module.
.DESCRIPTION
    PowerShell Editor Services Bootstrapper Script
    ----------------------------------------------
    This script contains startup logic for the PowerShell Editor Services
    module when launched by an editor.  It handles the following tasks:

    - Verifying the existence of dependencies like PowerShellGet
    - Verifying that the expected version of the PowerShellEditorServices module is installed
    - Installing the PowerShellEditorServices module if confirmed by the user
    - Creating named pipes for the language and debug services to use (if using named pipes)
    - Starting the language and debug services from the PowerShellEditorServices module
.INPUTS
    None
.OUTPUTS
    None
.NOTES
    If editor integration authors make modifications to this script, please
    consider contributing changes back to the canonical version of this script
    at the PowerShell Editor Services GitHub repository:
    https://github.com/PowerShell/PowerShellEditorServices/blob/master/module/PowerShellEditorServices/Start-EditorServices.ps1'
#>
[CmdletBinding(DefaultParameterSetName="NamedPipe")]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $HostName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $HostProfileId,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $HostVersion,

    [ValidateNotNullOrEmpty()]
    [string]
    $BundledModulesPath,

    [ValidateNotNullOrEmpty()]
    $LogPath,

    [ValidateSet("Diagnostic", "Normal", "Verbose", "Error")]
    $LogLevel,

	[Parameter(Mandatory=$true)]
	[ValidateNotNullOrEmpty()]
	[string]
	$SessionDetailsPath,

    [switch]
    $EnableConsoleRepl,

    [switch]
    $DebugServiceOnly,

    [string[]]
    $AdditionalModules,

    [string[]]
    $FeatureFlags,

    [switch]
    $WaitForDebugger,

    [switch]
    $ConfirmInstall,

    [Parameter(ParameterSetName="Stdio", Mandatory=$true)]
    [switch]
    $Stdio,

    [Parameter(ParameterSetName="NamedPipe")]
    [string]
    $LanguageServicePipeName = $null,

    [Parameter(ParameterSetName="NamedPipe")]
    [string]
    $DebugServicePipeName = $null,

    [Parameter(ParameterSetName="NamedPipeSimplex")]
    [switch]
    $SplitInOutPipes,

    [Parameter(ParameterSetName="NamedPipeSimplex")]
    [string]
    $LanguageServiceInPipeName,

    [Parameter(ParameterSetName="NamedPipeSimplex")]
    [string]
    $LanguageServiceOutPipeName,

    [Parameter(ParameterSetName="NamedPipeSimplex")]
    [string]
    $DebugServiceInPipeName = $null,

    [Parameter(ParameterSetName="NamedPipeSimplex")]
    [string]
    $DebugServiceOutPipeName = $null
)

$DEFAULT_USER_MODE = "600"

if ($LogLevel -eq "Diagnostic") {
    if (!$Stdio.IsPresent) {
        $VerbosePreference = 'Continue'
    }
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
    $logFileName = [System.IO.Path]::GetFileName($LogPath)
    Start-Transcript (Join-Path (Split-Path $LogPath -Parent) "$scriptName-$logFileName") -Force | Out-Null
}

function LogSection([string]$msg) {
    Write-Verbose "`n#-- $msg $('-' * ([Math]::Max(0, 73 - $msg.Length)))"
}

function Log([string[]]$msg) {
    $msg | Write-Verbose
}

function ExitWithError($errorString) {
    Write-Host -ForegroundColor Red "`n`n$errorString"

    # Sleep for a while to make sure the user has time to see and copy the
    # error message
    Start-Sleep -Seconds 300

    exit 1;
}

function WriteSessionFile($sessionInfo) {
    $sessionInfoJson = Microsoft.PowerShell.Utility\ConvertTo-Json -InputObject $sessionInfo -Compress
    Log "Writing session file with contents:"
    Log $sessionInfoJson
    $sessionInfoJson | Microsoft.PowerShell.Management\Set-Content -Force -Path "$SessionDetailsPath" -ErrorAction Stop
}

# Are we running in PowerShell 2 or earlier?
if ($PSVersionTable.PSVersion.Major -le 2) {
    # No ConvertTo-Json on PSv2 and below, so write out the JSON manually
    "{`"status`": `"failed`", `"reason`": `"unsupported`", `"powerShellVersion`": `"$($PSVersionTable.PSVersion.ToString())`"}" |
        Microsoft.PowerShell.Management\Set-Content -Force -Path "$SessionDetailsPath" -ErrorAction Stop

    ExitWithError "Unsupported PowerShell version $($PSVersionTable.PSVersion), language features are disabled."
}


if ($host.Runspace.LanguageMode -eq 'ConstrainedLanguage') {
    WriteSessionFile @{
        "status" = "failed"
        "reason" = "languageMode"
        "detail" = $host.Runspace.LanguageMode.ToString()
    }

    ExitWithError "PowerShell is configured with an unsupported LanguageMode (ConstrainedLanguage), language features are disabled."
}

# net451 and lower are not supported, only net452 and up
if ($PSVersionTable.PSVersion.Major -le 5) {
    $net452Version = 379893
    $dotnetVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\").Release
    if ($dotnetVersion -lt $net452Version) {
        Write-SessionFile @{
            status = failed
            reason = "netversion"
            detail = "$netVersion"
        }

        ExitWithError "Your .NET version is too low. Upgrade to net452 or higher to run the PowerShell extension."
    }
}

# If PSReadline is present in the session, remove it so that runspace
# management is easier
if ((Microsoft.PowerShell.Core\Get-Module PSReadline).Count -gt 0) {
    LogSection "Removing PSReadLine module"
    Microsoft.PowerShell.Core\Remove-Module PSReadline -ErrorAction SilentlyContinue
}

# This variable will be assigned later to contain information about
# what happened while attempting to launch the PowerShell Editor
# Services host
$resultDetails = $null;

function Test-ModuleAvailable($ModuleName, $ModuleVersion) {
    Log "Testing module availability $ModuleName $ModuleVersion"

    $modules = Microsoft.PowerShell.Core\Get-Module -ListAvailable $moduleName
    if ($null -ne $modules) {
        if ($null -ne $ModuleVersion) {
            foreach ($module in $modules) {
                if ($module.Version.Equals($moduleVersion)) {
                    Log "$ModuleName $ModuleVersion found"
                    return $true;
                }
            }
        }
        else {
            Log "$ModuleName $ModuleVersion found"
            return $true;
        }
    }

    Log "$ModuleName $ModuleVersion NOT found"
    return $false;
}

function New-NamedPipeName {
    # We try 10 times to find a valid pipe name
    for ($i = 0; $i -lt 10; $i++) {
        $PipeName = "PSES_$([System.IO.Path]::GetRandomFileName())"

        if ((Test-NamedPipeName -PipeName $PipeName)) {
            return $PipeName
        }
    }

    ExitWithError "Could not find valid a pipe name."
}

function Get-NamedPipePath {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $PipeName
    )

    if (($PSVersionTable.PSVersion.Major -le 5) -or $IsWindows) {
        return "\\.\pipe\$PipeName";
    }
    else {
        # Windows uses NamedPipes where non-Windows platforms use Unix Domain Sockets.
        # the Unix Domain Sockets live in the tmp directory and are prefixed with "CoreFxPipe_"
        return (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "CoreFxPipe_$PipeName")
    }
}

# Returns True if it's a valid pipe name
# A valid pipe name is a file that does not exist either
# in the temp directory (macOS & Linux) or in the pipe directory (Windows)
function Test-NamedPipeName {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $PipeName
    )

    $path = Get-NamedPipePath -PipeName $PipeName
    return !(Test-Path $path)
}

function Set-NamedPipeMode {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $PipeFile
    )

    if (($PSVersionTable.PSVersion.Major -le 5) -or $IsWindows) {
        return
    }

    chmod $DEFAULT_USER_MODE $PipeFile

    if ($IsLinux) {
        $mode = /usr/bin/stat -c "%a" $PipeFile
    }
    elseif ($IsMacOS) {
        $mode = /usr/bin/stat -f "%A" $PipeFile
    }

    if ($mode -ne $DEFAULT_USER_MODE) {
        ExitWithError "Permissions to the pipe file were not set properly. Expected: $DEFAULT_USER_MODE Actual: $mode for file: $PipeFile"
    }
}

LogSection "Console Encoding"
Log $OutputEncoding

function Get-ValidatedNamedPipeName {
    param(
        [string]
        $PipeName
    )

    # If no PipeName is passed in, then we create one that's guaranteed to be valid
    if (!$PipeName) {
        $PipeName = New-NamedPipeName
    }
    elseif (!(Test-NamedPipeName -PipeName $PipeName)) {
        ExitWithError "Pipe name supplied is already in use: $PipeName"
    }

    return $PipeName
}

function Set-PipeFileResult {
    param (
        [Hashtable]
        $ResultTable,

        [string]
        $PipeNameKey,

        [string]
        $PipeNameValue
    )

    $ResultTable[$PipeNameKey] = Get-NamedPipePath -PipeName $PipeNameValue
    if (($PSVersionTable.PSVersion.Major -ge 6) -and ($IsLinux -or $IsMacOS)) {
        Set-NamedPipeMode -PipeFile $ResultTable[$PipeNameKey]
    }
}

# Add BundledModulesPath to $env:PSModulePath
if ($BundledModulesPath) {
    $env:PSModulePath = $env:PSModulePath.TrimEnd([System.IO.Path]::PathSeparator) + [System.IO.Path]::PathSeparator + $BundledModulesPath
    LogSection "Updated PSModulePath to:"
    Log ($env:PSModulePath -split [System.IO.Path]::PathSeparator)
}

LogSection "Check required modules available"
# Check if PowerShellGet module is available
if ((Test-ModuleAvailable "PowerShellGet") -eq $false) {
    Log "Failed to find PowerShellGet module"
    # TODO: WRITE ERROR
}

try {
    LogSection "Start up PowerShellEditorServices"
    Log "Importing PowerShellEditorServices"

    Microsoft.PowerShell.Core\Import-Module PowerShellEditorServices -ErrorAction Stop

    if ($EnableConsoleRepl) {
        Write-Host "PowerShell Integrated Console`n"
    }

    $resultDetails = @{
        "status" = "not started";
        "languageServiceTransport" = $PSCmdlet.ParameterSetName;
        "debugServiceTransport" = $PSCmdlet.ParameterSetName;
    };

    # Create the Editor Services host
    Log "Invoking Start-EditorServicesHost"
    # There could be only one service on Stdio channel
    # Locate available port numbers for services
    switch ($PSCmdlet.ParameterSetName) {
        "Stdio" {
            $editorServicesHost = Start-EditorServicesHost `
                                        -HostName $HostName `
                                        -HostProfileId $HostProfileId `
                                        -HostVersion $HostVersion `
                                        -LogPath $LogPath `
                                        -LogLevel $LogLevel `
                                        -AdditionalModules $AdditionalModules `
                                        -Stdio `
                                        -BundledModulesPath $BundledModulesPath `
                                        -EnableConsoleRepl:$EnableConsoleRepl.IsPresent `
                                        -DebugServiceOnly:$DebugServiceOnly.IsPresent `
                                        -WaitForDebugger:$WaitForDebugger.IsPresent
            break
        }

        "NamedPipeSimplex" {
            $LanguageServiceInPipeName = Get-ValidatedNamedPipeName $LanguageServiceInPipeName
            $LanguageServiceOutPipeName = Get-ValidatedNamedPipeName $LanguageServiceOutPipeName
            $DebugServiceInPipeName = Get-ValidatedNamedPipeName $DebugServiceInPipeName
            $DebugServiceOutPipeName = Get-ValidatedNamedPipeName $DebugServiceOutPipeName

            $editorServicesHost = Start-EditorServicesHost `
                                        -HostName $HostName `
                                        -HostProfileId $HostProfileId `
                                        -HostVersion $HostVersion `
                                        -LogPath $LogPath `
                                        -LogLevel $LogLevel `
                                        -AdditionalModules $AdditionalModules `
                                        -LanguageServiceInNamedPipe $LanguageServiceInPipeName `
                                        -LanguageServiceOutNamedPipe $LanguageServiceOutPipeName `
                                        -DebugServiceInNamedPipe $DebugServiceInPipeName `
                                        -DebugServiceOutNamedPipe $DebugServiceOutPipeName `
                                        -BundledModulesPath $BundledModulesPath `
                                        -EnableConsoleRepl:$EnableConsoleRepl.IsPresent `
                                        -DebugServiceOnly:$DebugServiceOnly.IsPresent `
                                        -WaitForDebugger:$WaitForDebugger.IsPresent

            Set-PipeFileResult $resultDetails "languageServiceReadPipeName" $LanguageServiceInPipeName
            Set-PipeFileResult $resultDetails "languageServiceWritePipeName" $LanguageServiceOutPipeName
            Set-PipeFileResult $resultDetails "debugServiceReadPipeName" $DebugServiceInPipeName
            Set-PipeFileResult $resultDetails "debugServiceWritePipeName" $DebugServiceOutPipeName
            break
        }

        Default {
            $LanguageServicePipeName = Get-ValidatedNamedPipeName $LanguageServicePipeName
            $DebugServicePipeName = Get-ValidatedNamedPipeName $DebugServicePipeName

            $editorServicesHost = Start-EditorServicesHost `
                                        -HostName $HostName `
                                        -HostProfileId $HostProfileId `
                                        -HostVersion $HostVersion `
                                        -LogPath $LogPath `
                                        -LogLevel $LogLevel `
                                        -AdditionalModules $AdditionalModules `
                                        -LanguageServiceNamedPipe $LanguageServicePipeName `
                                        -DebugServiceNamedPipe $DebugServicePipeName `
                                        -BundledModulesPath $BundledModulesPath `
                                        -EnableConsoleRepl:$EnableConsoleRepl.IsPresent `
                                        -DebugServiceOnly:$DebugServiceOnly.IsPresent `
                                        -WaitForDebugger:$WaitForDebugger.IsPresent

            Set-PipeFileResult $resultDetails "languageServicePipeName" $LanguageServicePipeName
            Set-PipeFileResult $resultDetails "debugServicePipeName" $DebugServicePipeName
            break
        }
    }

    # TODO: Verify that the service is started
    Log "Start-EditorServicesHost returned $editorServicesHost"

    $resultDetails["status"] = "started"

    # Notify the client that the services have started
    WriteSessionFile $resultDetails

    Log "Wrote out session file"
}
catch [System.Exception] {
    $e = $_.Exception;
    $errorString = ""

    Log "ERRORS caught starting up EditorServicesHost"

    while ($null -ne $e) {
        $errorString = $errorString + ($e.Message + "`r`n" + $e.StackTrace + "`r`n")
        $e = $e.InnerException;
        Log $errorString
    }

    ExitWithError ("An error occurred while starting PowerShell Editor Services:`r`n`r`n" + $errorString)
}

try {
    # Wait for the host to complete execution before exiting
    LogSection "Waiting for EditorServicesHost to complete execution"
    $editorServicesHost.WaitForCompletion()
    Log "EditorServicesHost has completed execution"
}
catch [System.Exception] {
    $e = $_.Exception;
    $errorString = ""

    Log "ERRORS caught while waiting for EditorServicesHost to complete execution"

    while ($null -ne $e) {
        $errorString = $errorString + ($e.Message + "`r`n" + $e.StackTrace + "`r`n")
        $e = $e.InnerException;
        Log $errorString
    }
}

# SIG # Begin signature block
# MIIjhgYJKoZIhvcNAQcCoIIjdzCCI3MCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDn0vfZHFgqQ+xa
# HAgtAdhJlpnrAnpQXcKpYYKL7YHw0aCCDYEwggX/MIID56ADAgECAhMzAAABA14l
# HJkfox64AAAAAAEDMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMTgwNzEyMjAwODQ4WhcNMTkwNzI2MjAwODQ4WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDRlHY25oarNv5p+UZ8i4hQy5Bwf7BVqSQdfjnnBZ8PrHuXss5zCvvUmyRcFrU5
# 3Rt+M2wR/Dsm85iqXVNrqsPsE7jS789Xf8xly69NLjKxVitONAeJ/mkhvT5E+94S
# nYW/fHaGfXKxdpth5opkTEbOttU6jHeTd2chnLZaBl5HhvU80QnKDT3NsumhUHjR
# hIjiATwi/K+WCMxdmcDt66VamJL1yEBOanOv3uN0etNfRpe84mcod5mswQ4xFo8A
# DwH+S15UD8rEZT8K46NG2/YsAzoZvmgFFpzmfzS/p4eNZTkmyWPU78XdvSX+/Sj0
# NIZ5rCrVXzCRO+QUauuxygQjAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUR77Ay+GmP/1l1jjyA123r3f3QP8w
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDM3OTY1MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAn/XJ
# Uw0/DSbsokTYDdGfY5YGSz8eXMUzo6TDbK8fwAG662XsnjMQD6esW9S9kGEX5zHn
# wya0rPUn00iThoj+EjWRZCLRay07qCwVlCnSN5bmNf8MzsgGFhaeJLHiOfluDnjY
# DBu2KWAndjQkm925l3XLATutghIWIoCJFYS7mFAgsBcmhkmvzn1FFUM0ls+BXBgs
# 1JPyZ6vic8g9o838Mh5gHOmwGzD7LLsHLpaEk0UoVFzNlv2g24HYtjDKQ7HzSMCy
# RhxdXnYqWJ/U7vL0+khMtWGLsIxB6aq4nZD0/2pCD7k+6Q7slPyNgLt44yOneFuy
# bR/5WcF9ttE5yXnggxxgCto9sNHtNr9FB+kbNm7lPTsFA6fUpyUSj+Z2oxOzRVpD
# MYLa2ISuubAfdfX2HX1RETcn6LU1hHH3V6qu+olxyZjSnlpkdr6Mw30VapHxFPTy
# 2TUxuNty+rR1yIibar+YRcdmstf/zpKQdeTr5obSyBvbJ8BblW9Jb1hdaSreU0v4
# 6Mp79mwV+QMZDxGFqk+av6pX3WDG9XEg9FGomsrp0es0Rz11+iLsVT9qGTlrEOla
# P470I3gwsvKmOMs1jaqYWSRAuDpnpAdfoP7YO0kT+wzh7Qttg1DO8H8+4NkI6Iwh
# SkHC3uuOW+4Dwx1ubuZUNWZncnwa6lL2IsRyP64wggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIVWzCCFVcCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAQNeJRyZH6MeuAAAAAABAzAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgX9RMAUnr
# 1TCe22BA47+m4IAUebuLO1tQbKY9GRq7tHIwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQAVgW21kftf8u23zFmUVUGqRTcb2yYavWsqDFP0z+cE
# wZ0Epn8fR3peCaCqNfN0s4d1KeYBnKN4MIRt0N03GuVRrZ7S+HkHK7jDFKuk1omB
# 7BSc3VeoaU2JMrgfodCP5HXlxkl7sIAmAOtF1Kch/gV80WVHRLE9zPlwPm8/jDmS
# yWaqKZIYtUzQwsrCu4jeuiXentI7eJ1i/btCWFk02Wh/cQ0PU5tTkUVSyKbKvLlG
# ixekep+QRgYuVqNiAJY9mK5h/u41G2aGyHibvzq+nRNKDBzrSDUtSY1TuBTXlZwV
# 2wwLosly0K4lWLTFgqQD6V9p/LCu3tc4bG0ecsrQx7kfoYIS5TCCEuEGCisGAQQB
# gjcDAwExghLRMIISzQYJKoZIhvcNAQcCoIISvjCCEroCAQMxDzANBglghkgBZQME
# AgEFADCCAVEGCyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIA4JFO3OKVhl/OkgchhoTFBgD/OiJfhtfXt38nGR
# 7JZVAgZcPdMGOiAYEzIwMTkwMTIzMTY1NzIxLjM2OVowBIACAfSggdCkgc0wgcox
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOjQ5QkMtRTM3QS0yMzNDMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloIIOPDCCBPEwggPZoAMCAQICEzMAAADu+MX1NjuBHIwAAAAAAO4w
# DQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcN
# MTgxMDI0MjExNDE1WhcNMjAwMTEwMjExNDE1WjCByjELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046NDlCQy1FMzdBLTIz
# M0MxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggEiMA0G
# CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCj91Y1hPPdNOSjk0hlspJpuKFRwvtR
# Hgi+pYSv80hGm2wM3I/DgksSEbERXP8isz7C3rfarJNFkfSK/xIWb9ItT8ggdgUh
# N0uf1P1Xfqn0kSGmuYxpv+khuJgMILdbtMW/T8NsdIaNEPxo/o0MhWRb8CMt2iQL
# DFC0jI9nAg2XN7QfHa+LzdWHjB5w0+7fIsn+VKxX9L7NVRL7m6Ap4ctWAi5Ny3Iq
# v0yMFJqEKiXfEc6AgeoVYGJXog4aCXSlGK3pmohWLM2v0mldL/GIGpYROFEOl73d
# bBFS6DKllRekJ0mpfjgahB3o5efNn2ycL0RlE12JWoA9PFo3fv1fxqstAgMBAAGj
# ggEbMIIBFzAdBgNVHQ4EFgQUJnfNOCtFfr3TM2Uo98/jaPIOZU0wHwYDVR0jBBgw
# FoAU1WM6XIoxkPNDe3xGG8UzaFqFbVUwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDov
# L2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljVGltU3RhUENB
# XzIwMTAtMDctMDEuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNUaW1TdGFQQ0FfMjAx
# MC0wNy0wMS5jcnQwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDCDAN
# BgkqhkiG9w0BAQsFAAOCAQEAkT/i0RUbICEc8nu85JtZA9+MmlxixB7BxdNOliFg
# 9QPlz4OYlCdNXfgaTuykWeMjhywsyHL4xCbDcwZap//t/u6hiifFZWjI9haPWk5y
# 5TfxkYH8GORuLM2UmbXaYKBgX3Y8ZEZF/xkWDEAlf2e7Lzr8H78YbGiQjK2aI2/9
# qaY+KbJXHqqDjKMatZXj1wt4yaTRCxy7zcXP4xNFV0MPH8EXhiZxL60nbhHzprNy
# XZCj3aArdIf3dybZBo9fTf0eD3sMNPAlVCHkbksfq32dmgGAAt/2qaYZ+STSqBQu
# OPohWTP+m2fKEHdPZk58l7cEWqUEs1Y5ti9UIeJcxQGoRjCCBnEwggRZoAMCAQIC
# CmEJgSoAAAAAAAIwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRp
# ZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTEwMDcwMTIxMzY1NVoXDTI1MDcwMTIx
# NDY1NVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggEiMA0GCSqGSIb3
# DQEBAQUAA4IBDwAwggEKAoIBAQCpHQ28dxGKOiDs/BOX9fp/aZRrdFQQ1aUKAIKF
# ++18aEssX8XD5WHCdrc+Zitb8BVTJwQxH0EbGpUdzgkTjnxhMFmxMEQP8WCIhFRD
# DNdNuDgIs0Ldk6zWczBXJoKjRQ3Q6vVHgc2/JGAyWGBG8lhHhjKEHnRhZ5FfgVSx
# z5NMksHEpl3RYRNuKMYa+YaAu99h/EbBJx0kZxJyGiGKr0tkiVBisV39dx898Fd1
# rL2KQk1AUdEPnAY+Z3/1ZsADlkR+79BL/W7lmsqxqPJ6Kgox8NpOBpG2iAg16Hgc
# sOmZzTznL0S6p/TcZL2kAcEgCZN4zfy8wMlEXV4WnAEFTyJNAgMBAAGjggHmMIIB
# 4jAQBgkrBgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQU1WM6XIoxkPNDe3xGG8UzaFqF
# bVUwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1Ud
# EwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYD
# VR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwv
# cHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEB
# BE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9j
# ZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwgaAGA1UdIAEB/wSBlTCB
# kjCBjwYJKwYBBAGCNy4DMIGBMD0GCCsGAQUFBwIBFjFodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vUEtJL2RvY3MvQ1BTL2RlZmF1bHQuaHRtMEAGCCsGAQUFBwICMDQe
# MiAdAEwAZQBnAGEAbABfAFAAbwBsAGkAYwB5AF8AUwB0AGEAdABlAG0AZQBuAHQA
# LiAdMA0GCSqGSIb3DQEBCwUAA4ICAQAH5ohRDeLG4Jg/gXEDPZ2joSFvs+umzPUx
# vs8F4qn++ldtGTCzwsVmyWrf9efweL3HqJ4l4/m87WtUVwgrUYJEEvu5U4zM9GAS
# inbMQEBBm9xcF/9c+V4XNZgkVkt070IQyK+/f8Z/8jd9Wj8c8pl5SpFSAK84Dxf1
# L3mBZdmptWvkx872ynoAb0swRCQiPM/tA6WWj1kpvLb9BOFwnzJKJ/1Vry/+tuWO
# M7tiX5rbV0Dp8c6ZZpCM/2pif93FSguRJuI57BlKcWOdeyFtw5yjojz6f32WapB4
# pm3S4Zz5Hfw42JT0xqUKloakvZ4argRCg7i1gJsiOCC1JeVk7Pf0v35jWSUPei45
# V3aicaoGig+JFrphpxHLmtgOR5qAxdDNp9DvfYPw4TtxCd9ddJgiCGHasFAeb73x
# 4QDf5zEHpJM692VHeOj4qEir995yfmFrb3epgcunCaw5u+zGy9iCtHLNHfS4hQEe
# gPsbiSpUObJb2sgNVZl6h3M7COaYLeqN4DMuEin1wC9UJyH3yKxO2ii4sanblrKn
# QqLJzxlBTeCG+SqaoxFmMNO7dDJL32N79ZmKLxvHIa9Zta7cRDyXUHHXodLFVeNp
# 3lfB0d4wwP3M5k37Db9dT+mdHhk4L7zPWAUu7w2gUDXa7wknHNWzfjUeCLraNtvT
# X4/edIhJEqGCAs4wggI3AgEBMIH4oYHQpIHNMIHKMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVTTjo0OUJDLUUzN0EtMjMz
# QzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcG
# BSsOAwIaAxUAOD2sJkEijzzGxlXaBgr5Mm2TLmmggYMwgYCkfjB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQUFAAIFAN/y3WMwIhgPMjAx
# OTAxMjMyMDMyMzVaGA8yMDE5MDEyNDIwMzIzNVowdzA9BgorBgEEAYRZCgQBMS8w
# LTAKAgUA3/LdYwIBADAKAgEAAgIgswIB/zAHAgEAAgIRpTAKAgUA3/Qu4wIBADA2
# BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIB
# AAIDAYagMA0GCSqGSIb3DQEBBQUAA4GBAB7Qhv5VxbdwEM4hB+R/+RJX623zZab/
# RcGJ30LcWqY4ixUBIbzYa2hUQYglFyCyO1JTIkCl8EIbqoTEgKSLs6qASJ/uab3X
# noMj/GOT9GDIzE0hwO/TpxJ1O3hjGwr8uLLyKN5n6+Ame3havIr5HLrOuh1ZzS87
# dDO8xfzKcEMYMYIDDTCCAwkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTACEzMAAADu+MX1NjuBHIwAAAAAAO4wDQYJYIZIAWUDBAIBBQCgggFKMBoG
# CSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQggXsBN9ZQ
# j1NgvWceOPwdf15IK3EntkrsmkGuLEOJx6kwgfoGCyqGSIb3DQEJEAIvMYHqMIHn
# MIHkMIG9BCA/rsYitz77+LSxd5M1PpJRCp8LIQHymSsSDNEjLxAuwzCBmDCBgKR+
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAA7vjF9TY7gRyMAAAA
# AADuMCIEIPz3ROS7eU5S8r5ncDLJjGPD+R/RRCp47LfUzMgJf8/sMA0GCSqGSIb3
# DQEBCwUABIIBAHbP6q3hsXxi57+ilFaYRiaUJQXltWNcoItq+KtbV1oJE4Jz0Tkv
# ADdazSLV2Mx/dsk/+XvUYsYOQw+Vd1KUHVUWFZU3Feha2UMqmstNzX3fAriHgOTs
# sj8l9JHGo7o+9WnFoxH9yW0vzk65FfXA+ST+rtUv0eXnxo9A3exZzBsVcFGDxsjI
# GKxwGdjhUsoM/nq+CGHexwMGLWvsSGmPWynLGs+b4oiOHD4+BIKAehqkaYJ7rEGg
# a4TOOwXhGRbL0vSWb0p1qRb6Xy8puRczdtJWiqiHEqY/5QhZ52ALQLKURg7Yltkr
# qresKrXIt87IvYOqBnN7yz8FTMS9zr4AvAc=
# SIG # End signature block
