# Build-UnattendedWindows11ISO

Rebuilds a bootable Windows ISO from an unpacked installation folder, so an
`autounattend.xml` dropped into the folder rides along in the image. The script
checks that `sources\install.wim` and `sources\boot.wim` are present, downloads
`oscdimg.exe` from Microsoft if there is no local copy, and calls it with the
UEFI and BIOS boot configuration a Windows install media needs.

| File | What it is |
|---|---|
| `Build-UnattendedWindows11ISO.ps1` | The signed script. Last code change 2025-11-02 |

Usage, from the folder:

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
