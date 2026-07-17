# ============================================================
#  Atualizar-Indice.ps1
#  Varre as pastas de rede (SOMENTE LEITURA) e salva um
#  catalogo local (indice.csv) para buscas instantaneas.
#  NAO abre, move, renomeia ou altera nenhum arquivo da rede.
# ============================================================

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

Write-Host ""
Write-Host "  Catalogando arquivos das pastas de rede (somente leitura)..." -ForegroundColor Cyan
Write-Host "  Pode levar alguns minutos na 1a vez. O contador abaixo mostra que esta funcionando." -ForegroundColor DarkGray
Write-Host ""

$inicio = Get-Date
$total  = 0

$dados = foreach ($p in $pastas) {
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
        Write-Warning ("Pasta nao acessivel agora: {0}" -f $p)
    }
}

Write-Host "  Salvando catalogo..." -ForegroundColor DarkGray
$dados | Export-Csv -LiteralPath $tmp -NoTypeInformation -Encoding UTF8
Move-Item -LiteralPath $tmp -Destination $destino -Force

$dur = [int]((Get-Date) - $inicio).TotalSeconds
Write-Host ""
Write-Host ("  Pronto! {0} arquivos catalogados em {1}s." -f $total, $dur) -ForegroundColor Green
Write-Host ("  Indice salvo em: {0}" -f $destino) -ForegroundColor Green
Write-Host ""
