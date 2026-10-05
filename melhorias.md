# Melhorias — docker-postgresql-pgadmin

Revisão do estado atual do repositório (`docker-compose.yml` + `README.md`) e próximos passos para transformá-lo em um caso prático que demonstre conhecimento em PostgreSQL.

## 1. Problemas que quebram ou atrapalham

- [x] **Host errado no README** — o README manda conectar no host `postgres`, mas o serviço se chama `teste-postgres-compose`. Seguindo o passo a passo, a conexão pelo pgAdmin falha. Renomear o serviço para `postgres` (ou corrigir o README).
- [x] **Volume com caminho absoluto da máquina local** — `/home/rneto/Desenvolvimento/Docker-Compose/PostgreSQL` não existe em outra máquina. Trocar por um volume nomeado (`pgdata:`).
- [x] **Imagem sem versão fixa** — `postgres` sem tag puxa a última versão (18), que mudou o diretório de dados (PGDATA). Montar em `/var/lib/postgresql/data` deixa de funcionar como antes. Fixar a versão (ex.: `postgres:17` ou `postgres:18`) e ajustar o caminho do volume. Idem para `dpage/pgadmin4:latest`.
- [x] **Senhas hardcoded no compose** — mover para um arquivo `.env` (no `.gitignore`) e versionar apenas um `.env.example`.

## 2. Ajustes menores

- [x] Remover `version: '3'` (obsoleto no Compose v2, gera warning).
- [x] Adicionar `healthcheck` com `pg_isready` e usar `depends_on: condition: service_healthy` no pgAdmin.
- [x] Persistir o pgAdmin com volume próprio e pré-configurar a conexão via `servers.json` (evita recadastrar o servidor a cada recriação).
- [x] README: corrigir a URL do `git clone` (ainda está `seu-usuario/...`) e trocar `docker-compose` por `docker compose`.
- [x] Remover espaços em branco no fim das linhas do compose.

## 3. O que falta para o objetivo (mostrar conhecimento)

Hoje o projeto sobe apenas um banco vazio. Proposta de estrutura com um caso completo:

```
initdb/
  01_schema.sql      -- tabelas, PK/FK, constraints, CHECK, ENUM
  02_seed.sql        -- dados gerados com generate_series (milhares de linhas)
  03_objects.sql     -- views, materialized view, functions, triggers (auditoria)
  04_security.sql    -- roles (leitura/escrita), row-level security
queries/
  analytics.sql      -- CTEs, window functions, agregações
  performance.sql    -- EXPLAIN ANALYZE antes/depois de índices
scripts/
  backup.sh / restore.sh  -- pg_dump / pg_restore
```

Montando `initdb/` em `/docker-entrypoint-initdb.d`, um `docker compose up` já entrega o banco populado.

### Caso sugerido: editora com assinaturas de revistas

Entidades: clientes, títulos, edições, assinaturas, pagamentos, cancelamentos.

Permite demonstrar:

- Churn e receita recorrente com window functions
- Trigger de auditoria em pagamentos
- Roles separadas para "financeiro" e "editorial" (com RLS)
- Índices e análise de plano de execução com `EXPLAIN ANALYZE`
- Backup e restore

### Extras

- [x] Ativar `pg_stat_statements` para monitorar queries lentas
- [ ] Pequena API (Python/FastAPI) em outro container conectando ao banco
