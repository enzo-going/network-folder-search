# Network Folder Search

[![lint](https://github.com/enzo-going/network-folder-search/actions/workflows/lint.yml/badge.svg)](https://github.com/enzo-going/network-folder-search/actions/workflows/lint.yml)

Ferramenta local em PowerShell para **buscar arquivos por nome** em uma ou mais
pastas (locais ou compartilhamentos de rede). Ela varre as pastas configuradas
**apenas para leitura**, gera um catálogo local (`indice.csv`) e permite buscas
instantâneas sem varrer a rede a cada consulta.

> A ferramenta **não abre, move, renomeia nem altera** nenhum arquivo das pastas
> catalogadas. O catálogo é somente um índice de nomes/caminhos.

## Requisitos

- Windows com PowerShell 5.1 ou superior
- Acesso de leitura às pastas que serão catalogadas

## Configuração

As pastas a catalogar são definidas em um arquivo `config.json` local, que
**não é versionado**. Copie o exemplo e ajuste os caminhos:

```powershell
Copy-Item config.example.json config.json
```

`config.example.json`:

```json
{
  "searchRoots": [
    "\\\\fileserver.example.local\\Shared",
    "C:\\Example\\Documents"
  ],
  "indexFile": "indice.csv"
}
```

- `searchRoots`: uma ou mais pastas (caminhos UNC `\\servidor\share` ou locais `C:\...`).
- `indexFile`: nome do arquivo de catálogo gerado (padrão `indice.csv`).

## Uso

### 1. Gerar/atualizar o catálogo

```powershell
.\Atualizar-Indice.ps1
```

Ou dê duplo-clique em `Atualizar-Indice.bat`. Na primeira execução pode levar
alguns minutos, dependendo do volume de arquivos.

### 2. Buscar

```powershell
.\Buscar.ps1
```

Ou duplo-clique em `Buscar.bat`. Digite parte do nome do arquivo:

- Várias palavras = todas precisam aparecer no nome.
- Acentos e maiúsculas são ignorados.
- Prefixo `excel` restringe a planilhas (ex.: `excel fechamento`).
- Comandos: `!r` atualiza o catálogo, `!s` sai.

Se `Out-GridView` estiver disponível, os resultados abrem em uma janela
selecionável; ao selecionar um item, a pasta correspondente é aberta no
Explorer.

## Limitações

- O catálogo é uma "foto" do momento da varredura; rode `Atualizar-Indice.ps1`
  para refletir mudanças.
- A busca é por **nome de arquivo**, não pelo conteúdo.
- Pontos de junção/links são ignorados para evitar loops.

## Segurança / o que NÃO versionar

Estes itens ficam de fora do repositório (via `.gitignore`) por conterem dados
reais do ambiente:

- `config.json` (caminhos reais das suas pastas)
- `indice.csv` e qualquer `.csv` gerado (nomes e caminhos reais de arquivos)
- logs e arquivos temporários

Somente o código (`.ps1`/`.bat`), o `config.example.json` e este README são
versionados.
