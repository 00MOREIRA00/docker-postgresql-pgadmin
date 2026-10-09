# 01 — Flyway no compose

Primeira etapa da v0.3.0: colocar o Flyway para rodar junto com o Postgres, aplicando as migrations da pasta `migrations/`.

Itens da [checklist](../checklist.md) cobertos aqui:

- Adicionar o serviço `flyway` ao compose, com versão fixa e `depends_on: service_healthy`
- Criar a pasta `migrations/` e montá-la no container do Flyway
- Passar as credenciais do `.env` para o Flyway
- Testar que `docker compose up` aplica as migrations e o Flyway encerra com código 0

---

## 1. Criar a pasta `migrations/`

Criar a pasta `migrations/` na raiz do projeto, ao lado de `initdb/`. Por enquanto ela fica vazia; o `V1__schema_inicial.sql` vem na próxima etapa.

> O Git não versiona pasta vazia. Para commitar antes do V1, coloque um arquivo `.gitkeep` vazio dentro dela.

**Diferença entre `initdb/` e `migrations/`** (decisão D2 em [decisoes.md](../decisoes.md)):

| Pasta | Quem executa | Quando | Uso |
| --- | --- | --- | --- |
| `initdb/` | Entrypoint da imagem do Postgres | Só na primeira subida (volume vazio) | Extensões e configuração inicial |
| `migrations/` | Flyway | Em toda subida, aplicando só o que ainda não rodou | Schema da aplicação e sua evolução |

---

## 2. Adicionar o serviço `flyway` ao `docker-compose.yml`

Dentro de `services:`, depois do `postgres`:

```yaml
  flyway:
    image: flyway/flyway:11.20.3
    container_name: pauta-flyway
    environment:
      FLYWAY_URL: jdbc:postgresql://postgres:5432/${POSTGRES_DB:-pauta}
      FLYWAY_USER: ${POSTGRES_USER:-postgres}
      FLYWAY_PASSWORD: ${POSTGRES_PASSWORD:?defina POSTGRES_PASSWORD no arquivo .env}
      FLYWAY_LOCATIONS: filesystem:/flyway/sql
    command: migrate
    volumes:
      - ./migrations:/flyway/sql:ro
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - pauta-net
```

### O que cada parte faz

| Trecho | O que faz |
| --- | --- |
| `image: flyway/flyway:11.20.3` | Imagem oficial do Flyway, com a versão exata fixada (decisão D5) |
| `FLYWAY_URL` | Conexão no formato JDBC (o Flyway é feito em Java): `jdbc:postgresql://HOST:PORTA/BANCO`. O host é `postgres`, o nome do **serviço**, e a porta é a **interna** do container (`5432`), não a `POSTGRES_PORT` do Windows |
| `FLYWAY_USER` / `FLYWAY_PASSWORD` | Usuário e senha do banco, lidos do `.env` |
| `FLYWAY_LOCATIONS` | Pasta onde o Flyway procura os arquivos `V*.sql`. Precisa ser igual ao lado direito do volume |
| `command: migrate` | Aplica as migrations pendentes e **encerra**. Esse container não fica rodando |
| `./migrations:/flyway/sql:ro` | Bind mount da pasta do projeto, somente leitura (mesmo padrão do `./initdb`) |
| `depends_on: service_healthy` | Só roda depois que o healthcheck do Postgres passar, ou seja, com o banco aceitando conexões |
| `networks: pauta-net` | Mesma rede do Postgres, o que permite usar o nome `postgres` como host |

### `${...}` aqui e `$${...}` no healthcheck

- **`${POSTGRES_DB}`** (um `$`): quem substitui é o **Compose**, lendo o `.env` antes de subir os containers.
- **`$${POSTGRES_USER}`** (dois `$`, no healthcheck do Postgres): o `$$` escapa a substituição do Compose, e a variável é lida **dentro do container**.

---

## 3. Credenciais: nada novo no `.env`

O Flyway conecta no **mesmo banco e com o mesmo usuário** do Postgres, então reaproveita as variáveis que já existem:

| Variável do Flyway | Vem de |
| --- | --- |
| `FLYWAY_URL` (nome do banco) | `POSTGRES_DB` |
| `FLYWAY_USER` | `POSTGRES_USER` |
| `FLYWAY_PASSWORD` | `POSTGRES_PASSWORD` |

**Por que não criar `FLYWAY_USER` e `FLYWAY_PASSWORD` no `.env`:**

- A senha ficaria duplicada. Ao trocar a senha do Postgres e esquecer a do Flyway, as migrations param de rodar.
- Uma variável no `.env` **não chega sozinha ao container**. O `.env` só é lido pelo Compose para substituir os `${...}` do `docker-compose.yml`; o que entra no container é o que está em `environment:`.

> Faria sentido ter credenciais próprias se o Flyway usasse um usuário dedicado às migrations, separado do superusuário.

---

## 4. Testar

```bash
docker compose up -d
docker compose ps -a
docker compose logs flyway
```

O `-a` é necessário porque o Flyway encerra depois de rodar, e o `docker compose ps` sem ele só mostra containers em execução.

**Resultado esperado:** `pauta-flyway` com status `Exited (0)`.

```
NAME             IMAGE              STATUS
pauta-flyway     flyway/flyway:11   Exited (0)
pauta-pgadmin    dpage/pgadmin4:9   Up
pauta-postgres   postgres:18        Up (healthy)
```

Log do Flyway com a pasta `migrations/` ainda vazia:

```
Flyway OSS Edition 11.20.3 by Redgate
Database: jdbc:postgresql://postgres:5432/pauta (PostgreSQL 18.6)
Schema history table "public"."flyway_schema_history" does not exist yet
Successfully validated 0 migrations
WARNING: No migrations found. Are your locations set up correctly?
Creating Schema History table "public"."flyway_schema_history" ...
Current version of schema "public": << Empty Schema >>
Schema "public" is up to date. No migration necessary.
```

Na primeira execução o Flyway cria a tabela **`flyway_schema_history`** no banco `pauta`. É nela que ele registra cada migration aplicada, para não rodar a mesma duas vezes. O `WARNING` é esperado enquanto não houver migrations.

---

## Problemas encontrados

### `(root) Additional property kearname is not allowed`

A linha 1 do compose estava `kearname: pauta-digital` em vez de `name: pauta-digital`.

Antes de qualquer comando (`up`, `down`, `ps`...), o Compose valida o arquivo contra as chaves permitidas. `(root)` indica que o problema está no nível raiz. Por isso até o `docker compose down` falhava.

### `services.flyway Additional property envirament is not allowed`

Mesmo tipo de erro, agora dentro do serviço `flyway`: `envirament` em vez de `environment`.

Outros erros de digitação no bloco, que **não** são pegos pela validação:

| Errado | Certo | O que aconteceria |
| --- | --- | --- |
| `flayway/flyway:11` | `flyway/flyway:11` | Erro só no `up`, ao tentar baixar uma imagem que não existe |
| `FLAYWAY_LOCATIONS` | `FLYWAY_LOCATIONS` | **Nenhum erro**: o Flyway ignora a variável e procura as migrations no lugar padrão |

Também foi preciso corrigir a indentação: o bloco estava com 4 espaços antes de `flyway:`, o que o colocaria dentro do `pgadmin`. Os serviços ficam com 2 espaços, e as propriedades deles com 4.

> Para validar o arquivo sem subir nada: `docker compose config -q`. Sem saída significa arquivo válido.

### `Found non-empty schema(s) "public" but no schema history table`

O Flyway encerrou com `Exited (1)`:

```
ERROR: Found non-empty schema(s) "public" but no schema history table.
       Use baseline() or set baselineOnMigrate to true to initialize the schema history table.
```

**Causa:** na primeira execução, antes de criar a `flyway_schema_history`, o Flyway confere se o schema está vazio. O `public` tinha uma tabela `teste`, criada manualmente no DBeaver. Por segurança, o Flyway não assume o controle de um schema que já tem objetos de origem desconhecida.

**Solução:** recriar o banco do zero, já que a tabela era só de teste:

```bash
docker compose down -v
docker compose up -d
```

> O `-v` apaga os volumes `pgdata` **e** `pgadmin-data`.

A extensão `pg_stat_statements`, criada pelo `initdb/` no `public`, não impediu o Flyway de rodar.

**Por que não usar `baselineOnMigrate`:** é a opção para bancos que já existiam antes do Flyway, com dados reais. Aqui ela só esconderia o problema.

---

## Próxima etapa

A primeira migration (`V1__schema_inicial.sql`), a convenção de nomes do Flyway e a fixação da versão da imagem estão em [02 — Primeira migration (V1)](02%20-%20migration.md).
