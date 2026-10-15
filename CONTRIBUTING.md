# Contribuindo

Pull requests são bem-vindos. Para mudanças grandes, abra uma issue antes para
discutir o que você pretende alterar.

Antes de abrir o PR, rode no Windows PowerShell 5.1 (o mesmo do CI):

```powershell
.\tests\Testar-Atualizacao.ps1
Install-Module PSScriptAnalyzer -Scope CurrentUser   # uma vez só
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error
```

Convenções: tudo em pt-BR, inclusive nomes de funções e variáveis (`Percorrer`,
`$pastas`). Os `.ps1` ficam em ASCII, sem acento, porque o PowerShell 5.1 lê
arquivo sem BOM na página de código do sistema.