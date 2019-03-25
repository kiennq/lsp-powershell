#
# Copyright (c) Microsoft. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.
#

function Import-EditorCommand {
    <#
    .EXTERNALHELP ..\PowerShellEditorServices.Commands-help.xml
    #>
    [OutputType([Microsoft.PowerShell.EditorServices.Extensions.EditorCommand])]
    [CmdletBinding(DefaultParameterSetName='ByCommand')]
    param(
        [Parameter(Position=0,
                   Mandatory,
                   ValueFromPipeline,
                   ValueFromPipelineByPropertyName,
                   ParameterSetName='ByCommand')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Command,

        [Parameter(Position=0, Mandatory, ParameterSetName='ByModule')]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Module,

        [switch]
        $Force,

        [switch]
        $PassThru
    )
    begin {
        function GetCommandsFromModule {
            param(
                [Parameter(ValueFromPipeline)]
                [string]
                $ModuleToSearch
            )
            process {
                if (-not $ModuleToSearch) { return }

                $caller = (Get-PSCallStack)[2]

                if ($caller.InvocationInfo.MyCommand.ScriptBlock.Module.Name -eq $ModuleToSearch) {
                    $moduleInfo = $caller.InvocationInfo.MyCommand.ScriptBlock.Module

                    return $moduleInfo.Invoke(
                        {
                            $ExecutionContext.SessionState.InvokeProvider.Item.Get('function:\*') |
                                Where-Object ModuleName -eq $args[0]
                        },
                        $ModuleToSearch)
                }

                $moduleInfo = Get-Module $ModuleToSearch -ErrorAction SilentlyContinue
                return $moduleInfo.ExportedFunctions.Values
            }
        }
        $flags = [Reflection.BindingFlags]'Instance, NonPublic'
        $extensionService = $psEditor.GetType().
                                      GetField('extensionService', $flags).
                                      GetValue($psEditor)

        $editorCommands = $extensionService.GetType().
                                            GetField('editorCommands', $flags).
                                            GetValue($extensionService)
    }
    process {
        switch ($PSCmdlet.ParameterSetName) {
            ByModule {
                $commands = $Module | GetCommandsFromModule
            }
            ByCommand {
                $commands = $Command | Get-Command -ErrorAction SilentlyContinue
            }
        }
        $attributeType = [Microsoft.PowerShell.EditorServices.Extensions.EditorCommandAttribute]
        foreach ($aCommand in $commands) {
            # Get the attribute from our command to get name info.
            $details = $aCommand.ScriptBlock.Attributes | Where-Object TypeId -eq $attributeType

            if ($details) {
                # TODO: Add module name to this?
                # Name: Expand-Expression becomes ExpandExpression
                if (-not $details.Name) { $details.Name = $aCommand.Name -replace '-' }

                # DisplayName: Expand-Expression becomes Expand Expression
                if (-not $details.DisplayName) { $details.DisplayName = $aCommand.Name -replace '-', ' ' }

                # If the editor command is already loaded skip unless force is specified.
                if ($editorCommands.ContainsKey($details.Name)) {
                    if ($Force.IsPresent) {
                        $null = $psEditor.UnregisterCommand($details.Name)
                    } else {
                        $PSCmdlet.WriteVerbose($Strings.EditorCommandExists -f $details.Name)
                        continue
                    }
                }
                # Check for a context parameter.
                $contextParameter = $aCommand.Parameters.Values |
                    Where-Object ParameterType -eq ([Microsoft.PowerShell.EditorServices.Extensions.EditorContext])

                # If one is found then add a named argument. Otherwise call the command directly.
                if ($contextParameter) {
                    $sbText = '{0} -{1} $args[0]' -f $aCommand.Name, $contextParameter.Name
                    $scriptBlock = [scriptblock]::Create($sbText)
                } else {
                    $scriptBlock = [scriptblock]::Create($aCommand.Name)
                }

                $editorCommand = New-Object Microsoft.PowerShell.EditorServices.Extensions.EditorCommand @(
                    <# commandName:    #> $details.Name,
                    <# displayName:    #> $details.DisplayName,
                    <# suppressOutput: #> $details.SuppressOutput,
                    <# scriptBlock:    #> $scriptBlock)

                $PSCmdlet.WriteVerbose($Strings.EditorCommandImporting -f $details.Name)
                $null = $psEditor.RegisterCommand($editorCommand)

                if ($PassThru.IsPresent -and $editorCommand) {
                    $editorCommand # yield
                }
            }
        }
    }
}

if ($PSVersionTable.PSVersion.Major -ge 5) {
    Register-ArgumentCompleter -CommandName Import-EditorCommand -ParameterName Module -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        (Get-Module).Name -like ($wordToComplete + '*') | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($PSItem, $PSItem, 'ParameterValue', $PSItem)
        }
    }
    Register-ArgumentCompleter -CommandName Import-EditorCommand -ParameterName Command -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        (Get-Command -ListImported).Name -like ($wordToComplete + '*') | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($PSItem, $PSItem, 'ParameterValue', $PSItem)
        }
    }
}

# SIG # Begin signature block
# MIIjhAYJKoZIhvcNAQcCoIIjdTCCI3ECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAYVJXgB2fHOAVC
# SMK6hsON+9k71hvK3eeXbTGokKn9OKCCDYEwggX/MIID56ADAgECAhMzAAABA14l
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
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIVWTCCFVUCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAQNeJRyZH6MeuAAAAAABAzAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgNh9EgglW
# onzyUpkYqpWgtKl7QtKKNhqwMxCyigYobdcwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQB+35wY/Re7brCHo+XwXSkdORBOS1pE9882s3xQJFaF
# /qQnjZ25zR93frDyuxgx3dXIXmU2pKIMJVQrudvF0sOIoJdWjWpTyVHDYIw+L8cl
# 3/vPMCtemU6EYd0WMRQ+vHnP3kLfKHJWY2vS+JK6PYpiKpVnzhJQNMKa2llbErNL
# 5uOvkwAqCT8CbFCCQwhuyk/PI6yzAILF3kVi2kWbGSuoKDDJNJ1J24LMCvmlR4sP
# BlpgdvxoZJtzDaMU6gRn9Rws9QRNE54DDqymzasQbnifw8KDcGTakBOI/3Fk6sx1
# hrOkwPWzSpjBeOlv5MQGZ/aG0qL7yOYVniGDFQW+LLnSoYIS4zCCEt8GCisGAQQB
# gjcDAwExghLPMIISywYJKoZIhvcNAQcCoIISvDCCErgCAQMxDzANBglghkgBZQME
# AgEFADCCAU8GCyqGSIb3DQEJEAEEoIIBPgSCATowggE2AgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIBjpcBjStjO4h4lQLRefKMIaQIJiRwrAy0CnLSWt
# 5nFtAgZcP1ZqG84YETIwMTkwMTIzMTY1NzQ0LjJaMASAAgH0oIHQpIHNMIHKMQsw
# CQYDVQQGEwJVUzELMAkGA1UECBMCV0ExEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IEly
# ZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMSYwJAYDVQQLEx1UaGFsZXMgVFNTIEVT
# TjowODQyLTRCRTYtQzI5QTElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# c2VydmljZaCCDjwwggTxMIID2aADAgECAhMzAAAA2BrkzD96EfrhAAAAAADYMA0G
# CSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTE4
# MDgyMzIwMjY1MVoXDTE5MTEyMzIwMjY1MVowgcoxCzAJBgNVBAYTAlVTMQswCQYD
# VQQIEwJXQTEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25z
# IExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjA4NDItNEJFNi1DMjlB
# MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBzZXJ2aWNlMIIBIjANBgkq
# hkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAlB4w5Ida9bBouPMwkk1SUi11Q+YxVF4k
# gK7imoaAQHlxBYN17XS/eyXsE9rxJi3hhD0nXOZ6K5evnumaIVY//PMCkfsNJfwF
# xG24NoDPIO12e1KBgQWI930yWzS5PQaACOENPgsgi7CRFDcb1wSZF9CoXl69yKba
# Q2aGoAZZP091GhR5kznxumHHuc0SeSx0MrxNDvUZyQyTDeQ6Eef8zGV+wNhRdAx1
# 3+AvwFkED2B0DldX5jbn8QZUsA+BhWzrtUfHS/kszVM3u+x6U6oPuni01ErBzXla
# +GCs6zfNb5gsemiLuYrlsHFFscMe04G6hq9nXYP1ePVvIrvVLDL1QwIDAQABo4IB
# GzCCARcwHQYDVR0OBBYEFJ+2Vkse7hTV34p2epqDGueQ42bkMB8GA1UdIwQYMBaA
# FNVjOlyKMZDzQ3t8RhvFM2hahW1VMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9j
# cmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1RpbVN0YVBDQV8y
# MDEwLTA3LTAxLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljVGltU3RhUENBXzIwMTAt
# MDctMDEuY3J0MAwGA1UdEwEB/wQCMAAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJ
# KoZIhvcNAQELBQADggEBAA5ScHbeyD8gtTS3uwGc3vDaOzJ3fOA+UjB38YkaS3jm
# F8/m4GfiP2/AZ+mwoNl6Eu1Cm39GnqLlKrv03JA7Dguvn5KNLltS6TkTlKQr3PVk
# xr9FV4/6CQLl2USU0d6nmRzoImGdKgsiUoTsiCJiSm+N2IM+LdJPyQNKuRPs9lvw
# 9pyg1Vfs05yvEp0TkOeVinqCavaQXCY3dZ3+x72HdTJchYRdzsHQjxazPxbbHCzu
# hilQYr16XtNyvSNirKICYdu7Ail3dO0zdYalDlTOeLFSW2aHz5yRMIoPjToWEkYo
# 4UuE/30WtVXC0Nq8ITTMkHPVPvkPlt/iNivGg5tJTrEwggZxMIIEWaADAgECAgph
# CYEqAAAAAAACMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZp
# Y2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0xMDA3MDEyMTM2NTVaFw0yNTA3MDEyMTQ2
# NTVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEAqR0NvHcRijog7PwTl/X6f2mUa3RUENWlCgCChfvt
# fGhLLF/Fw+Vhwna3PmYrW/AVUycEMR9BGxqVHc4JE458YTBZsTBED/FgiIRUQwzX
# Tbg4CLNC3ZOs1nMwVyaCo0UN0Or1R4HNvyRgMlhgRvJYR4YyhB50YWeRX4FUsc+T
# TJLBxKZd0WETbijGGvmGgLvfYfxGwScdJGcSchohiq9LZIlQYrFd/XcfPfBXday9
# ikJNQFHRD5wGPmd/9WbAA5ZEfu/QS/1u5ZrKsajyeioKMfDaTgaRtogINeh4HLDp
# mc085y9Euqf03GS9pAHBIAmTeM38vMDJRF1eFpwBBU8iTQIDAQABo4IB5jCCAeIw
# EAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFNVjOlyKMZDzQ3t8RhvFM2hahW1V
# MBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMB
# Af8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1Ud
# HwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3By
# b2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQRO
# MEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2Vy
# dHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MIGgBgNVHSABAf8EgZUwgZIw
# gY8GCSsGAQQBgjcuAzCBgTA9BggrBgEFBQcCARYxaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL1BLSS9kb2NzL0NQUy9kZWZhdWx0Lmh0bTBABggrBgEFBQcCAjA0HjIg
# HQBMAGUAZwBhAGwAXwBQAG8AbABpAGMAeQBfAFMAdABhAHQAZQBtAGUAbgB0AC4g
# HTANBgkqhkiG9w0BAQsFAAOCAgEAB+aIUQ3ixuCYP4FxAz2do6Ehb7Prpsz1Mb7P
# BeKp/vpXbRkws8LFZslq3/Xn8Hi9x6ieJeP5vO1rVFcIK1GCRBL7uVOMzPRgEop2
# zEBAQZvcXBf/XPleFzWYJFZLdO9CEMivv3/Gf/I3fVo/HPKZeUqRUgCvOA8X9S95
# gWXZqbVr5MfO9sp6AG9LMEQkIjzP7QOllo9ZKby2/QThcJ8ySif9Va8v/rbljjO7
# Yl+a21dA6fHOmWaQjP9qYn/dxUoLkSbiOewZSnFjnXshbcOco6I8+n99lmqQeKZt
# 0uGc+R38ONiU9MalCpaGpL2eGq4EQoO4tYCbIjggtSXlZOz39L9+Y1klD3ouOVd2
# onGqBooPiRa6YacRy5rYDkeagMXQzafQ732D8OE7cQnfXXSYIghh2rBQHm+98eEA
# 3+cxB6STOvdlR3jo+KhIq/fecn5ha293qYHLpwmsObvsxsvYgrRyzR30uIUBHoD7
# G4kqVDmyW9rIDVWZeodzOwjmmC3qjeAzLhIp9cAvVCch98isTtoouLGp25ayp0Ki
# yc8ZQU3ghvkqmqMRZjDTu3QyS99je/WZii8bxyGvWbWu3EQ8l1Bx16HSxVXjad5X
# wdHeMMD9zOZN+w2/XU/pnR4ZOC+8z1gFLu8NoFA12u8JJxzVs341Hgi62jbb01+P
# 3nSISRKhggLOMIICNwIBATCB+KGB0KSBzTCByjELMAkGA1UEBhMCVVMxCzAJBgNV
# BAgTAldBMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMg
# TGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046MDg0Mi00QkU2LUMyOUEx
# JTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIHNlcnZpY2WiIwoBATAHBgUr
# DgMCGgMVAGUxwd0RXh2Q7I0ookkVCFlgKyKBoIGDMIGApH4wfDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDf8w9KMCIYDzIwMTkw
# MTI0MDAwNTMwWhgPMjAxOTAxMjUwMDA1MzBaMHcwPQYKKwYBBAGEWQoEATEvMC0w
# CgIFAN/zD0oCAQAwCgIBAAICJccCAf8wBwIBAAICEWIwCgIFAN/0YMoCAQAwNgYK
# KwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQAC
# AwGGoDANBgkqhkiG9w0BAQUFAAOBgQAaxE4GcOOQ4NysIys1chtdR5dcNlHYZp9W
# iTNSgRHbcne4gz+wVoUD64nXf845wtkx3M2aYHL3nOnZsATNnsBfkAUcAET2O0X+
# zfNEEDdYFvfB3220QNgvyqLZI3EWsTbv8L0Y8sVPNowJ7UNYtlaXmXC/zcJDbMoO
# r8CLTcFxnTGCAw0wggMJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwAhMzAAAA2BrkzD96EfrhAAAAAADYMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkq
# hkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIB1+ncUn9w6F
# HG56dQWleg4On+peLw74Pamy2e3IR6RaMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB
# 5DCBvQQgczudx3hc6PN2Kf/vhJWqPSlA0W8KBP8ga8wTn0Eu2C0wgZgwgYCkfjB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAANga5Mw/ehH64QAAAAAA
# 2DAiBCDmZQxAiHfi3WKgteAAL9U0HlrXkFO49w/wlhiImNg4zTANBgkqhkiG9w0B
# AQsFAASCAQB7J6zQjMBMMWKTh8unUxD6kFwXfEAxKhdgfaksPOpFuCo3rZJ7TiNT
# wuIYgQo3QogpIq6ZSIEDWfYSKwncU2JNyGBg2GZHvmbILLnX5PY3C54ETSj/eWk/
# u4Z+zwpjhxbjMAZyjC4rGzGslsNUmf/2vQcc13si15atQnWwuNSzgHPlCl7XnbOH
# 1YLkgeRkqL5dJps/9sX+jrmGKzQHtISs/K83C+lnnQRA6E6OHPI64YI8XuWXmd2N
# Me+cyL4JMAggM2EjzHYOndgPODIrsvCqYBvxqfEKU1u1G8JYQtQN7HiIBhoC1NWW
# CKRtng/e0gtjuZaitCXD/30/Em0lV/mg
# SIG # End signature block
