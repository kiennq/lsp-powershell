<#
.SYNOPSIS
Download the language server PowerShellEditorServices module.

.DESCRIPTION
Download the language server PowerShellEditorServices module.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Destination,

    [string]
    $Version = "v1.11.0"
)

$file = "PowerShellEditorServices.zip"
$url = "https://github.com/PowerShell/PowerShellEditorServices/releases/download/$Version/$file"

Invoke-WebRequest -Uri $url -OutFile "$env:TEMP/$file"
Expand-Archive -Path "$env:TEMP/$file" -DestinationPath $Destination -Force
