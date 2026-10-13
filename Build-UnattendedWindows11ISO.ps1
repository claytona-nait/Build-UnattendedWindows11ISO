<#
.SYNOPSIS
Creates a bootable Windows ISO from an unpacked installation source, ensuring required files exist and downloading oscdimg.exe if necessary.

.DESCRIPTION
This script automates the creation of a bootable Windows ISO image from an unpacked Windows installation folder. 
It validates that the source folder contains the required files (`install.wim` and `boot.wim`), downloads `oscdimg.exe` 
from Microsoft if it is not available locally, and then uses `oscdimg.exe` to generate the ISO with proper boot configuration.

.PARAMETER UnpackedFolderPath
Specifies the path to the unpacked Windows installation files. 
The folder must contain `sources\install.wim` and `sources\boot.wim`. 
Default: .\Windows11

.PARAMETER OutputISOPath
Specifies the path and filename for the generated ISO image. 
Default: .\Windows11-Unattended.iso

.PARAMETER localOSCDPath
Specifies the local path to `oscdimg.exe`. If the file does not exist, it will be downloaded automatically. 
Default: .\oscdimg.exe

.EXAMPLE
PS> .\Create-WindowsISO.ps1 -UnpackedFolderPath "C:\Win11Files" -OutputISOPath "C:\Win11-Unattended.iso"
Creates a bootable Windows 11 ISO from the unpacked files located in `C:\Win11Files` and saves it as `C:\Win11-Unattended.iso`.

.EXAMPLE
PS> .\Create-WindowsISO.ps1
Uses default paths to create a bootable Windows 11 ISO from the `.\Windows11` folder and saves it as `.\Windows11-Unattended.iso`.

.NOTES
Author: Clayton Amelia
Version: 1.2.27
Requires: PowerShell 5.1 or later, Internet access (if oscdimg.exe needs to be downloaded)
#>
param (
    [Parameter(Position=0)]
    [ValidateScript({
        if (Test-Path $_) {
            if (Test-Path $(Join-Path -Path $Path -ChildPath "sources\install.wim") -and Test-Path $(Join-Path -Path $Path -ChildPath "sources\boot.wim")) {
                return $true
            } else {
                Throw "`r`nUnable to locate 'sources\install.wim' and 'sources\boot.wim' in $_"
            }
        } else {
            Throw "`r`nUnpacked ISO path does not exist $_ does not exist"
        }
    })]
    [string]
    $UnpackedFolderPath = ".\Windows11",

    [Parameter(Position=1)]
    [string]
    $OutputISOPath = ".\Windows11-Unattended.iso",

     [Parameter(Position=2,Mandatory=$false)]
    $localOSCDPath = ".\oscdimg.exe"

)

if (!(Test-Path $localOSCDPath)) {
    $OSCDurl = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"
    Write-Host "Downloading oscdimg.exe from $OSCDurl"
    Invoke-WebRequest -Uri $OSCDurl -OutFile $localOSCDPath
    if (Test-Path $localOSCDPath) {
        Write-Host "oscdimg.exe downloaded successfully"
    } else {
        Write-Error "Failed to download oscdimg.exe"
        pause
        exit 1
    }
}

& "$localOSCDPath" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$UnpackedFolderPath\boot\etfsboot.com#pEF,e,b$UnpackedFolderPath\efi\microsoft\boot\efisys.bin" "$UnpackedFolderPath" "$OutputISOPath"

# SIG # Begin signature block
# MIIQ4QYJKoZIhvcNAQcCoIIQ0jCCEM4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDy8zx+HhQTJ7iZ
# YJNnO2Te2480+jEqvOYTvWTx3fCms6CCDSYwggWgMIIEiKADAgECAhMSAAAGp51a
# CZ27OHNaAAIAAAanMA0GCSqGSIb3DQEBCwUAMEcxEjAQBgoJkiaJk/IsZAEZFgJj
# YTEUMBIGCgmSJomT8ixkARkWBG5haXQxGzAZBgNVBAMTEk5BSVQgRW50ZXJwcmlz
# ZSBDQTAeFw0yNDAxMTgxODM0MzZaFw0yOTAxMTYxODM0MzZaMEgxEjAQBgoJkiaJ
# k/IsZAEZFgJjYTEUMBIGCgmSJomT8ixkARkWBG5haXQxHDAaBgNVBAMTE05BSVQg
# U3Vib3JkaW5hdGUgQ0EwgZ8wDQYJKoZIhvcNAQEBBQADgY0AMIGJAoGBAL6RZrKg
# S7XlzUf9S2TcUCasXnT2gIt5FnBJfmST+myK4a8xWWiW6DXQh/tCZemF1x1tCrnf
# LmzaCURxO7i1pWI+lcWYS9Kzui/RNWzBihWGclHVk77sOqrdQ9RIbvOPx4zKApnk
# v5htffMCuWF1rNKBWYOP1STWrc2Hten2rpxdAgMBAAGjggMGMIIDAjASBgkrBgEE
# AYI3FQEEBQIDAQAGMCMGCSsGAQQBgjcVAgQWBBSXQV3zxUGhbnDIA3xNDttApY4y
# MzAdBgNVHQ4EFgQUPTKsnR+E+2UrH3Ye3ARoBmhMvmUwGQYJKwYBBAGCNxQCBAwe
# CgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0j
# BBgwFoAUAKTNvVf662LN1qmc8vWPdjD3MvYwggEfBgNVHR8EggEWMIIBEjCCAQ6g
# ggEKoIIBBoaBv2xkYXA6Ly8vQ049TkFJVCUyMEVudGVycHJpc2UlMjBDQSgyKSxD
# Tj1NQUlOLUNFUlQxLENOPUNEUCxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxD
# Tj1TZXJ2aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPW5haXQsREM9Y2E/Y2VydGlm
# aWNhdGVSZXZvY2F0aW9uTGlzdD9iYXNlP29iamVjdENsYXNzPWNSTERpc3RyaWJ1
# dGlvblBvaW50hkJodHRwOi8vTUFJTi1DRVJUMS5uYWl0LmNhL0NlcnRFbnJvbGwv
# TkFJVCUyMEVudGVycHJpc2UlMjBDQSgyKS5jcmwwggEpBggrBgEFBQcBAQSCARsw
# ggEXMIGxBggrBgEFBQcwAoaBpGxkYXA6Ly8vQ049TkFJVCUyMEVudGVycHJpc2Ul
# MjBDQSxDTj1BSUEsQ049UHVibGljJTIwS2V5JTIwU2VydmljZXMsQ049U2Vydmlj
# ZXMsQ049Q29uZmlndXJhdGlvbixEQz1uYWl0LERDPWNhP2NBQ2VydGlmaWNhdGU/
# YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9yaXR5MGEGCCsGAQUF
# BzAChlVodHRwOi8vTUFJTi1DRVJUMS5uYWl0LmNhL0NlcnRFbnJvbGwvTUFJTi1D
# RVJUMS5uYWl0LmNhX05BSVQlMjBFbnRlcnByaXNlJTIwQ0EoMikuY3J0MA0GCSqG
# SIb3DQEBCwUAA4IBAQCSxSaVXKpDRZi826Ne+ZR018ct3xX9VqspAIqyo0Ko7mhQ
# rAz5zhuXJFtq53L/SOgYbZreUPEd2hpCFBW8YRDNCZzYQP0anEnKbsZJ28rx+610
# nAPAI777SPjuoERBVhNJe3E+thoR4pji9xp0ZbMGAvYrOZ9gj8d6rS0jax3TvK12
# +Ive8qCip8nTM0wfvofAIKayemo5k7vWbTlP0qj2pa2f5rZMS/3MShMddmczr2UY
# a0VZbyLg7mp6PZruhNZjNYCMMd0a94BOA2wIpgkzaNMfqGSDgJyzA+XDKnhlXAiQ
# a3rcqC44QWeRNs2NaUDX4jjHDST+tBfZYSGahv7cMIIHfjCCBuegAwIBAgITGQFR
# xi9g/lYUyATHbQAGAVHGLzANBgkqhkiG9w0BAQsFADBIMRIwEAYKCZImiZPyLGQB
# GRYCY2ExFDASBgoJkiaJk/IsZAEZFgRuYWl0MRwwGgYDVQQDExNOQUlUIFN1Ym9y
# ZGluYXRlIENBMB4XDTI2MDQwNzE0MTc0MloXDTI5MDExNjE4MzQzNlowgYkxEjAQ
# BgoJkiaJk/IsZAEZFgJjYTEUMBIGCgmSJomT8ixkARkWBG5haXQxETAPBgNVBAsT
# CEFjY291bnRzMQ4wDAYDVQQLEwVTdGFmZjEUMBIGA1UECxMLQWN0aXZlU3RhZmYx
# ETAPBgNVBAsTCEVtcGxveWVlMREwDwYDVQQDEwhDTEFZVE9OQTCCAiIwDQYJKoZI
# hvcNAQEBBQADggIPADCCAgoCggIBALpkhU2uhnF085EqOoMPkcFl0/NGst/JYQ2O
# iJXYov4dETvDNKYzJx3yYUhC2anToLqcUAemdXrwvlAmo3oXsFG8e71hpY8S7CQF
# mRZYthtsJF8hOZOtO0rMJ49He7HKxTAI/ZkfJuKfIa/sRU6LhBxTOM67xPdzXW6F
# sKCURKmn9Oh2CUKEj8VKgQGVpHuUOpBMXXfdg0Qnx0A3BOHwZlTk4Aa8BYSEoVf2
# 9x0TAnjt+Hoz3KJYyRJKBh8G6+Wp35Y01tzQwRYV9OuwqEj7orcCROt8TROS4GTI
# sfFV5AfiilpEXMabfzQbhLujNAhx6838klyb1iv7n3smSiROwmpSJ5SlmoJh6659
# izQOUkuOzEANGQ/bUy8DJxxhJ1SNcJz7tY/u6ERKw2OPitliLOVUqn67iAWKeh49
# RtUZGg2ebK/aTKrOeAfFNyYZlQcM9x7Zk66ukNxEDd/vSjE4m1xLa4ZE7W1iyTfV
# SvKueCMH3qp/B5jRLHG8L1721g2WREc+sUQI1fBSuxcY8wiCgu0IoN5mZ5ZBw1sk
# XYlCYQj6Pl6BA/8mljp0KrB82dkzN0XKfzQjGfxY+bpwAA9/T1tCYwmp0VWWJLV6
# 0DwxeI+aDMiumi26a9tL/9vt4na3ET9sMb1amCi55tJn1yU0dcy0Hk/kVWP/B/0y
# PRRcmkORAgMBAAGjggOeMIIDmjATBgNVHSUEDDAKBggrBgEFBQcDAzAbBgkrBgEE
# AYI3FQoEDjAMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBRCnkU7aIkTmbSwXcPVqSvA
# tGW2XjAfBgNVHSMEGDAWgBQ9MqydH4T7ZSsfdh7cBGgGaEy+ZTCCASUGA1UdHwSC
# ARwwggEYMIIBFKCCARCgggEMhoHCbGRhcDovLy9DTj1OQUlUJTIwU3Vib3JkaW5h
# dGUlMjBDQSgxKSxDTj1tYWluLWluZnNydjEsQ049Q0RQLENOPVB1YmxpYyUyMEtl
# eSUyMFNlcnZpY2VzLENOPVNlcnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9bmFp
# dCxEQz1jYT9jZXJ0aWZpY2F0ZVJldm9jYXRpb25MaXN0P2Jhc2U/b2JqZWN0Q2xh
# c3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnSGRWh0dHA6Ly9tYWluLWluZnNydjEubmFp
# dC5jYS9DZXJ0RW5yb2xsL05BSVQlMjBTdWJvcmRpbmF0ZSUyMENBKDEpLmNybDCC
# AS8GCCsGAQUFBwEBBIIBITCCAR0wgbIGCCsGAQUFBzAChoGlbGRhcDovLy9DTj1O
# QUlUJTIwU3Vib3JkaW5hdGUlMjBDQSxDTj1BSUEsQ049UHVibGljJTIwS2V5JTIw
# U2VydmljZXMsQ049U2VydmljZXMsQ049Q29uZmlndXJhdGlvbixEQz1uYWl0LERD
# PWNhP2NBQ2VydGlmaWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9u
# QXV0aG9yaXR5MGYGCCsGAQUFBzAChlpodHRwOi8vbWFpbi1pbmZzcnYxLm5haXQu
# Y2EvQ2VydEVucm9sbC9tYWluLWluZnNydjEubmFpdC5jYV9OQUlUJTIwU3Vib3Jk
# aW5hdGUlMjBDQSg2KS5jcnQwCwYDVR0PBAQDAgeAMD4GCSsGAQQBgjcVBwQxMC8G
# JysGAQQBgjcVCIOVlzCDz5YSgemTB4eAgjKDsOsIgVOE+rcMh7n0SwIBZAIBAzAr
# BgNVHREEJDAioCAGCisGAQQBgjcUAgOgEgwQQ0xBWVRPTkFAbmFpdC5jYTBQBgkr
# BgEEAYI3GQIEQzBBoD8GCisGAQQBgjcZAgGgMQQvUy0xLTUtMjEtMTQ4MjQ3NjUw
# MS0xNTIwNDkxNzEtNjgyMDAzMzMwLTEzMDYzNTIwDQYJKoZIhvcNAQELBQADgYEA
# RKUI0fn+iOkHd0an9B/qw4T67uoM2x411ofsp7waMArJyL2kv/ji2qDIwEJbGNw9
# yTUZlya5lryqUtS7P9s+JbEzcUteR7i56m8N5HcZ4rlBP0VARPFs+682SHD0+Hs6
# M93+5MBkPVakg9AKGrzGPk/smHjLb5UkkuuDD9TPyS8xggMRMIIDDQIBATBfMEgx
# EjAQBgoJkiaJk/IsZAEZFgJjYTEUMBIGCgmSJomT8ixkARkWBG5haXQxHDAaBgNV
# BAMTE05BSVQgU3Vib3JkaW5hdGUgQ0ECExkBUcYvYP5WFMgEx20ABgFRxi8wDQYJ
# YIZIAWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG
# 9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIB
# FTAvBgkqhkiG9w0BCQQxIgQg8hEfPGJSNir2+kEgjFwJsc2TTqHhiIflhZH6Jk2i
# +4QwDQYJKoZIhvcNAQEBBQAEggIAn23NuWFLcs225c+63tLHu+j99WEWrNlz+7M1
# +dP6C0wiOehLEpH8nYLsYpDLKf6yLkUyAK1cQcFhPeIBgkXHVjV6zgK1zAiog0d7
# yLnPEq1eMVsXsybtwJybhzkmt0dptU8q+hIGl8nxtpmLiBuJpv2xKbw0AeO/BoOM
# lOuMEkbXPVG5zty7eph3msQsd1lZEKz6SQzeeIRHsyJP3bIYzrQYMOtNYTfb2Zss
# tKNxIguKUeItVW7Ly9A5kMfUq46XaDnO7DIDUSr1PKM0plm1R2B1TT6y5RWT8A7M
# 6FSwJLsPII1zbOKbjAH9XIBcFeIXLdRcySYsy3emID4SfjtCGiOMLngjM7CNGXP5
# hdCuPKC1ekwKeqEb/AWs4XT0vXyllbfWwXAeyENbq49Ob2vjaSWrp+qGGpXYl3Sv
# /9sxJvAWtdEUqKsUXgUaAdbDv6H+KaxOip0ag5USB4bYrsM6hAwFA5rvYaODKAmz
# at8A4BUn5P+ufBng55X3qTjmK7KbP96Q0XgVrFufmCqmHs1Jz5dqaKL7hn7Ur9Jl
# fI0Uw+7A9P5nDKeWLyBnyd0DVbL3Et7RFSE45uPkz50KQcMHo5G7/k/PXfbQzSYY
# ZZKec9JeUWfdSV57qhiTWXeNhtqW7KZEFi/fzvBQK9SkKS73C6YOcU6pTFpT2z2L
# rmEE4N4=
# SIG # End signature block
