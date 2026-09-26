# Checks that the APKs in this folder were built from the current source.
#
# The work is done by verify-apks.mjs; this only finds the bundled Node so you
# do not need one installed. See that file for why the check is worth running
# at all, and for the UTF-16 trap it works around.

. C:\sathiyaa-dev\env.ps1

$node = "C:\sathiyaa-dev\node\node.exe"
if (-not (Test-Path $node)) { $node = "node" }

& $node "$PSScriptRoot\verify-apks.mjs"
exit $LASTEXITCODE
