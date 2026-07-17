# ============================================================
#  Buscar.ps1  -  Buscador das pastas de rede configuradas
#  Somente leitura. Digite parte do nome e ele mostra onde esta.
#  Duplo-clique num resultado abre a PASTA do arquivo no Explorer.
# ============================================================

$ErrorActionPreference = 'SilentlyContinue'

# --- Nome do catalogo pode vir de config.json (nao versionado); padrao 'indice.csv' ---
$configPath = Join-Path $PSScriptRoot 'config.json'
$indexName  = 'indice.csv'
if (Test-Path -LiteralPath $configPath) {
    $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if ($cfg.indexFile) { $indexName = $cfg.indexFile }
}
$indice   = Join-Path $PSScriptRoot $indexName
$atualiza = Join-Path $PSScriptRoot 'Atualizar-Indice.ps1'

# --- remove acentos e caixa para busca "esperta" ---
function Normalizar([string]$t) {
    if (-not $t) { return '' }
    $n = $t.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($c in $n.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne 'NonSpacingMark') {
            [void]$sb.Append($c)
        }
    }
    return $sb.ToString().ToLowerInvariant()
}

# --- garante que o indice exista ---
if (-not (Test-Path -LiteralPath $indice)) {
    Write-Host "  O catalogo ainda nao existe. Vou cria-lo agora (so na 1a vez)..." -ForegroundColor Yellow
    & $atualiza
}

$dados = Import-Csv -LiteralPath $indice
$idade = (Get-Date) - (Get-Item $indice).LastWriteTime

Clear-Host
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "     BUSCADOR - pastas de rede" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ("  {0} arquivos no catalogo | atualizado ha {1:N0}h{2:N0}min" -f $dados.Count, [math]::Floor($idade.TotalHours), $idade.Minutes) -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Como usar:" -ForegroundColor Gray
Write-Host "    - Digite parte do nome (ex.: termino 2026)" -ForegroundColor Gray
Write-Host "    - Varias palavras = todas precisam aparecer no nome" -ForegroundColor Gray
Write-Host "    - Acentos e maiusculas nao importam" -ForegroundColor Gray
Write-Host "    - Digite  excel   antes do termo para so planilhas (ex.: excel termino)" -ForegroundColor Gray
Write-Host "    - Comandos:  !r = atualizar catalogo   |   !s = sair" -ForegroundColor DarkGray
Write-Host ""

while ($true) {
    Write-Host ""
    $q = Read-Host "  Buscar"
    if (-not $q) { continue }
    if ($q -eq '!s') { break }
    if ($q -eq '!r') { & $atualiza; $dados = Import-Csv -LiteralPath $indice; continue }

    $tokens = $q -split '\s+' | Where-Object { $_ }

    # filtro opcional de Excel
    $soExcel = $false
    if ($tokens[0] -in @('excel','xls','xlsx','planilha','planilhas')) {
        $soExcel = $true
        $tokens  = $tokens[1..($tokens.Count-1)]
    }
    $termos = $tokens | ForEach-Object { Normalizar $_ }

    $res = $dados | Where-Object {
        $nome = Normalizar $_.Nome
        $ok = $true
        foreach ($t in $termos) { if ($nome -notlike "*$t*") { $ok = $false; break } }
        if ($soExcel -and $_.Ext -notin @('xlsx','xls','xlsm','csv')) { $ok = $false }
        $ok
    } | Sort-Object { [datetime]$_.Modificado } -Descending

    $n = @($res).Count
    if ($n -eq 0) {
        Write-Host "  Nada encontrado. Tente outra grafia ou !r para atualizar." -ForegroundColor Yellow
        continue
    }

    Write-Host ("  {0} resultado(s). Abrindo a lista... (selecione e OK para abrir a pasta)" -f $n) -ForegroundColor Green

    $temGrid = Get-Command Out-GridView -ErrorAction SilentlyContinue
    if ($temGrid) {
        $escolha = $res |
            Select-Object Nome, Ext, Modificado, MB, Pasta, Caminho |
            Out-GridView -Title ("$n resultado(s) para: $q  -  selecione e clique OK") -PassThru
        foreach ($item in $escolha) {
            if (Test-Path -LiteralPath $item.Caminho) {
                explorer.exe "/select,`"$($item.Caminho)`""
            }
        }
    } else {
        $res | Select-Object Nome, Modificado, MB, Pasta | Format-Table -AutoSize -Wrap | Out-Host
    }
}

Write-Host "  Ate mais!" -ForegroundColor Cyan
