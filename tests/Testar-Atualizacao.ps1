# ============================================================
#  tests/Testar-Atualizacao.ps1
#  Roda o Atualizar-Indice.ps1 de verdade numa arvore de pastas
#  temporaria e confere o que o README promete: o que entra no
#  catalogo, os codigos de saida e a protecao do catalogo bom.
#  Nao toca em nenhuma pasta real: tudo acontece dentro do TEMP.
#
#  Uso: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Testar-Atualizacao.ps1
# ============================================================

$ErrorActionPreference = 'Stop'

$origem = Join-Path (Split-Path $PSScriptRoot -Parent) 'Atualizar-Indice.ps1'
$base   = Join-Path ([IO.Path]::GetTempPath()) ('buscador-teste-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$app    = Join-Path $base 'app'    # copia do script; o catalogo nasce aqui
$raiz   = Join-Path $base 'rede'   # faz o papel da pasta de rede
$fora   = Join-Path $base 'fora'   # alvo de um ponto de juncao: nao pode entrar
$juncao = Join-Path $raiz 'atalho'

$script:falhas = 0
$script:saida  = ''

function Confere([bool]$condicao, [string]$descricao) {
    if ($condicao) {
        Write-Host "  ok    $descricao" -ForegroundColor Green
    } else {
        Write-Host "  FALHA $descricao" -ForegroundColor Red
        Write-Host ($script:saida -replace '(?m)^', '        | ') -ForegroundColor DarkGray
        $script:falhas++
    }
}

# Processo separado, como no .bat: o exit do script vira o codigo de saida.
function Rodar {
    $script:saida = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $app 'Atualizar-Indice.ps1') | Out-String)
    return $LASTEXITCODE
}

function Configurar([string[]]$raizes) {
    $json = @{ searchRoots = $raizes; indexFile = 'indice.csv' } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $app 'config.json') -Value $json -Encoding UTF8
}

function Arquivo([string]$relativo) {
    $cheio = Join-Path $raiz $relativo
    New-Item -ItemType Directory -Force -Path (Split-Path $cheio -Parent) | Out-Null
    Set-Content -LiteralPath $cheio -Value 'x' -Encoding ASCII
}

# A virgula impede o PowerShell de desfazer o array na volta: com uma linha so,
# viria um PSCustomObject solto, que no 5.1 nem tem .Count.
function Catalogo([string]$nome) {
    $p = Join-Path $app $nome
    if (-not (Test-Path -LiteralPath $p)) { return ,@() }
    return ,@(Import-Csv -LiteralPath $p)
}

function Existe([string]$nome) { Test-Path -LiteralPath (Join-Path $app $nome) }

# Nome com acento montado por codigo: o script fica em ASCII, como os outros.
$acentuado = 'Relat{0}rio a{1}{2}o.docx' -f [char]0x00F3, [char]0x00E7, [char]0x00E3
$validos   = @('contrato.pdf', 'Financeiro\Fechamento 2026.XLSX', 'Financeiro\relatorio [final].docx', "RH\$acentuado")

try {
    New-Item -ItemType Directory -Force -Path $app, $raiz, $fora | Out-Null
    Copy-Item -LiteralPath $origem -Destination $app

    Write-Host 'Sem config.json'
    Confere ((Rodar) -eq 1) 'sai com codigo 1'
    Confere (-not (Existe 'indice.csv')) 'nao cria catalogo'

    Write-Host 'Primeira varredura'
    $validos | ForEach-Object { Arquivo $_ }
    Arquivo 'RH\~$temporario.docx'            # temporario do Office
    Arquivo 'projeto\node_modules\lib.js'     # pasta de lixo tecnico
    Arquivo '.git\config'
    Set-Content -LiteralPath (Join-Path $fora 'fora.txt') -Value 'x'
    New-Item -ItemType Junction -Path $juncao -Target $fora | Out-Null
    Set-Content -LiteralPath (Join-Path $app 'indice.tmp.99999.csv') -Value 'abandonado'
    Configurar @($raiz)

    Confere ((Rodar) -eq 0) 'sai com codigo 0'
    $cat = Catalogo 'indice.csv'
    $nomes = @($cat | ForEach-Object { $_.Nome } | Sort-Object)
    $esperados = @($validos | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object)
    Confere (($nomes -join '|') -ceq ($esperados -join '|')) ("cataloga so os 4 arquivos validos (veio: {0})" -f ($nomes -join ', '))
    Confere (@($cat | Where-Object { $_.Caminho -like '*node_modules*' -or $_.Caminho -like '*\.git\*' }).Count -eq 0) 'ignora node_modules e .git'
    Confere (@($cat | Where-Object { $_.Nome -eq 'fora.txt' }).Count -eq 0) 'nao segue ponto de juncao'
    Confere (@($cat | Where-Object { $_.Nome -ceq $acentuado }).Count -eq 1) 'acento sobrevive ao CSV'
    $planilha = @($cat | Where-Object { $_.Nome -eq 'Fechamento 2026.XLSX' })[0]
    Confere ($planilha.Ext -ceq 'xlsx') 'extensao em minusculas e sem ponto'
    Confere ($planilha.Caminho -eq (Join-Path $raiz 'Financeiro\Fechamento 2026.XLSX')) 'caminho completo'
    Confere (-not (Existe 'indice.tmp.99999.csv')) 'remove temporario abandonado'
    Confere (-not (Existe 'indice.parcial.csv')) 'nao deixa parcial'

    Write-Host 'Rede devolve menos da metade dos arquivos'
    $validos[1..3] | ForEach-Object { Remove-Item -LiteralPath (Join-Path $raiz $_) }
    Confere ((Rodar) -eq 2) 'sai com codigo 2'
    Confere ((Catalogo 'indice.csv').Count -eq 4) 'mantem o catalogo antigo'
    Confere ((Catalogo 'indice.parcial.csv').Count -eq 1) 'guarda o resultado em indice.parcial.csv'
    Confere (@(Get-ChildItem -LiteralPath $app -Filter 'indice.tmp.*.csv').Count -eq 0) 'nao deixa temporario'

    Write-Host 'Uma das pastas nao responde'
    $validos | ForEach-Object { Arquivo $_ }
    Configurar @($raiz, (Join-Path $base 'nao-existe'))
    Confere ((Rodar) -eq 2) 'sai com codigo 2'
    Confere ($script:saida -match 'nao-existe') 'avisa qual pasta falhou'
    Confere ((Catalogo 'indice.csv').Count -eq 4) 'mantem o catalogo antigo'

    Write-Host 'Atualizacao completa depois da falha'
    Arquivo 'novo.pdf'
    Configurar @($raiz)
    Confere ((Rodar) -eq 0) 'sai com codigo 0'
    Confere ((Catalogo 'indice.csv').Count -eq 5) 'catalogo novo entra'
    Confere ((Catalogo 'indice.anterior.csv').Count -eq 4) 'o anterior vira indice.anterior.csv'
    Confere (-not (Existe 'indice.parcial.csv')) 'apaga o parcial da falha anterior'
}
finally {
    # Tira a juncao antes: assim a limpeza nunca atravessa para o alvo.
    if (Test-Path -LiteralPath $juncao) { [IO.Directory]::Delete($juncao) }
    if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force }
}

Write-Host ''
if ($script:falhas -gt 0) {
    Write-Host ("{0} verificacao(oes) falharam." -f $script:falhas) -ForegroundColor Red
    exit 1
}
Write-Host 'Todas as verificacoes passaram.' -ForegroundColor Green
