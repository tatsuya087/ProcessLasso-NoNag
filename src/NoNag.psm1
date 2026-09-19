Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:OriginalHash = '2f6f1005b5d67a7e7468c66b106d45ac0e2537cbc82fb6b7edce3c89fe9a989a'
$script:PatchedHash = 'b82a5b6f6cfe4e7ef416bb039ae986b348cea9e678978b17107b53bd3d562137'

function Get-DataHash([byte[]]$Data) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($Data)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-PathHash([string]$Path) {
    if ([IO.File]::Exists($Path)) { return Get-DataHash ([IO.File]::ReadAllBytes($Path)) }
    return ''
}

function Get-NoNagState([string]$Directory) {
    $full = [IO.Path]::GetFullPath($Directory)
    $target = Join-Path $full 'ProcessLasso.exe'
    $backup = Join-Path $full 'ProcessLasso-Original.exe'
    $hash = Get-PathHash $target
    $backupHash = Get-PathHash $backup
    $status = 'Unsupported or modified executable'
    $apply = $false
    $restore = $false
    if (-not $hash) { $status = 'Executable missing' }
    if ($hash -eq $script:OriginalHash) {
        $status = 'Original'
        $apply = -not (Test-Path -LiteralPath $backup)
        if (-not $apply) { $status = 'Original; backup already exists (apply blocked)' }
    }
    if ($hash -eq $script:PatchedHash) {
        $status = 'Patched'
        $restore = $backupHash -eq $script:OriginalHash
        if (-not $restore) { $status = 'Patched; verified backup missing (restore blocked)' }
    }
    [pscustomobject]@{
        Directory = $full; Target = $target; Backup = $backup
        Hash = $hash; BackupHash = $backupHash; Status = $status
        CanApply = $apply; CanRestore = $restore
    }
}

function Find-NoNagInstallation {
    $paths = @()
    foreach ($base in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base) { $paths += Join-Path $base 'Process Lasso' }
    }
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($entry in @(Get-ItemProperty $key -ErrorAction SilentlyContinue)) {
            if ($entry.PSObject.Properties['DisplayName'] -and $entry.DisplayName -like '*Process Lasso*' -and $entry.PSObject.Properties['InstallLocation'] -and $entry.InstallLocation) {
                $paths += $entry.InstallLocation
            }
        }
    }
    @($paths | Select-Object -Unique | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'ProcessLasso.exe') -PathType Leaf })
}

function Get-TargetGui([string]$Target) {
    foreach ($process in @(Get-Process -Name ProcessLasso -ErrorAction SilentlyContinue)) {
        try {
            $path = $process.MainModule.FileName
            if (-not $path) { throw 'Executable path unavailable.' }
        } catch {
            if ($process.HasExited) { continue }
            throw "Cannot identify ProcessLasso PID $($process.Id). No process will be force-closed."
        }
        if ([string]::Equals($path, $Target, [StringComparison]::OrdinalIgnoreCase)) {
            if ($process.SessionId -ne [Diagnostics.Process]::GetCurrentProcess().SessionId) {
                throw 'Process Lasso is running in another Windows session. Close it there before continuing.'
            }
            $process
        }
    }
}

function Stop-TargetGui([string]$Target) {
    $processes = @(Get-TargetGui $Target)
    if ($processes.Count -eq 0) { return $false }
    Write-Host 'Closing Process Lasso...'
    foreach ($process in $processes) {
        if (-not $process.HasExited) { $null = $process.CloseMainWindow() }
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    do {
        $remaining = @($processes | Where-Object { -not $_.HasExited })
        if ($remaining.Count -eq 0) { break }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($remaining.Count -gt 0) {
        if ((Read-Host 'Process Lasso did not exit. Force close it? [y/N]') -cnotmatch '^[yY]$') {
            throw 'Cancelled. Executable files were not changed.'
        }
        foreach ($process in $remaining) {
            if (-not $process.HasExited) {
                $process.Kill()
                if (-not $process.WaitForExit(5000)) { throw 'Process Lasso is still running.' }
            }
        }
    }
    if (@(Get-TargetGui $Target).Count -gt 0) { throw 'Process Lasso restarted itself. Close it and try again.' }
    return $true
}

function New-PatchedData([byte[]]$Data) {
    if ((Get-DataHash $Data) -ne $script:OriginalHash) { throw 'Source hash mismatch.' }
    $patches = @(
        @{ Offset = 0xDF00C; Before = [byte[]](0x74,0x4D); After = [byte[]](0xEB,0x4D) },
        @{ Offset = 0xE2532; Before = [byte[]](0x0F,0x85,0xD9,0,0,0); After = [byte[]](0xE9,0xDA,0,0,0,0x90) },
        @{ Offset = 0xE2618; Before = [byte[]](0x75,0x38); After = [byte[]](0xEB,0x38) }
    )
    foreach ($patch in $patches) {
        for ($i = 0; $i -lt $patch.Before.Length; $i++) {
            if ($Data[$patch.Offset + $i] -ne $patch.Before[$i]) { throw 'Patch bytes do not match.' }
        }
    }
    $output = [byte[]]$Data.Clone()
    foreach ($patch in $patches) { [Array]::Copy($patch.After, 0, $output, $patch.Offset, $patch.After.Length) }
    if ((Get-DataHash $output) -ne $script:PatchedHash) { throw 'Generated hash mismatch.' }
    return ,$output
}

function Replace-NoNagFile([string]$Source, [string]$Target, [string]$Backup) {
    [IO.File]::Replace($Source, $Target, $Backup)
}

function Assert-NoNagTarget([string]$Path, [string]$ExpectedHash) {
    if ((Get-PathHash $Path) -ne $ExpectedHash) { throw 'File verification failed.' }
}

function Invoke-NoNagChange {
    param([string]$Directory, [ValidateSet('Apply','Restore')][string]$Action)
    $state = Get-NoNagState $Directory
    if (($Action -eq 'Apply' -and -not $state.CanApply) -or ($Action -eq 'Restore' -and -not $state.CanRestore)) {
        throw "Cannot $($Action.ToLowerInvariant()): $($state.Status). No files were changed."
    }
    foreach ($path in @($state.Directory, $state.Target, $state.Backup)) {
        if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Linked installation paths are not supported.'
        }
    }
    $lockPath = Join-Path $state.Directory 'ProcessLasso-NoNag.lock'
    $lock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 1, [IO.FileOptions]::DeleteOnClose)
    $stage = Join-Path $state.Directory ('ProcessLasso-NoNag-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $replaceAttempted = $false
    $wasRunning = $false
    $success = $false
    $message = ''
    $restartSafe = $false
    try {
        $fresh = Get-NoNagState $state.Directory
        if ($fresh.Hash -ne $state.Hash -or $fresh.BackupHash -ne $state.BackupHash) { throw 'Files changed during preparation. Try again.' }
        if ($Action -eq 'Apply') {
            $data = New-PatchedData ([IO.File]::ReadAllBytes($state.Target))
            $stream = [IO.File]::Open($stage, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $stream.Write($data, 0, $data.Length); $stream.Flush($true) } finally { $stream.Dispose() }
            Assert-NoNagTarget $stage $script:PatchedHash
        }
        $wasRunning = Stop-TargetGui $state.Target
        Assert-NoNagTarget $state.Target $state.Hash
        if ((Get-PathHash $state.Backup) -ne $state.BackupHash) { throw 'Backup changed during preparation.' }
        if ($Action -eq 'Apply') {
            if (Test-Path -LiteralPath $state.Backup) { throw 'Backup already exists. It will not be overwritten.' }
            $replaceAttempted = $true
            Replace-NoNagFile $stage $state.Target $state.Backup
            Assert-NoNagTarget $state.Target $script:PatchedHash
            Assert-NoNagTarget $state.Backup $script:OriginalHash
        } else {
            $replaceAttempted = $true
            Replace-NoNagFile $state.Backup $state.Target $stage
            Assert-NoNagTarget $state.Target $script:OriginalHash
        }
        $success = $true
        $restartSafe = $true
        $message = if ($Action -eq 'Apply') { 'Patch applied. Original saved as ProcessLasso-Original.exe.' } else { 'Original restored. Backup returned to ProcessLasso.exe.' }
    } catch {
        $message = $_.Exception.Message
        try {
            if ($replaceAttempted) {
                $currentHash = Get-PathHash $state.Target
                if ($Action -eq 'Apply') {
                    if ($currentHash -eq $script:PatchedHash) {
                        Assert-NoNagTarget $state.Backup $script:OriginalHash
                        Replace-NoNagFile $state.Backup $state.Target $stage
                    } elseif (-not $currentHash) {
                        Assert-NoNagTarget $state.Backup $script:OriginalHash
                        [IO.File]::Move($state.Backup, $state.Target)
                    } elseif ($currentHash -ne $state.Hash) { throw 'Unexpected target contents; automatic recovery stopped.' }
                } else {
                    if ($currentHash -eq $script:OriginalHash) {
                        Assert-NoNagTarget $stage $script:PatchedHash
                        if (Test-Path -LiteralPath $state.Backup) { throw 'Backup path occupied; automatic recovery stopped.' }
                        Replace-NoNagFile $stage $state.Target $state.Backup
                    } elseif (-not $currentHash) {
                        Assert-NoNagTarget $stage $script:PatchedHash
                        [IO.File]::Move($stage, $state.Target)
                    } elseif ($currentHash -ne $state.Hash) { throw 'Unexpected target contents; automatic recovery stopped.' }
                }
                Assert-NoNagTarget $state.Target $state.Hash
                if ((Get-PathHash $state.Backup) -ne $state.BackupHash) { throw 'Backup state differs; inspect the files before retrying.' }
                $message += ' Previous state preserved or restored.'
            }
            $restartSafe = (Get-PathHash $state.Target) -eq $state.Hash
        } catch {
            $message += " Recovery incomplete: $($_.Exception.Message) Preserve the backup and temporary files."
        }
    } finally {
        if ($success -or $restartSafe) {
            if ([IO.File]::Exists($stage)) {
                try { [IO.File]::Delete($stage) } catch { $message += " Temporary file remains: $stage" }
            }
        }
        $lock.Dispose()
    }
    [pscustomobject]@{ Success = $success; Restart = ($wasRunning -and $restartSafe); Message = $message }
}

function New-NoNagWorkerCommand {
    param([string]$ScriptPath, [ValidateSet('Apply','Restore')][string]$Action, [string]$Installation)
    $scriptLiteral = $ScriptPath.Replace("'", "''")
    $pathLiteral = $Installation.Replace("'", "''")
    $command = "`$ErrorActionPreference = 'Stop'; & '$scriptLiteral' -Action '$Action' -Installation '$pathLiteral'; exit `$LASTEXITCODE"
    [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
}

Export-ModuleMember -Function Get-NoNagState, Find-NoNagInstallation, Invoke-NoNagChange, New-NoNagWorkerCommand
