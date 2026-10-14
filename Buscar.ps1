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

# --- Grupos de tipo: digite a palavra antes do termo para filtrar ---
$grupos = [ordered]@{
    excel    = @('xlsx','xls','xlsm','xlsb','csv')
    planilha = @('xlsx','xls','xlsm','xlsb','csv')
    word     = @('docx','doc','docm','rtf','odt')
    doc      = @('docx','doc','docm','rtf','odt')
    pdf      = @('pdf')
    imagem   = @('jpg','jpeg','png','gif','bmp','tif','tiff','webp')
    foto     = @('jpg','jpeg','png','gif','bmp','tif','tiff','webp')
    slide    = @('pptx','ppt','ppsx','odp')
    zip      = @('zip','rar','7z')
}

# --- remove acentos e caixa para busca "esperta" ---
# Aceita um texto ou uma lista inteira. Com a lista, o .NET normaliza tudo de
# uma vez: o laco caractere a caractere que existia aqui rodava em cada busca
# e levava ~35 s num catalogo de 120 mil arquivos.
function Normalizar($t) {
    if ($null -eq $t) { return '' }
    return ($t.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', '').ToLowerInvariant()
}

# --- garante que o indice exista ---
if (-not (Test-Path -LiteralPath $indice)) {
    Write-Host "  O catalogo ainda nao existe. Vou cria-lo agora (so na 1a vez)..." -ForegroundColor Yellow
    & $atualiza
    if (-not (Test-Path -LiteralPath $indice)) {
        Write-Host "  Nao foi possivel criar o catalogo. Verifique o acesso as pastas de rede." -ForegroundColor Red
        return
    }
}

function Carregar {
    $script:dados = @(Import-Csv -LiteralPath $indice)
    $script:idade = (Get-Date) - (Get-Item $indice).LastWriteTime
    # Nome e caminho ja sem acento, na mesma ordem de $dados: a busca so compara.
    $script:nomesN    = [string[]]@()
    $script:caminhosN = [string[]]@()
    if ($script:dados.Count -gt 0) {
        $script:nomesN    = [string[]]@(Normalizar $script:dados.Nome)
        $script:caminhosN = [string[]]@(Normalizar $script:dados.Caminho)
    }
}
Carregar

function Cabecalho {
    Write-Host ("  {0} arquivos no catalogo | atualizado ha {1:N0}h{2:N0}min" -f `
        $script:dados.Count, [math]::Floor($script:idade.TotalHours), $script:idade.Minutes) -ForegroundColor DarkGray
    # Um catalogo velho e a causa mais comum de "nao acha um arquivo que existe".
    if ($script:idade.TotalHours -ge 48) {
        Write-Host "  ATENCAO: catalogo com mais de 2 dias. Digite !r para atualizar." -ForegroundColor Yellow
    }
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'indice.parcial.csv')) {
        Write-Host "  AVISO: a ultima atualizacao ficou incompleta (indice.parcial.csv) e foi descartada." -ForegroundColor Yellow
    }
}

Clear-Host
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host "     BUSCADOR - pastas de rede" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Cabecalho
Write-Host ""
Write-Host "  Como usar:" -ForegroundColor Gray
Write-Host "    - Digite parte do nome (ex.: termino 2026)" -ForegroundColor Gray
Write-Host "    - Varias palavras = todas precisam aparecer" -ForegroundColor Gray
Write-Host "    - Acentos e maiusculas nao importam" -ForegroundColor Gray
Write-Host ("    - Filtro por tipo antes do termo: {0}" -f ($grupos.Keys -join ', ')) -ForegroundColor Gray
Write-Host "      (ex.:  excel termino    |   pdf contrato    |   excel   sozinho lista todas)" -ForegroundColor Gray
Write-Host "    - Comandos:  !p = procurar tambem no caminho da pasta" -ForegroundColor DarkGray
Write-Host "                 !r = atualizar catalogo   |   !s = sair" -ForegroundColor DarkGray
Write-Host ""

$buscarNoCaminho = $false

while ($true) {
    Write-Host ""
    $q = Read-Host "  Buscar"
    if (-not $q) { continue }
    if ($q -eq '!s') { break }
    if ($q -eq '!r') {
        & $atualiza
        Carregar
        Cabecalho
        continue
    }
    if ($q -eq '!p') {
        $buscarNoCaminho = -not $buscarNoCaminho
        $estado = if ($buscarNoCaminho) { 'nome + caminho da pasta' } else { 'somente o nome' }
        Write-Host ("  Busca agora considera: {0}" -f $estado) -ForegroundColor Cyan
        continue
    }

    $tokens = @($q -split '\s+' | Where-Object { $_ })

    # --- filtro opcional por tipo de arquivo ---
    $extsFiltro = $null
    $primeiro   = Normalizar $tokens[0]
    if ($grupos.Contains($primeiro)) {
        $extsFiltro = $grupos[$primeiro]
        # Sem esta guarda, "excel" sozinho virava termo de busca em vez de filtro.
        if ($tokens.Count -gt 1) { $tokens = $tokens[1..($tokens.Count - 1)] } else { $tokens = @() }
    }
    $termos = @($tokens | ForEach-Object { Normalizar $_ })

    if ($termos.Count -eq 0 -and -not $extsFiltro) { continue }

    # Contains em vez de -like: colchete digitado ("[final]") e texto literal.
    # Com -like ele virava curinga e trazia qualquer nome com f, i, n, a ou l.
    $alvos = if ($buscarNoCaminho) { $script:caminhosN } else { $script:nomesN }
    $res = for ($i = 0; $i -lt $alvos.Length; $i++) {
        $item = $script:dados[$i]
        if ($extsFiltro -and $item.Ext -notin $extsFiltro) { continue }
        $alvo = $alvos[$i]
        $ok = $true
        foreach ($t in $termos) { if (-not $alvo.Contains($t)) { $ok = $false; break } }
        if ($ok) { $item }
    }
    $res = $res | Sort-Object -Property Modificado -Descending   # 'yyyy-MM-dd HH:mm' ordena como texto

    $n = @($res).Count
    if ($n -eq 0) {
        Write-Host "  Nada encontrado." -ForegroundColor Yellow
        if (-not $buscarNoCaminho) {
            Write-Host "  Dica: !p procura tambem no caminho da pasta; !r atualiza o catalogo." -ForegroundColor DarkGray
        } else {
            Write-Host "  Dica: !r atualiza o catalogo." -ForegroundColor DarkGray
        }
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
            } else {
                # O catalogo e uma foto do passado: o arquivo pode ter sido movido.
                Write-Host ("  Nao esta mais em: {0}" -f $item.Caminho) -ForegroundColor Yellow
                Write-Host "  O catalogo pode estar desatualizado (!r para atualizar)." -ForegroundColor DarkGray
            }
        }
    } else {
        $res | Select-Object Nome, Modificado, MB, Pasta | Format-Table -AutoSize -Wrap | Out-Host
    }
}

Write-Host "  Ate mais!" -ForegroundColor Cyan
