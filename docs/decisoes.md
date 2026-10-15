# Decisões do projeto

Registro curto das escolhas de arquitetura e do motivo de cada uma, no formato de ADR (*Architecture Decision Record*) simplificado.

A numeração é estável: uma decisão nunca muda de número, para não quebrar as referências nos documentos de [tutoriais/](tutoriais/). D3 e D4 foram descartadas quando o escopo do projeto foi reduzido.

---

## D1 — Usar um caso de negócio fictício

**Contexto:** um compose que só sobe Postgres e pgAdmin mostra conhecimento de Docker, mas não dá motivo para usar os recursos do banco.

**Decisão:** dar ao banco o contexto de uma empresa fictícia, a [Pauta Digital](caso-de-negocio.md), com regras de negócio simples.

**Consequência:** as constraints, o índice parcial e as migrations representam regras concretas ("um e-mail por assinante", "uma assinatura em andamento"), em vez de exemplos soltos. O caso é só contexto: o foco continua sendo Docker, PostgreSQL e Flyway.

---

## D2 — Migrations com Flyway

**Contexto:** scripts em `/docker-entrypoint-initdb.d` rodam **só na primeira subida**, com volume vazio. Eles não versionam a evolução do schema.

**Decisão:** usar o **Flyway** como serviço do compose. Ele aplica `migrations/V*.sql` em ordem, registra o histórico na tabela `flyway_schema_history` e encerra.

**Alternativas consideradas:**
- *dbmate*: mais leve, mas menos conhecido.
- *Alembic*: exigiria Python no projeto só para as migrations.
- *Só `initdb`*: não mostra evolução de schema.

**Consequência:** o histórico de migrations conta a história do banco, e a V2 pôde ser aplicada sobre um banco com dados, sem perdê-los. `initdb/` fica restrito ao que precisa existir antes de tudo (a extensão `pg_stat_statements`).

---

## D5 — Versões fixas das imagens

**Contexto:** `postgres` sem tag passa a apontar para uma versão maior nova sem aviso. O Postgres 18, por exemplo, mudou o diretório de dados (`PGDATA`).

**Decisão:** fixar `postgres:18`, `dpage/pgadmin4:9` e `flyway/flyway:11.20.3`. Usar volumes nomeados, nunca caminhos absolutos da máquina.

**Consequência:** as tags evitam mudanças automáticas de versão maior. `postgres:18` e `dpage/pgadmin4:9` ainda recebem atualizações dentro dessas versões, e tags podem ser republicadas. Para reproduzir exatamente os mesmos artefatos, seria necessário fixar as imagens por digest (`sha256`). O projeto mantém tags para acompanhar correções dessas versões.

---

## D6 — Dinheiro em centavos

**Decisão:** valores monetários em `integer` (centavos): `preco_centavos` nos planos e `valor` dos cupons do tipo `valor_fixo`. A formatação acontece só na apresentação.

**Motivo:** `float` gera erros de arredondamento. `numeric` funcionaria, mas `integer` deixa as regras de cálculo explícitas e é mais rápido.

---

## D7 — Credenciais em `.env`

**Decisão:** senhas e portas ficam em `.env`, que está no `.gitignore`. O repositório versiona só o `.env.example`, sem senhas. O compose usa `${VAR:?mensagem}` e recusa subir se a senha não estiver definida.

**Consequência:** o compose não expõe segredos, e o padrão é o mesmo usado em projetos reais.

---

## D8 — Dados de exemplo em SQL, fora das migrations

**Contexto:** para aplicar a V2 sobre um banco com dados, era preciso uma massa de teste.

**Decisão:** gerar os dados com `generate_series` num script SQL (`scripts/dados_exemplo.sql`), executado sob demanda. Dados fixos do negócio (planos, publicações e cupons) ficam nas migrations; dados de teste, não.

**Consequência:** um banco novo sobe com o catálogo, mas sem assinantes falsos. O script começa com `TRUNCATE` e pode ser executado quantas vezes for preciso, sem dependência de outra linguagem. A limpeza e a carga ficam em uma única transação (`BEGIN`/`COMMIT`); um erro desfaz as mudanças ao encerrar a conexão.

---

## D9 — Backup lógico com `pg_dump` no formato custom

**Contexto:** o projeto precisava mostrar que o banco pode ser salvo e recuperado.

**Decisão:** backup com `pg_dump -Fc` executado **dentro** do container, para a versão da ferramenta sempre bater com a do servidor. O restore é testado num banco separado (`pauta_restore`) e conferido por contagem e por uma impressão digital (`md5`) do conteúdo. Os dumps ficam em `backups/`, fora do git.

**Consequência:** o backup é validado, não só gerado. O histórico do Flyway viaja junto, então o banco restaurado continua da mesma versão de migration.
