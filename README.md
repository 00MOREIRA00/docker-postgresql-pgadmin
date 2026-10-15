# Pauta Digital — PostgreSQL com Docker e Flyway

> Laboratório de PostgreSQL com Docker baseado em um caso de negócio fictício: a **Pauta Digital**, uma plataforma de revistas e newsletters por assinatura.

O foco do projeto é a infraestrutura do banco: subir o PostgreSQL com **Docker Compose**, versionar o schema com **migrations do Flyway** e **evoluir um banco que já tem dados** sem perdê-los.

---

## O caso

A Pauta Digital vende acesso a um catálogo de publicações digitais (revistas e newsletters) em planos mensais, anuais e familiares. O banco guarda planos, publicações, assinantes e assinaturas, com as regras de negócio garantidas pelo próprio PostgreSQL: e-mail único, uma assinatura em andamento por assinante, cancelamento sempre com data e motivo.

Detalhes do negócio: [docs/caso-de-negocio.md](docs/caso-de-negocio.md).

## Arquitetura

```mermaid
flowchart LR
    subgraph compose[docker compose]
        PG[(PostgreSQL 18)]
        FW[Flyway<br/>migrations] -->|aplica V1..Vn| PG
        PGA[pgAdmin 4] -->|conexão pré-configurada| PG
    end
    DEV((você)) -->|localhost:16543| PGA
    DEV -->|localhost:5432| PG
```

| Serviço    | Papel                                                              | Fica rodando |
|------------|--------------------------------------------------------------------|--------------|
| `postgres` | Banco de dados, com healthcheck e `pg_stat_statements` habilitado  | Sim |
| `flyway`   | Aplica as migrations pendentes em `migrations/` e encerra          | Não (`Exited (0)`) |
| `pgadmin`  | Interface web, com o servidor já cadastrado via `servers.json`     | Sim |

O Flyway e o pgAdmin só sobem depois que o healthcheck do Postgres passa (`depends_on: service_healthy`).

Por que essas escolhas: [docs/decisoes.md](docs/decisoes.md).

## Estrutura do repositório

```
.
├── docker-compose.yml
├── .env.example              # variáveis (senhas, portas) — copie para .env
├── migrations/               # evolução do schema, versionada (Flyway)
│   ├── V1__schema_inicial.sql
│   └── V2__cupons.sql
├── initdb/                   # roda só na 1ª subida: extensões do servidor
│   └── 01_extensoes.sql
├── scripts/
│   └── dados_exemplo.sql     # massa de teste com generate_series (não é migration)
├── backups/                  # dumps do pg_dump — fora do git (.gitignore)
├── pgadmin/
│   └── servers.json          # conexão pré-cadastrada no pgAdmin
└── docs/
    ├── caso-de-negocio.md
    ├── modelo-de-dados.md
    ├── decisoes.md
    ├── checklist.md          # plano de trabalho por versão
    └── criando/              # passo a passo de cada etapa, com os problemas encontrados
```

## Como rodar

**Pré-requisitos:** Docker com o plugin Compose v2 (`docker compose`).

```bash
# 1. Clonar e configurar
git clone https://github.com/00MOREIRA00/docker-postgresql-pgadmin.git
cd docker-postgresql-pgadmin
cp .env.example .env          # defina POSTGRES_PASSWORD e PGADMIN_PASSWORD

# 2. Subir tudo
docker compose up -d

# 3. Conferir
docker compose ps -a
```

O esperado:

| Container        | Status          |
|------------------|-----------------|
| `pauta-postgres` | `Up (healthy)`  |
| `pauta-flyway`   | `Exited (0)`    |
| `pauta-pgadmin`  | `Up`            |

**Conferir se as migrations rodaram**

```bash
docker compose logs flyway
```

Procure `Successfully applied N migration` na primeira subida, ou `Schema "public" is up to date` quando não há nada novo. O `Exited (0)` sozinho não garante que uma migration foi aplicada: um arquivo com nome fora do padrão (`v1__...` em vez de `V1__...`) é ignorado sem erro.

**Acessos**

| O quê    | Onde                            | Credenciais         |
|----------|---------------------------------|---------------------|
| pgAdmin  | http://localhost:16543          | definidas no `.env` |
| Postgres | `localhost:5432`, banco `pauta` | definidas no `.env` |

O pgAdmin já abre com o servidor **Pauta Digital (local)** cadastrado (grupo *Laboratório*). No primeiro acesso, ele pede a senha do banco (`POSTGRES_PASSWORD`). Ele leva cerca de um minuto para ficar disponível.

Dentro da rede do compose, o host do banco é `postgres`.

**Teste rápido pelo terminal**

```bash
docker compose exec postgres psql -U postgres -d pauta -c "SELECT codigo, nome, preco_centavos FROM planos;"
```

**Encerrar**

```bash
docker compose down        # para os containers, mantém os dados
docker compose down -v     # para e apaga os volumes (recomeça do zero)
```

## Migrations

| Versão | Arquivo | Conteúdo |
|--------|---------|----------|
| V1 | `V1__schema_inicial.sql` | Extensão `citext`, ENUMs, 6 tabelas, constraints, índice único parcial e carga dos planos e publicações |
| V2 | `V2__cupons.sql` | Tabela `cupons` e coluna `cupom_id` em `assinaturas`, aplicada num banco com dados |

Regra de ouro: **migration aplicada não se edita**. O Flyway guarda um checksum de cada arquivo em `flyway_schema_history` e recusa alterações; correções entram como uma nova versão.

Modelo completo: [docs/modelo-de-dados.md](docs/modelo-de-dados.md).

## Dados de exemplo

O script `scripts/dados_exemplo.sql` gera 500 assinantes e suas assinaturas com `generate_series`. Não é uma migration: roda sob demanda e começa limpando as tabelas, então pode ser executado quantas vezes for preciso.

A limpeza também remove o histórico das assinaturas (`CASCADE`). Execute somente no banco de laboratório. O `TRUNCATE` e os inserts ficam na mesma transação: se a carga falhar, a limpeza é desfeita ao encerrar a conexão.

```bash
docker compose cp scripts/dados_exemplo.sql postgres:/tmp/dados_exemplo.sql
docker compose exec postgres psql -U postgres -d pauta -v ON_ERROR_STOP=1 -f /tmp/dados_exemplo.sql
```

Os status e as datas seguem as regras do caso: trials só na última semana, ativas com o ciclo vigente, inadimplentes com o ciclo vencido e o plano anual com período de 365 dias.

## Backup e restore

Os exemplos abaixo usam Bash (Linux, macOS ou WSL) e as credenciais padrão de usuário/banco (`postgres`/`pauta`). Se você alterou esses nomes no `.env`, ajuste os comandos.

**Backup** com `pg_dump` no formato custom (binário e compactado):

```bash
mkdir -p backups
docker compose exec -T postgres pg_dump -U postgres -d pauta -Fc > backups/pauta_$(date +%Y%m%d_%H%M).dump
```

O `-T` é obrigatório: sem ele, o terminal interativo do `exec` pode corromper o arquivo binário. A pasta `backups/` está no `.gitignore`, porque um dump contém todos os dados do banco.

**Restore** num banco separado, para não arriscar o original:

```bash
ARQ=$(ls -t backups/*.dump | head -1)
docker compose exec postgres createdb -U postgres pauta_restore
docker compose exec -T postgres pg_restore -U postgres -d pauta_restore --no-owner --exit-on-error < "$ARQ"
```

**Conferir os dados restaurados.** Além das contagens de assinantes, assinaturas e cupons, a consulta calcula uma impressão digital (`md5`) do conteúdo das assinaturas:

```bash
Q="SELECT (SELECT count(*) FROM assinantes) AS assinantes,
          (SELECT count(*) FROM assinaturas) AS assinaturas,
          (SELECT count(*) FROM cupons) AS cupons,
          (SELECT md5(string_agg(a::text, ',' ORDER BY a.id)) FROM assinaturas a) AS impressao_digital;"

for db in pauta pauta_restore; do
  docker compose exec postgres psql -U postgres -d $db -c "$Q"
done
```

As duas saídas devem ser idênticas. Esta é uma conferência parcial: valida essas contagens e o conteúdo das assinaturas, mas não compara o conteúdo das demais tabelas, as sequências ou toda a estrutura. Execute sem escritas concorrentes e com as mesmas configurações de sessão (como fuso horário), pois a representação textual usada no hash pode variar. O backup também leva a `flyway_schema_history`, então o banco restaurado sabe em qual migration está:

```bash
docker compose run --rm -e FLYWAY_URL=jdbc:postgresql://postgres:5432/pauta_restore flyway info
```

**Limpar** o banco de teste:

```bash
docker compose exec postgres dropdb -U postgres pauta_restore
```

### Windows PowerShell

Para preservar os bytes do dump em versões como o Windows PowerShell 5.1, gere o arquivo dentro do container e use `docker compose cp`. Execute as etapas em sequência e só continue quando cada comando terminar sem erro.

```powershell
New-Item -ItemType Directory -Force backups | Out-Null
$arquivo = 'pauta_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.dump'
docker compose exec -T postgres pg_dump -U postgres -d pauta -Fc -f /tmp/pauta_backup.dump
if ($LASTEXITCODE -ne 0) { throw 'Falha ao gerar o backup' }
docker compose cp postgres:/tmp/pauta_backup.dump "backups/$arquivo"
if ($LASTEXITCODE -ne 0) { throw 'Falha ao copiar o backup' }

# Restore em banco separado; ele ainda não deve existir.
docker compose cp "backups/$arquivo" postgres:/tmp/pauta_restore.dump
if ($LASTEXITCODE -ne 0) { throw 'Falha ao copiar o dump para restore' }
docker compose exec -T postgres createdb -U postgres pauta_restore
if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar pauta_restore' }
docker compose exec -T postgres pg_restore -U postgres -d pauta_restore --no-owner --exit-on-error /tmp/pauta_restore.dump
if ($LASTEXITCODE -ne 0) { throw 'Falha no restore' }

$consulta = @'
SELECT (SELECT count(*) FROM assinantes) AS assinantes,
       (SELECT count(*) FROM assinaturas) AS assinaturas,
       (SELECT count(*) FROM cupons) AS cupons,
       (SELECT md5(string_agg(a::text, ',' ORDER BY a.id)) FROM assinaturas a) AS impressao_digital;
'@
foreach ($banco in @('pauta', 'pauta_restore')) {
    docker compose exec -T postgres psql -U postgres -d $banco -v ON_ERROR_STOP=1 -c $consulta
    if ($LASTEXITCODE -ne 0) { throw "Falha ao conferir $banco" }
}
docker compose run --rm -e FLYWAY_URL=jdbc:postgresql://postgres:5432/pauta_restore flyway info
```

Compare as duas saídas, com os mesmos limites de conferência descritos acima. Depois, remova somente o banco de teste com `docker compose exec -T postgres dropdb -U postgres pauta_restore`. O dump em `backups/` permanece salvo.

## O que o projeto demonstra

| Tema | Onde ver |
|------|----------|
| Compose com healthcheck, `depends_on: service_healthy`, volumes e rede | `docker-compose.yml` |
| Credenciais fora do código | `.env.example` |
| Scripts de inicialização do Postgres | `initdb/` |
| Migrations versionadas com Flyway | `migrations/` |
| Modelagem relacional: PK/FK, `CHECK`, `ENUM`, `citext` | `migrations/V1` |
| Índice único parcial (uma assinatura em andamento por assinante) | `migrations/V1` |
| Evolução de schema sem perder dados | `migrations/V2` |
| Massa de teste com `generate_series` | `scripts/dados_exemplo.sql` |
| Backup e restore com `pg_dump` / `pg_restore`, conferidos por impressão digital | [Backup e restore](#backup-e-restore) |

O passo a passo de cada etapa, com os erros que apareceram e como foram resolvidos, está em [docs/criando/](docs/criando/).

## Roadmap

- [x] Corrigir a base do compose (ver [melhorias.md](melhorias.md))
- [x] `.env.example`, healthcheck, `servers.json` do pgAdmin e `pg_stat_statements`
- [x] Serviço Flyway + `V1` schema inicial
- [x] Dados de exemplo em SQL e `V2` cupons, aplicada sem apagar o banco
- [x] Backup e restore
- [x] README final

Detalhes de cada versão: [docs/checklist.md](docs/checklist.md).

## Aviso

Projeto de estudo. As credenciais do `.env.example` são apenas para uso local — não use esta configuração em produção.
