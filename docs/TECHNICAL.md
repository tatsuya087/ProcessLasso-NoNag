# Technical details

## Supported binary

Process Lasso 18.3.0.34 x64, 2,631,664 bytes. The SHA-256 identifies the supported executable; the version label alone is insufficient.

| State | SHA-256 |
|---|---|
| Original | `2f6f1005b5d67a7e7468c66b106d45ac0e2537cbc82fb6b7edce3c89fe9a989a` |
| Patched | `b82a5b6f6cfe4e7ef416bb039ae986b348cea9e678978b17107b53bd3d562137` |

## Patch

Three branches skip startup purchase reminders, startup discount offers, and purchase reminders on GUI redisplay. Six bytes change.

| File offset | Original | Replacement |
|---|---|---|
| `0xDF00C` | `74 4D` | `EB 4D` |
| `0xE2532` | `0F 85 D9 00 00 00` | `E9 DA 00 00 00 90` |
| `0xE2618` | `75 38` | `EB 38` |

The shared predicate, generic dialog function, and core engine are unchanged. Explicit `/nag` invocation is not patched. This does not unlock Pro features. The modified signature reports `HashMismatch`.

## File operations

Apply stages and verifies the payload before replacing the target and retaining the original backup. Restore requires the known patched target and verified original backup. Updated targets cannot be downgraded using an old backup.

Operations use a directory lock and Windows file replacement. Caught failures attempt rollback; unexpected contents stop recovery. On incomplete recovery, preserve the backup and `ProcessLasso-NoNag-*.tmp` files. Recover from a verified installer or VM checkpoint if necessary.

## Process handling

Only the selected installation's GUI is closed. Another Windows session blocks the operation. After an eight-second graceful-exit attempt, force-close requires confirmation. The core engine is not stopped.

The elevated worker returns an exit code to the menu: 0 = success, 1 = failure, 10 = success and restart, 11 = recovered failure and restart. The encoded-command wrapper forwards the code explicitly. The menu verifies the resulting file state before restarting under its own privilege level.

This PowerShell implementation is separate from the referenced project; patch locations were derived from 18.3.0.34 analysis. Upstream Python code and vendor binaries are not included.
