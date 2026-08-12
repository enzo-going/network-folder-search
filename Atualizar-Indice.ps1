# ============================================================
#  Atualizar-Indice.ps1
#  Varre as pastas de rede (SOMENTE LEITURA) e salva um
#  catalogo local (indice.csv) para buscas instantaneas.
#  NAO abre, move, renomeia ou altera nenhum arquivo da rede.
# ============================================================

# Erros de leitura (pasta sem permissao, arquivo sumindo no meio da varredura)
# sao esperados e tratados item a item. O que NAO pode passar despercebido e a
# falha ao gravar o catalogo, entao a gravacao usa -ErrorAction Stop.
$ErrorActionPreference = 'SilentlyContinue'

# --- Pastas a catalogar: lidas de config.json (nao versionado). Veja config.example.json. ---
$configPath = Join-Path $PSScriptRoot 'config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Warning "Configuracao ausente. Copie 'config.example.json' para 'config.json' e ajuste 'searchRoots'."
    return
}
$config    = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$pastas    = @($config.searchRoots)
$indexFile = if ($config.indexFile) { $config.indexFile } else { 'indice.csv' }
if (-not $pastas -or $pastas.Count -eq 0) {
    Write-Warning "Defina ao menos uma pasta em 'searchRoots' no config.json."
    return
}

# --- Pastas a IGNORAR (lixo tecnico que so atrapalha a busca). Edite a vontade. ---
$ignorarPastas = @('node_modules','.git','.svn','.cache','$recycle.bin','__pycache__')

$destino = Join-Path $PSScriptRoot $indexFile
$tmp     = Join-Path $PSScriptRoot ("indice.tmp.$PID.csv")   # unico por processo
$parcial = Join-Path $PSScriptRoot 'indice.parcial.csv'
$backup  = Join-Path $PSScriptRoot 'indice.anterior.csv'

# --- Percorre uma raiz "podando" pastas de lixo e evitando loops (reparse points) ---
function Percorrer([string]$raiz, [string[]]$ignorar) {
    $fila = New-Object System.Collections.Generic.Queue[string]
    $fila.Enqueue($raiz)
    while ($fila.Count -gt 0) {
        $dir = $fila.Dequeue()
        foreach ($it in (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
            if ($it.PSIsContainer) {
                if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($ignorar -contains $it.Name.ToLower()) { continue }
                $fila.Enqueue($it.FullName)
            }
            elseif (-not $it.Name.StartsWith('~$')) {   # ignora arquivos temporarios do Office
                $it
            }
        }
    }
}

# --- Quantas linhas tem o catalogo atual (para comparar no fim) ---
function ContarLinhas([string]$arquivo) {
    if (-not (Test-Path -LiteralPath $arquivo)) { return 0 }
    $n = 0
    $leitor = [IO.File]::OpenText($arquivo)
    try { while ($null -ne $leitor.ReadLine()) { $n++ } } finally { $leitor.Close() }
    return [Math]::Max(0, $n - 1)   # desconta o cabecalho
}

Write-Host ""
Write-Host "  Catalogando arquivos das pastas de rede (somente leitura)..." -ForegroundColor Cyan
Write-Host "  Pode levar alguns minutos na 1a vez. O contador abaixo mostra que esta funcionando." -ForegroundColor DarkGray
Write-Host ""

$inicio    = Get-Date
$total     = 0
$anterior  = ContarLinhas $destino
$falhou    = @()

# Temporarios de execucoes que foram interrompidas a forca (o bloco finally nao
# roda quando o processo e morto). Sao inuteis e so ocupam ~40 MB cada.
Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'indice.tmp.*.csv' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $tmp } |
    ForEach-Object {
        Write-Host ("  Removendo temporario abandonado: {0}" -f $_.Name) -ForegroundColor DarkGray
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
    }

try {
    # A saida vai direto para o CSV, sem acumular ~165 mil objetos na memoria.
    & {
        foreach ($p in $pastas) {
            if (Test-Path -LiteralPath $p) {
                Write-Host ("  Lendo {0} ..." -f $p) -ForegroundColor Yellow
                Percorrer $p $ignorarPastas | ForEach-Object {
                    $script:total++
                    if ($script:total % 250 -eq 0) {
                        Write-Host ("`r    {0} arquivos lidos..." -f $script:total) -NoNewline -ForegroundColor Green
                    }
                    [PSCustomObject]@{
                        Nome       = $_.Name
                        Ext        = $_.Extension.TrimStart('.').ToLower()
                        Pasta      = $_.DirectoryName
                        Caminho    = $_.FullName
                        Modificado = $_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
                        MB         = [math]::Round($_.Length / 1MB, 2)
                    }
                }
                Write-Host ("`r    {0} arquivos lidos ate aqui.        " -f $script:total) -ForegroundColor Green
            } else {
                $script:falhou += $p
                Write-Warning ("Pasta nao acessivel agora: {0}" -f $p)
            }
        }
    } | Export-Csv -LiteralPath $tmp -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

    Write-Host "  Salvando catalogo..." -ForegroundColor DarkGray

    # --- Protecao: nunca trocar um catalogo bom por um incompleto ---------------
    # Se a rede cair no meio da varredura, o Get-ChildItem simplesmente devolve
    # menos arquivos, sem erro. Substituir o indice nesse caso deixaria a busca
    # "sem achar" arquivos que existem -- pior do que um indice de ontem.
    $motivo = $null
    if ($falhou.Count -gt 0) {
        $motivo = "estas pastas nao responderam: {0}" -f ($falhou -join ', ')
    }
    elseif ($total -eq 0) {
        $motivo = "a varredura nao encontrou nenhum arquivo"
    }
    elseif ($anterior -gt 0 -and $total -lt ($anterior * 0.5)) {
        $motivo = "so {0} arquivos contra {1} do catalogo atual (menos da metade)" -f $total, $anterior
    }

    if ($motivo -and $anterior -gt 0) {
        Move-Item -LiteralPath $tmp -Destination $parcial -Force
        Write-Host ""
        Write-Warning "Catalogo ANTIGO mantido: $motivo."
        Write-Warning "O resultado desta varredura ficou em 'indice.parcial.csv' para conferencia."
        Write-Warning "Rode de novo com a rede estavel; nada foi perdido."
        return
    }

    if (Test-Path -LiteralPath $destino) {
        Copy-Item -LiteralPath $destino -Destination $backup -Force
    }
    Move-Item -LiteralPath $tmp -Destination $destino -Force -ErrorAction Stop
}
finally {
    # Nao deixa lixo para tras se algo estourar no meio do caminho.
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
}

$dur = [int]((Get-Date) - $inicio).TotalSeconds
Write-Host ""
Write-Host ("  Pronto! {0} arquivos catalogados em {1}s." -f $total, $dur) -ForegroundColor Green
if ($anterior -gt 0) {
    $delta = $total - $anterior
    $sinal = if ($delta -ge 0) { '+' } else { '' }
    Write-Host ("  Catalogo anterior tinha {0} ({1}{2})." -f $anterior, $sinal, $delta) -ForegroundColor DarkGray
}
Write-Host ("  Indice salvo em: {0}" -f $destino) -ForegroundColor Green
Write-Host ""
