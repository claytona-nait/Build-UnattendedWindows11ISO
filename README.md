# Build-UnattendedWindows11ISO

Rebuilds a bootable Windows ISO from an unpacked installation folder, so an
`autounattend.xml` dropped into the folder rides along in the image. The script
checks that `sources\install.wim` and `sources\boot.wim` are present, downloads
`oscdimg.exe` from Microsoft if there is no local copy, and calls it with the
UEFI and BIOS boot configuration a Windows install media needs.

| File | What it is |
|---|---|
| `Build-UnattendedWindows11ISO.ps1` | The signed script. Last code change 2026-10-13 |

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

## Boot files

The script does not ship any boot code of its own. It points `oscdimg` at files that are
already inside the extracted ISO, and checks they exist before it starts:

| File | Path inside `Windows11` | Role |
|---|---|---|
| `efisys_noprompt.bin` | `efi\microsoft\boot\efisys_noprompt.bin` | UEFI boot image with no "Press any key" prompt. Used when present |
| `efisys.bin` | `efi\microsoft\boot\efisys.bin` | Standard UEFI boot image. Fallback, with a warning, if the no-prompt one is missing |
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
next reboot without asking, so detach the media once the install is going.

## Usage

From the folder:

```powershell
.\Build-UnattendedWindows11ISO.ps1 -UnpackedFolderPath 'C:\Win11Files' -OutputISOPath 'C:\Win11-Unattended.iso'
```

Defaults are `.\Windows11` for the source, `.\Windows11-Unattended.iso` for the
output and `.\oscdimg.exe` for the tool.

Related: the `course-lab-build` repo has `New-NoPromptIso.ps1`, which does the
narrower job of removing the "press any key to boot" prompt from a Server ISO.

## License

[CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) — Creative Commons
Attribution-NonCommercial-ShareAlike. Share and adapt it freely for non-commercial use,
credit Clayton Amelia, and release any derivative under the same license. See
[LICENSE.md](LICENSE.md) for the details, including what the license does not cover
(`oscdimg.exe` and Windows media are Microsoft's).
