# Windows distribution

Ghostty currently provides a portable Windows ZIP. It is not an installer and
does not register shortcuts, file associations, an AppUserModelID (AUMID), or
toast activation metadata.

Build and package on Windows with PowerShell 7 or newer:

```powershell
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseFast
./dist/windows/package.ps1
```

The script consumes the installed `zig-out` tree and writes
`zig-out/dist/ghostty-<version>-windows-<architecture>.zip`. Use `-ZigOut` and
`-OutputPath` for non-default paths, and `-Architecture aarch64` when packaging
an ARM64 build. The ZIP contains `bin/ghostty.exe`, the installed `share` tree,
and `LICENSE`. PDBs, import libraries, headers, and standalone library DLLs are
development artifacts and are intentionally excluded.

Archive paths are sorted and timestamps and permissions are normalized, so the
same inputs produce the same bytes. The script fails when the executable,
license, resource tree, or Windows terminfo sentinel is missing.

## Future installer metadata

Reliable toast notifications for an unpackaged desktop application require a
stable AUMID, a Start Menu shortcut carrying that AUMID, and an activation
strategy. A portable ZIP cannot legitimately perform that registration. Put
those values in the future installer source when an installer technology is
adopted rather than shipping inactive or misleading metadata in this archive.
