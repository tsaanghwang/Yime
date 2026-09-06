# Isolated module entry point for Rime/PIME package staging. Importing this
# module defines helpers only; it performs no build, copy, install, registration
# or process action.
. (Join-Path $PSScriptRoot 'rime-pime-package-staging.ps1')
Export-ModuleMember -Function '*-RimePime*','*-YimePime*'
