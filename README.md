# Build-UnattendedWindows11ISO

Rebuilds a bootable Windows ISO from an unpacked installation folder, so an
`autounattend.xml` dropped into the folder rides along in the image. The script
checks that `sources\install.wim` and `sources\boot.wim` are present, finds
`oscdimg.exe` in the Windows ADK or installs it with winget if there is no local copy,
and calls it with the UEFI and BIOS boot configuration a Windows install media needs.

| File | What it is |
|---|---|
| `Build-UnattendedWindows11ISO.ps1` | The signed script. Last code change 2026-11-09 |

## No AI use except by the originating instructor

Only the originating instructor, Clayton Amelia, may use AI tooling on this
repository. The content, scripts and decisions here are his intellectual
property, and collaborator access was granted for using the material, not for
feeding it to a model. If you are any other collaborator, do not paste,
upload or point an AI assistant, code completion model or chat model at any
part of this repository, and disable editor AI features while working in it.
This repository has no decision record, so this note is the record.

## Getting the source folder

The script needs the ISO's contents unpacked into a plain folder. Windows can mount an ISO
but will not copy it out as a folder in one step, so the simplest route is an archive tool
that reads ISO images directly, such as [7-Zip](https://www.7-zip.org/), PeaZip or WinRAR:

1. Right-click the Windows 11 ISO and extract it to a folder next to the script.
2. Rename the extracted folder to `Windows11`, with no spaces. 7-Zip names it after the
   ISO, which is usually something like `Win11_24H2_English_x64`.
3. Drop your `autounattend.xml` into the root of that `Windows11` folder.

With the folder named `Windows11` the script's defaults line up and it runs with no
parameters. Any other folder name works too, you just pass it with `-UnpackedFolderPath`.

The script does not write answer files, but it does look for one. If there is no
`autounattend.xml` in the folder root it warns that the ISO will be ordinary install
media. If the file is there it is parsed, and a file that is not well-formed XML or does
not have the Windows Setup `unattend` root element stops the build, since Setup would
silently ignore it and the install would sit at the first interactive screen. Pass
`-SkipUnattendCheck` when plain media is what you want.

## Boot files

The script does not ship any boot code of its own. It points `oscdimg` at files that are
already inside the extracted ISO, and checks they exist before it starts:

| File | Path inside `Windows11` | Role |
|---|---|---|
| `efisys_noprompt.bin` | `efi\microsoft\boot\efisys_noprompt.bin` | UEFI boot image with no "Press any key" prompt. Used when present |
| `efisys.bin` | `efi\microsoft\boot\efisys.bin` | Standard UEFI boot image. Used with `-KeepPrompt`, or as a fallback with a warning if the no-prompt one is missing |
| `etfsboot.com` | `boot\etfsboot.com` | Legacy BIOS boot sector, kept so the ISO also boots on older firmware |

`efisys.bin` is the small FAT image holding the UEFI bootloader, and it is the file
Microsoft's own `-bootdata` example uses. See the
[oscdimg command-line options](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/oscdimg-command-line-options)
on Microsoft Learn for what each flag does. Microsoft ships both variants in every
Windows ISO. The only difference is that `efisys_noprompt.bin` skips the "Press any key
to boot from CD or DVD" message, which is the step that would otherwise stall a hands-off
install. The script picks the no-prompt variant automatically, so there is nothing to
rename. If you ever build with `oscdimg` by hand, the equivalent is to copy
`efisys_noprompt.bin` over `efisys.bin` before running it.

The trade-off is that a no-prompt ISO left in a VM's virtual drive will reinstall on the
next reboot without asking, so detach the media once the install is going. If you would
rather the ISO wait for a key press, pass `-KeepPrompt` and the script boots it with
`efisys.bin` instead.

## Getting oscdimg.exe

`oscdimg.exe` is Microsoft's ISO mastering tool. It ships inside the Windows ADK and is
not offered as a standalone download with a published checksum, so the script accepts a
copy only if it passes one of two tests: a valid Microsoft Authenticode signature, which
the ADK copy carries, or a SHA256 that matches the `Microsoft.OSCDIMG` winget manifest,
which is what the symbol server copy has. It tries these locations in order and says
which one it used in the build summary:

| Order | Location | What usually passes |
|---|---|---|
| 1 | The path in `-localOSCDPath`, default `.\oscdimg.exe` | A copy taken from the ADK, or one winget fetched. Anything else is skipped with a warning |
| 2 | Windows ADK Deployment Tools, found through the Installed Roots registry key | Signed by Microsoft |
| 3 | The `Microsoft.OSCDIMG` winget package, installed if it is not already there | winget checks the hash on download and the script checks it again |

If none of those yields a verifiable copy the script stops and says so. It never fetches
the file from a hard-coded URL, because there is nothing to check such a download against.
The manifest hash is read live with `winget show`, so it tracks the file when Microsoft
re-uploads it. The manifest is community-submitted and reviewed in the
[winget-pkgs](https://github.com/microsoft/winget-pkgs/tree/master/manifests/m/Microsoft/OSCDIMG)
repository, and the symbol server copy it points at is not signed.

## Usage

From the folder:

```powershell
.\Build-UnattendedWindows11ISO.ps1 -UnpackedFolderPath 'C:\Win11Files' -OutputISOPath 'C:\Win11-Unattended.iso'
```

Defaults are `.\Windows11` for the source and `.\oscdimg.exe` for the tool. The output
defaults to `.\Windows11-Unattended.iso` when the source folder has an `autounattend.xml`
and `.\Windows11.iso` when it does not, so the file name says which kind of media it is.
Pass `-OutputISOPath` to choose your own. Add `-KeepPrompt` to keep the "Press any key"
prompt in the built ISO, and `-Force` to overwrite an ISO that is already at the output
path. The script checks the output folder exists and refuses to write the ISO inside the
source folder before it starts `oscdimg`.

The ISO gets a volume label instead of oscdimg's default `DVD_ROM`, so a mounted image
says what it is. The label follows the same rule as the file name: `Win11_Unattended`
with an answer file, `Win11` without. Pass `-VolumeLabel` to set your own, up to 32
characters of letters, digits, underscore or hyphen.

The script exits 0 only when `oscdimg` succeeded and the ISO is on disk. A failed check
exits 1, and an `oscdimg` failure exits with `oscdimg`'s own code, so a calling script
can test `$LASTEXITCODE` instead of parsing the output.

A successful build ends with a summary: the ISO path and size, the volume label, which
UEFI boot image went in, whether an answer file was included, the SHA256 of the ISO and
the build time. The hash is also written beside the ISO as `<name>.iso.sha256.txt`, so
the copy a student has can be checked against the one that was built. Pass `-SkipHash`
to leave the hash out of a quick test build.

Related: the `course-lab-build` repo has `New-NoPromptIso.ps1`, which does the
narrower job of removing the "press any key to boot" prompt from a Server ISO.

## Reuse

Written by Clayton Amelia. No open licence is granted. Reuse and adaptation by
other NAIT instructors is welcome with credit, and reuse outside NAIT means
getting in touch first. Reuse never includes AI use, see the note at the top of
this README. `oscdimg.exe` and Windows media are Microsoft's and are not part of
this work. The repository carried CC BY-NC-SA 4.0 until 2026-10-16, and versions
published before that date remain available under it.
