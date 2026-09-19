# Maintainer checks

Run from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-NoNag.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-WorkerExitCodes.ps1
```

Transaction tests use temporary synthetic files and stub GUI operations. To test a verified original executable without changing it, add `-FixturePath 'path\to\ProcessLasso.exe'` to the first command.

## Manual checks

Use a VM and keep a baseline checkpoint.

- Apply and restore with the GUI open and closed; check hashes against TECHNICAL.md.
- Confirm UAC, graceful exit, force-close acceptance/cancellation, and restart behavior.
- Check startup, normal launch, tray redisplay, list updates, settings, and core-engine reconnection.
- Check existing/missing/corrupt backups, unsupported targets, and concurrent operations.
- Check custom paths and another Windows session.

## Distribution

Keep tests and CI configuration in Git. The user ZIP contains `Start.cmd`, `src/CLI.ps1`, `src/NoNag.psm1`, `README.md`, `docs/TECHNICAL.md`, and `LICENSE`. Exclude tests, maintainer checklists, and vendor binaries.

Push a tool-version tag such as `v1.0.0` to run tests, build the ZIP, and create a **draft** GitHub Release. Review its notes and attachment, then publish manually. An existing release is not overwritten; a rerun for that tag stops at release creation.

To build the same ZIP locally:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Release.ps1 -Tag v1.0.0
```

Output: `dist/ProcessLasso-NoNag-v1.0.0.zip`. Existing output files are not overwritten.
