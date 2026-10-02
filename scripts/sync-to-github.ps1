# Thin wrapper over sync-to-github.mjs, so this sits with the other scripts
# and can be run by double-clicking rather than remembering a node invocation.
#
#   .\sync-to-github.ps1                  the live repository (_github), then report
#   .\sync-to-github.ps1 -All             that plus the staged sathiyaa-apps / -platform
#   .\sync-to-github.ps1 -Only apps       just one of them
#   .\sync-to-github.ps1 -DryRun          report only, write nothing
#
# The two staged repositories do not exist on GitHub yet, which is why the
# monorepo is the default. See CONTRIBUTING.md.
param(
    [switch]$DryRun,
    [switch]$All,
    [ValidateSet('monorepo', 'apps', 'platform')]
    [string]$Only = ''
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$node = 'node'
if (Test-Path 'C:\sathiyaa-dev\node\node.exe') { $node = 'C:\sathiyaa-dev\node\node.exe' }

$nodeArgs = @("$here\sync-to-github.mjs")
if ($DryRun) { $nodeArgs += '--dry-run' }
if ($All) { $nodeArgs += '--all' }
if ($Only -ne '') { $nodeArgs += "--only=$Only" }

& $node @nodeArgs
exit $LASTEXITCODE
