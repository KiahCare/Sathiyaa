# Thin wrapper over sync-to-github.mjs, so this sits with the other scripts
# and can be run by double-clicking rather than remembering a node invocation.
#
#   .\sync-to-github.ps1              sync both repositories, then report
#   .\sync-to-github.ps1 -DryRun      report only, write nothing
#   .\sync-to-github.ps1 -Only apps   just that repository (apps | platform)
param(
    [switch]$DryRun,
    [ValidateSet('apps', 'platform')]
    [string]$Only = ''
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$node = 'node'
if (Test-Path 'C:\sathiyaa-dev\node\node.exe') { $node = 'C:\sathiyaa-dev\node\node.exe' }

$nodeArgs = @("$here\sync-to-github.mjs")
if ($DryRun) { $nodeArgs += '--dry-run' }
if ($Only -ne '') { $nodeArgs += "--only=$Only" }

& $node @nodeArgs
exit $LASTEXITCODE
