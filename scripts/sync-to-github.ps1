# Thin wrapper over sync-to-github.mjs, so this sits with the other scripts
# and can be run by double-clicking rather than remembering a node invocation.
#
#   .\sync-to-github.ps1            sync, then report what changed
#   .\sync-to-github.ps1 -DryRun    report only, write nothing
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$node = 'node'
if (Test-Path 'C:\sathiyaa-dev\node\node.exe') { $node = 'C:\sathiyaa-dev\node\node.exe' }

$args = @("$here\sync-to-github.mjs")
if ($DryRun) { $args += '--dry-run' }

& $node @args
exit $LASTEXITCODE
