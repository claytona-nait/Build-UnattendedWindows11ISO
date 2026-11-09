<#
.SYNOPSIS
Creates a bootable Windows ISO from an unpacked installation source, ensuring required files exist and downloading oscdimg.exe if necessary.

.DESCRIPTION
This script automates the creation of a bootable Windows ISO image from an unpacked Windows installation folder.
It validates that the source folder contains the installer images (`sources\install.wim` and `sources\boot.wim`) and the
boot files oscdimg needs (`boot\etfsboot.com` for BIOS and `efi\microsoft\boot\efisys.bin` for UEFI), downloads
`oscdimg.exe` from Microsoft if it is not available locally, and then uses `oscdimg.exe` to generate the ISO.

Because the output is meant to be an unattended installer, the script prefers `efisys_noprompt.bin` for the UEFI boot
image when the source folder has one. That removes the "Press any key to boot from CD or DVD" prompt, so the install
starts without anyone at the keyboard. If only `efisys.bin` is present it is used instead and a warning is written.
Pass `-KeepPrompt` to use `efisys.bin` deliberately, for an ISO that should still wait at the prompt.

.PARAMETER UnpackedFolderPath
Specifies the path to the unpacked Windows installation files.
The folder must contain `sources\install.wim`, `sources\boot.wim`, `boot\etfsboot.com` and either
`efi\microsoft\boot\efisys_noprompt.bin` or `efi\microsoft\boot\efisys.bin`.
Default: .\Windows11

.PARAMETER OutputISOPath
Specifies the path and filename for the generated ISO image. When omitted the name says what was built:
`.\Windows11-Unattended.iso` if the source folder has an `autounattend.xml`, otherwise `.\Windows11.iso`.
Default: .\Windows11-Unattended.iso or .\Windows11.iso, see above

.PARAMETER localOSCDPath
Specifies the local path to `oscdimg.exe`. If the file does not exist, it will be downloaded automatically.
Default: .\oscdimg.exe

.PARAMETER KeepPrompt
Uses `efi\microsoft\boot\efisys.bin` for the UEFI boot image even when `efisys_noprompt.bin` is present, so the
ISO keeps the "Press any key to boot from CD or DVD" prompt. Useful when the media should not reinstall on its own
if it is left in a drive. Without this switch the no-prompt image is preferred.

.PARAMETER Force
Overwrites an existing ISO at `OutputISOPath`. Without this switch the script stops rather than replace a file that
is already there. A locked ISO, such as one still attached to a running VM, cannot be overwritten either way.

.PARAMETER SkipUnattendCheck
Skips the answer file check. By default the script warns when there is no `autounattend.xml` in the root of the
source folder, since the ISO would then be ordinary install media, and stops if the file is there but is not
well-formed XML with the Windows Setup `unattend` root element. Pass this switch when plain media is the goal.

.PARAMETER VolumeLabel
Sets the ISO volume label, which is what Hyper-V, File Explorer and the Windows Setup logs show for the mounted
media. Letters, digits, underscore and hyphen only, up to 32 characters. Without a label oscdimg writes `DVD_ROM`,
which makes every ISO look alike. When omitted the label follows the same rule as the output name: `Win11_Unattended`
if the source folder has an `autounattend.xml`, otherwise `Win11`.
Default: Win11_Unattended or Win11, see above

.PARAMETER SkipHash
Skips the SHA256 hash of the finished ISO. By default the script hashes the ISO, prints the value in the build
summary and writes it beside the ISO as `<name>.iso.sha256.txt`, so the file handed to students can be checked
against the one that was built. Hashing a full Windows ISO takes a little while, so skip it for throwaway builds.

.EXAMPLE
PS> .\Build-UnattendedWindows11ISO.ps1 -UnpackedFolderPath "C:\Win11Files" -OutputISOPath "C:\Win11-Unattended.iso"
Creates a bootable Windows 11 ISO from the unpacked files located in `C:\Win11Files` and saves it as `C:\Win11-Unattended.iso`.

.EXAMPLE
PS> .\Build-UnattendedWindows11ISO.ps1
Uses default paths to create a bootable Windows 11 ISO from the `.\Windows11` folder and saves it as `.\Windows11-Unattended.iso`,
or as `.\Windows11.iso` if the folder has no `autounattend.xml`.

.EXAMPLE
PS> .\Build-UnattendedWindows11ISO.ps1 -KeepPrompt
Builds from the default paths but boots with `efisys.bin`, so the ISO still asks for a key press before starting the installer.

.NOTES
Author: Clayton Amelia
Version: 1.4.0
Requires: PowerShell 5.1 or later, Internet access (if oscdimg.exe needs to be downloaded)
#>
param (
    [Parameter(Position=0)]
    [string]
    $UnpackedFolderPath = ".\Windows11",

    [Parameter(Position=1)]
    [string]
    $OutputISOPath,

    [Parameter(Position=2)]
    [string]
    $localOSCDPath = ".\oscdimg.exe",

    [Parameter()]
    [switch]
    $KeepPrompt,

    [Parameter()]
    [switch]
    $Force,

    [Parameter()]
    [switch]
    $SkipUnattendCheck,

    [Parameter()]
    [string]
    $VolumeLabel,

    [Parameter()]
    [switch]
    $SkipHash
)

$buildTimer = [System.Diagnostics.Stopwatch]::StartNew()

# Validation runs here rather than in a [ValidateScript()] so it also covers the default folder.
# PowerShell skips parameter validation when the caller does not supply a value.
if (!(Test-Path -Path $UnpackedFolderPath -PathType Container)) {
    Write-Error "Unpacked ISO folder does not exist: $UnpackedFolderPath"
    exit 1
}
$UnpackedFolderPath = (Resolve-Path -Path $UnpackedFolderPath).Path

$requiredFiles = @(
    "sources\install.wim",
    "sources\boot.wim",
    "boot\etfsboot.com"
)
$missing = $requiredFiles | Where-Object { !(Test-Path -Path (Join-Path -Path $UnpackedFolderPath -ChildPath $_)) }
if ($missing) {
    Write-Error "Unable to locate the following in $UnpackedFolderPath`r`n  $($missing -join "`r`n  ")`r`nExtract the whole ISO, not just some of its folders."
    exit 1
}

# The script does not write answer files, but it can catch a missing or broken one here, where the fix is
# a file copy, rather than at Windows Setup, where a bad autounattend.xml is silently ignored and the install
# stops at the first interactive screen.
$unattendPath = Join-Path -Path $UnpackedFolderPath -ChildPath "autounattend.xml"
$hasUnattend = Test-Path -Path $unattendPath -PathType Leaf
if (!$SkipUnattendCheck) {
    if (!$hasUnattend) {
        Write-Warning "No autounattend.xml in $UnpackedFolderPath. The ISO will be ordinary install media. Pass -SkipUnattendCheck to silence this."
    } else {
        try {
            $unattendXml = [xml](Get-Content -Path $unattendPath -Raw -ErrorAction Stop)
        } catch {
            Write-Error "autounattend.xml is not well-formed XML, Windows Setup would ignore it: $($_.Exception.Message)"
            exit 1
        }
        $root = $unattendXml.DocumentElement
        if ($root.LocalName -ne "unattend" -or $root.NamespaceURI -ne "urn:schemas-microsoft-com:unattend") {
            Write-Error "autounattend.xml does not have the <unattend xmlns=`"urn:schemas-microsoft-com:unattend`"> root element Windows Setup expects, found <$($root.Name)>"
            exit 1
        }
        Write-Host "Found autounattend.xml, parsed as a Windows Setup answer file"
    }
}

# Prefer the no-prompt UEFI boot image so an unattended install does not stall on "Press any key",
# unless -KeepPrompt asks for the standard image on purpose.
$efiBootDir = Join-Path -Path $UnpackedFolderPath -ChildPath "efi\microsoft\boot"
$efiNoPrompt = Join-Path -Path $efiBootDir -ChildPath "efisys_noprompt.bin"
$efiPrompt   = Join-Path -Path $efiBootDir -ChildPath "efisys.bin"
if ($KeepPrompt) {
    if (!(Test-Path -Path $efiPrompt)) {
        Write-Error "-KeepPrompt was given but efisys.bin was not found in $efiBootDir"
        exit 1
    }
    $efiBoot = $efiPrompt
    Write-Host "Using efisys.bin for UEFI boot because -KeepPrompt was given, the ISO will show 'Press any key to boot from CD or DVD'"
} elseif (Test-Path -Path $efiNoPrompt) {
    $efiBoot = $efiNoPrompt
    Write-Host "Using efisys_noprompt.bin for UEFI boot, the 'Press any key' prompt will be skipped"
} elseif (Test-Path -Path $efiPrompt) {
    $efiBoot = $efiPrompt
    Write-Warning "efisys_noprompt.bin not found, falling back to efisys.bin. The ISO will show 'Press any key to boot from CD or DVD' and will not be fully unattended."
} else {
    Write-Error "Unable to locate efisys_noprompt.bin or efisys.bin in $efiBootDir"
    exit 1
}
$biosBoot = Join-Path -Path $UnpackedFolderPath -ChildPath "boot\etfsboot.com"

# Name the ISO after what it is when the caller did not choose a name, so plain media and
# unattended media built from the same folder do not overwrite each other.
if ([string]::IsNullOrEmpty($OutputISOPath)) {
    $OutputISOPath = if ($hasUnattend) { ".\Windows11-Unattended.iso" } else { ".\Windows11.iso" }
    Write-Host "Output ISO will be $OutputISOPath"
}

# Check the output path before oscdimg does, since its own errors for a missing folder or a locked
# file are terse. The parent folder must exist, the ISO must not land inside the source tree where
# oscdimg would try to pack it into itself, and an existing ISO is only replaced with -Force.
$outputDir = Split-Path -Path $OutputISOPath -Parent
if ([string]::IsNullOrEmpty($outputDir)) { $outputDir = "." }
if (!(Test-Path -Path $outputDir -PathType Container)) {
    Write-Error "Output folder does not exist: $outputDir"
    exit 1
}
$OutputISOPath = Join-Path -Path (Resolve-Path -Path $outputDir).Path -ChildPath (Split-Path -Path $OutputISOPath -Leaf)
if ($OutputISOPath.StartsWith($UnpackedFolderPath + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Error "Output ISO path is inside the source folder, choose a location outside $UnpackedFolderPath"
    exit 1
}
if (Test-Path -Path $OutputISOPath -PathType Leaf) {
    if (!$Force) {
        Write-Error "Output ISO already exists: $OutputISOPath`r`nPass -Force to overwrite it."
        exit 1
    }
    try {
        Remove-Item -Path $OutputISOPath -Force -ErrorAction Stop
        Write-Host "Removed existing $OutputISOPath"
    } catch {
        Write-Error "Unable to remove existing $OutputISOPath, it may still be attached to a VM: $($_.Exception.Message)"
        exit 1
    }
}

# Give the ISO a label that says what it is. oscdimg defaults to DVD_ROM, so every build looks alike once mounted.
# The default follows the output name, so plain media and unattended media are told apart once mounted too.
if ([string]::IsNullOrEmpty($VolumeLabel)) {
    $VolumeLabel = if ($hasUnattend) { "Win11_Unattended" } else { "Win11" }
}
if ($VolumeLabel -notmatch '^[A-Za-z0-9_\-]{1,32}$') {
    Write-Error "Volume label must be 1 to 32 characters of letters, digits, underscore or hyphen: $VolumeLabel"
    exit 1
}
Write-Host "Volume label will be $VolumeLabel"

if (!(Test-Path -Path $localOSCDPath)) {
    $OSCDurl = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"
    Write-Host "Downloading oscdimg.exe from $OSCDurl"
    Invoke-WebRequest -Uri $OSCDurl -OutFile $localOSCDPath
    if (Test-Path -Path $localOSCDPath) {
        Write-Host "oscdimg.exe downloaded successfully"
    } else {
        Write-Error "Failed to download oscdimg.exe"
        exit 1
    }
}

& "$localOSCDPath" '-m' '-o' '-u2' '-udfver102' "-l$VolumeLabel" "-bootdata:2#p0,e,b$biosBoot#pEF,e,b$efiBoot" "$UnpackedFolderPath" "$OutputISOPath"

# Pass oscdimg's result through so a wrapper or a CI step can tell a failed build from a good one.
# Its own output already says what went wrong, this just makes sure the script does not exit 0 after it.
$oscdimgExitCode = $LASTEXITCODE
if ($oscdimgExitCode -ne 0) {
    Write-Error "oscdimg.exe failed with exit code $oscdimgExitCode"
    exit $oscdimgExitCode
}
if (!(Test-Path -Path $OutputISOPath -PathType Leaf)) {
    Write-Error "oscdimg.exe returned 0 but no ISO was written to $OutputISOPath"
    exit 1
}

# Summarise what was built. When a student reports a problem, this is what identifies the ISO they have.
$iso = Get-Item -Path $OutputISOPath
$summary = [ordered]@{
    "ISO"          = $iso.FullName
    "Size"         = "{0:N2} GB" -f ($iso.Length / 1GB)
    "Volume label" = $VolumeLabel
    "UEFI boot"    = Split-Path -Path $efiBoot -Leaf
    "Answer file"  = if ($hasUnattend) { "autounattend.xml included" } else { "none, plain install media" }
}
if (!$SkipHash) {
    Write-Host "Hashing the ISO..."
    $hash = (Get-FileHash -Path $iso.FullName -Algorithm SHA256).Hash
    $hashPath = "$($iso.FullName).sha256.txt"
    Set-Content -Path $hashPath -Value $hash -Encoding Ascii
    $summary["SHA256"] = $hash
    $summary["Hash file"] = $hashPath
}
$summary["Build time"] = "{0:mm\:ss}" -f $buildTimer.Elapsed
Write-Host ""
Write-Host "Build complete"
$width = ($summary.Keys | Measure-Object -Property Length -Maximum).Maximum
foreach ($key in $summary.Keys) {
    Write-Host ("  {0,-$width}  {1}" -f $key, $summary[$key])
}
exit 0

# SIG # Begin signature block
# MIIQ4QYJKoZIhvcNAQcCoIIQ0jCCEM4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBqDc6u3O3SW1Dm
# 9mgZBVen9H/+Y+L0u14ZxQuwiu51hqCCDSYwggWgMIIEiKADAgECAhMSAAAGp51a
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
# FTAvBgkqhkiG9w0BCQQxIgQgojmUThwQAuiuWQ2WRTe8DPoLLLCocYyli7OVvkSO
# JtAwDQYJKoZIhvcNAQEBBQAEggIARR6nSlwETu8nmxCSkrtf9CG2Qs1x4PS2NXLm
# 9+gVuFZg0TxZ4hEpAbwoquPZLxR3mimLQc8Gc5Rs9oN1VAWN/En42qJbp0P0KsdB
# Ty7QkVT/C1sCCJJ9FnZXIV12BiX06RFvKQJXRxWiFo3OdHHg5TyrbnK+oSK1tbJw
# RjCzqDqOyr3XyI0Mp/swOX3Rp2dwGd3M/OxFpzlUxdYY8dHQmjdncyo0axh2xs5a
# 3yTttdO/tcDdn1jAZynndNFw9yC0Pzu0IeTbt4tizCml367NostgjGqxKpFWCbUh
# VXlq43jGlKdYMwSEli1p7XSt9MhM/5yI/auzQguBPAjCFZEEk1NDJfSVT72uZCEw
# 9hqslEZUzLB7iHJWm8Mm+CggS2tye69a2ACYS82GPepuDOqVp5+5IJ2+W6njfYRV
# hfCvd8dJrxRZ80kwXQrARqTW06hJzzu5Qk79EJL0A+O3mfQ6cpSBmUQBp05H1Ngs
# DXYwcImeWrFt1biJnQKo8TgJNjE8U8B7T7REYRr41oODp1B6+1quglttDnHjns3C
# GDdWXLTgKVVF8PT7QhgSrNAjmZd0lssPnGW9u3dl5ZtoKJ6IwbfquxMiAwurPjAX
# FuAUDfTzZgdI1C6Zo0AYm/G/i5ilxmSVTYWRQeOGm6ZWkUawGqt0/FUWRI/VRnww
# HdQ8+pk=
# SIG # End signature block
