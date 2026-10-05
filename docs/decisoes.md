# Decisões do projeto

Registro curto das escolhas de arquitetura e do motivo de cada uma, no formato de ADR (*Architecture Decision Record*) simplificado.

---

## D1 — Usar um caso de negócio fictício

**Contexto:** um compose que só sobe Postgres e pgAdmin mostra conhecimento de Docker, não de banco de dados.

**Decisão:** construir o repositório em torno de uma empresa fictícia (Pauta Digital), com regras de negócio e perguntas a responder.

**Consequência:** cada recurso do Postgres aparece resolvendo um problema concreto, em vez de ser um exemplo solto.

---

## D2 — Migrations com Flyway

**Contexto:** scripts em `/docker-entrypoint-initdb.d` rodam **só na primeira subida**, com volume vazio. Eles não versionam a evolução do schema.

**Decisão:** usar o **Flyway** como serviço do compose. Ele aplica `migrations/V*.sql` em ordem, registra o histórico na tabela `flyway_schema_history` e encerra.

**Alternativas consideradas:**
- *dbmate*: mais leve, mas menos conhecido.
- *Alembic*: acoplaria as migrations ao Python.
- *Só `initdb`*: não mostra evolução de schema.

**Consequência:** o histórico de migrations conta a história do banco. `initdb/` fica restrito ao que precisa existir antes de tudo (extensões, configuração).

---

## D3 — Script Python em vez de backend

**Contexto:** uma API traria rotas, autenticação, validação e testes. Seria muita superfície fora do foco, que é o banco.

**Decisão:** um script Python de linha de comando, com três comandos: `seed`, `simular` e `relatorio`. Ele roda em container próprio sob o profile `tools`, então ninguém precisa instalar Python na máquina.

**Consequência:** o Python serve ao banco (gera dados, exercita triggers, consome consultas) sem roubar o protagonismo. Se um dia fizer sentido ter uma API, ela pode ir para outro repositório e usar este banco.

---

## D4 — Seed em Python; `generate_series` como demonstração

**Contexto:** dados realistas (nomes, e-mails, distribuição de cancelamentos ao longo do tempo, sazonalidade) são trabalhosos em SQL puro.

**Decisão:** o seed principal fica no Python, com Faker (`pt_BR`) e `psycopg` usando `COPY` para carga rápida. O `generate_series` aparece em `queries/` como técnica para gerar massa de teste.

**Consequência:** os dados têm comportamento plausível, então as análises de churn e coorte mostram padrões, não ruído. O SQL de geração continua representado.

---

## D5 — Versões fixas das imagens

**Contexto:** `postgres` sem tag passa a apontar para uma versão maior nova sem aviso. O Postgres 18, por exemplo, mudou o diretório de dados (`PGDATA`).

**Decisão:** fixar `postgres:18`, a versão do pgAdmin e a do Flyway. Usar volumes nomeados, nunca caminhos absolutos da máquina.

**Consequência:** o projeto se comporta igual em qualquer máquina e em qualquer data. Atualizar a versão vira uma decisão explícita.

---

## D6 — Dinheiro em centavos

**Decisão:** valores monetários em `integer` (centavos). A formatação acontece só na apresentação.

**Motivo:** `float` gera erros de arredondamento. `numeric` funcionaria, mas `integer` deixa as regras de cálculo explícitas e é mais rápido.

---

## D7 — Credenciais em `.env`

**Decisão:** senhas e portas ficam em `.env`, que está no `.gitignore`. O repositório versiona só o `.env.example`.

**Consequência:** o compose não expõe segredos e o padrão é o mesmo usado em projetos reais.
