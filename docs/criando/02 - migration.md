# 02 — Primeira migration (V1)

Com o Flyway rodando (ver [01 — Flyway no compose](01%20-%20inicial.md)), esta etapa fixa a versão da imagem e cria a primeira migration de verdade: a extensão `citext`, os tipos ENUM, as tabelas, as constraints, o índice único parcial e a carga dos dados fixos.

Itens da [checklist](../checklist.md) fechados aqui:

- Flyway: versão fixa da imagem
- Flyway: `docker compose up` aplica as migrations e encerra com código 0
- Migration V1: extensão `citext`
- Migration V1: tipos ENUM
- Migration V1: tabelas
- Migration V1: constraints (`CHECK` de UF, de cancelamento e de valores)
- Migration V1: índice único parcial
- Migration V1: carga dos 4 planos e das publicações

---

## 1. Fixar a versão do Flyway

**O que foi feito:** a imagem passou de `flyway/flyway:11` para `flyway/flyway:11.20.3`.

```yaml
  flyway:
    image: flyway/flyway:11.20.3
```

**Por quê:**

- `:11` fixa só a versão **maior**. Cada vez que a Redgate publica uma `11.x` nova, a tag passa a apontar para ela, e o projeto muda de comportamento sem ninguém ter alterado nada.
- `:11.20.3` é uma versão exata. O projeto se comporta igual em qualquer máquina e em qualquer data.
- É o que pede a decisão **D5** em [decisoes.md](../decisoes.md): fixar as versões do Postgres, do pgAdmin e do Flyway, e fazer de cada atualização uma escolha explícita.

O número `11.20.3` veio do próprio log do Flyway (`Flyway OSS Edition 11.20.3 by Redgate`), ou seja, é a versão que já estava sendo usada e testada.

> O log avisa `A more recent version of Flyway is available ... Flyway 13.10.0`. Pode ignorar: a versão fixa existe justamente para não atualizar sozinho. Ir da 11 para a 13 pula duas versões maiores e merece teste próprio.

---

## 2. Criar a migration `V1__schema_inicial.sql`

**O que foi feito:** criado o arquivo `migrations/V1__schema_inicial.sql`, por enquanto só com a extensão:

```sql
CREATE EXTENSION IF NOT EXISTS citext;
```

### Por que `citext`

`citext` (*case-insensitive text*) é um tipo de texto que **ignora maiúsculas e minúsculas nas comparações**. No [modelo de dados](../modelo-de-dados.md), ele é usado no `email` dos assinantes:

| Com `text` | Com `citext` |
| --- | --- |
| `'Joao@Email.com' = 'joao@email.com'` é **falso** | `'Joao@Email.com' = 'joao@email.com'` é **verdadeiro** |
| O `UNIQUE` aceita os dois e-mails: a mesma pessoa vira dois assinantes | O `UNIQUE` recusa o segundo: um e-mail, um assinante |

Assim a regra "e-mail único, sem diferenciar maiúsculas de minúsculas" fica garantida **pelo banco**, e não depende de a aplicação lembrar de usar `lower()`.

### Por que `IF NOT EXISTS`

Se a extensão já existir, o comando não faz nada em vez de dar erro. É o mesmo padrão do [initdb/01_extensoes.sql](../../initdb/01_extensoes.sql).

### Por que no V1, e não no `initdb/`

- O `pg_stat_statements` ficou no `initdb/` porque é **configuração do servidor**: precisa existir antes de tudo e não tem relação com o schema da aplicação.
- O `citext` é **parte do schema**: a tabela `assinantes` depende dele. Ele precisa estar no histórico de migrations, junto com as tabelas que o usam (decisão **D2**).

### O V1 vai crescer

O V1 é o schema inicial inteiro. Os próximos itens da checklist (ENUMs, tabelas, constraints, índice parcial, carga de planos e publicações) entram **neste mesmo arquivo**, abaixo da extensão.

---

## 3. A convenção de nomes do Flyway

O Flyway reconhece as migrations **pelo nome do arquivo**, não pelo conteúdo:

```
V1__schema_inicial.sql
│ │ │              │
│ │ │              └─ sufixo: .sql
│ │ └─ descrição (vira "schema inicial" no histórico)
│ └─ versão: 1, 2, 3... (ou 1.1, 2.0.1)
└─ prefixo: V maiúsculo
```

| Prefixo | Tipo | Quando roda |
| --- | --- | --- |
| `V` | *Versioned* | Uma vez só, em ordem de versão. É o usado no projeto |
| `R` | *Repeatable* | De novo sempre que o conteúdo do arquivo muda (útil para views e funções) |
| `U` | *Undo* | Desfaz uma versão (só na edição paga) |

Detalhes que derrubam a migration:

- O prefixo **diferencia maiúsculas de minúsculas**: `v1__...` não é reconhecido.
- O separador são **dois** underscores (`__`). Com um só, o arquivo também é ignorado.

### O problema que aconteceu: `v` minúsculo

O arquivo foi criado primeiro como `v1__schema_inicial.sql`. O Flyway terminou com `Exited (0)`, mas não aplicou nada. O motivo só aparecia no log:

```
1 SQL migrations were detected but not run because they did not follow the filename convention.
Set 'validateMigrationNaming' to true to fail fast and see a list of the invalid file names.
Successfully validated 0 migrations
WARNING: No migrations found. Are your locations set up correctly?
```

**Por que não deu erro:** por padrão, o Flyway só **avisa** sobre nomes fora do padrão. Sem nenhuma migration válida, não havia nada para aplicar, e isso conta como sucesso.

**Correção:** renomear para `V1__schema_inicial.sql`. Como o Windows não diferencia maiúsculas de minúsculas, renomear direto pode não funcionar; o seguro é passar por um nome intermediário:

```bash
mv migrations/v1__schema_inicial.sql migrations/tmp.sql
mv migrations/tmp.sql migrations/V1__schema_inicial.sql
```

> Com `FLYWAY_VALIDATE_MIGRATION_NAMING: "true"` no `environment:` do Flyway, um nome fora do padrão faz o Flyway **falhar** em vez de ignorar o arquivo em silêncio.

**Lição:** `Exited (0)` não garante que a migration rodou. Confira sempre o log.

---

## 4. Rodar e conferir

```bash
docker compose up flyway
```

Sem o `-d`, o log aparece direto no terminal, e o terminal volta sozinho quando o Flyway termina. Com `-d`, o log só aparece com `docker compose logs flyway`.

**Log esperado:**

```
Successfully validated 1 migration
Current version of schema "public": << Empty Schema >>
Migrating schema "public" to version "1 - schema inicial"
Successfully applied 1 migration to schema "public", now at version v1
pauta-flyway exited with code 0
```

**Conferir no banco `pauta`:**

```sql
SELECT installed_rank, version, description, script, success
FROM flyway_schema_history;

SELECT extname, extversion FROM pg_extension;
```

Resultado:

```
 installed_rank | version |  description   |         script         | success
----------------+---------+----------------+------------------------+---------
              1 | 1       | schema inicial | V1__schema_inicial.sql | t
```

O `citext` (versão 1.8) aparece em `pg_extension`, ao lado de `plpgsql` (padrão do Postgres) e `pg_stat_statements` (do `initdb/`).

### O que é a `flyway_schema_history`

É a tabela onde o Flyway registra cada migration aplicada: versão, descrição, arquivo, quem aplicou, quando, quanto tempo levou, se deu certo e um **checksum** do conteúdo. Na próxima execução, ele compara a pasta `migrations/` com essa tabela e aplica só o que falta.

---

## 5. Regra de ouro: migration aplicada não se edita

O Flyway guardou o checksum do `V1__schema_inicial.sql`. Se o arquivo for alterado depois disso, a próxima execução falha com:

```
Validate failed: Migration checksum mismatch for migration version 1
```

É a proteção principal do Flyway: garantir que todo banco que passou pela versão 1 tem exatamente o mesmo schema. Em um banco com dados reais, uma correção vira uma **nova** migration (`V2`, `V3`...), nunca uma edição do V1.

**Exceção enquanto o V1 está em construção:** o banco local ainda é descartável. Para acrescentar os ENUMs e as tabelas no V1, recrie o banco a cada alteração:

```bash
docker compose down -v
docker compose up -d
```

> O `-v` apaga os volumes `pgdata` e `pgadmin-data`: o banco volta vazio e o Flyway aplica o V1 completo de novo.

### O que o `-v` faz

`-v` é a abreviação de `--volumes`: além de remover containers e rede, o `down` apaga os volumes.

| Comando | Containers | Rede | Volumes (`pgdata`, `pgadmin-data`) |
| --- | --- | --- | --- |
| `docker compose down` | Remove | Remove | **Mantém** |
| `docker compose down -v` | Remove | Remove | **Apaga** |

Com o volume vazio, no próximo `up` tudo acontece como na primeira vez:

1. O Postgres cria o banco `pauta` (vindo do `POSTGRES_DB`).
2. Os scripts do `initdb/` rodam e recriam o `pg_stat_statements`.
3. O Flyway encontra um banco sem `flyway_schema_history` e aplica o V1 inteiro, já com o conteúdo novo.

> O `-v` **não tem como desfazer**. Só é seguro enquanto o banco é descartável, ou seja, enquanto tudo pode ser recriado a partir de `initdb/`, `migrations/` e `servers.json`. Quando houver dados que importam, faça backup antes ou pare de editar o V1 e crie migrations novas.

---

## 6. Tipos ENUM

**O que foi feito:** acrescentados ao `V1__schema_inicial.sql`, abaixo do `citext`, os quatro tipos enumerados da V1:

```sql
CREATE TYPE periodicidade AS ENUM ('mensal', 'anual');

CREATE TYPE tipo_publicacao AS ENUM ('revista', 'newsletter');

CREATE TYPE status_assinatura AS ENUM ('trial', 'ativa', 'inadimplente', 'cancelada');

CREATE TYPE motivo_cancelamento AS ENUM ('preco', 'conteudo', 'pouco_uso', 'inadimplencia', 'trial_nao_convertido', 'outro');
```

Os valores vêm da seção "Tipos enumerados" do [modelo de dados](../modelo-de-dados.md).

### Por que ENUM

Um ENUM é um tipo criado por você que só aceita uma **lista fixa de valores**. Se uma coluna `status` for do tipo `status_assinatura`, o banco recusa qualquer coisa fora da lista:

```sql
INSERT ... status = 'ativo'
-- ERRO: invalid input value for enum status_assinatura: "ativo"
```

Assim, a regra "uma assinatura só pode estar em `trial`, `ativa`, `inadimplente` ou `cancelada`" fica garantida **pelo banco**, e não depende de a aplicação acertar o texto. É a mesma ideia do `citext`.

### Por que só esses quatro

O modelo também tem `status_fatura`, `metodo_pagamento` (V2) e `tipo_desconto` (V3). Cada tipo entra na migration que cria as tabelas que o usam.

### Por que no início do arquivo

O Postgres executa o arquivo de cima para baixo. Uma tabela só pode usar um tipo que já exista, então a ordem do V1 é:

```
V1__schema_inicial.sql
├── 1. Extensão citext
├── 2. Tipos ENUM
├── 3. Tabelas (com as constraints)
├── 4. Índice único parcial
└── 5. Carga dos planos e publicações
```

### Cuidados

- **Valores em minúsculas, sem acento e sem espaço**, exatamente como no modelo. A comparação é exata: `'Ativa'` é diferente de `'ativa'`.
- **A ordem dos valores tem significado.** O `ORDER BY` em um ENUM segue a ordem da declaração, não a alfabética: `'trial' < 'ativa' < 'inadimplente' < 'cancelada'`. A ordem do modelo acompanha o ciclo de vida da assinatura.

### O problema que aconteceu: erros de digitação que o banco aceitou

A primeira versão foi aplicada **sem nenhum erro**, mas estava errada:

| Tipo | Estava | Correto |
| --- | --- | --- |
| `periodicidade` | `'anul'` | `'anual'` |
| `status_assinatura` | `'inadiplente'` | `'inadimplente'` |
| `motivo_cancelamento` | `'inadiplencia'` | `'inadimplencia'` |
| `motivo_cancelamento` | `'outros'` | `'outro'` |
| `tipo_publicacao` | não existia | `('revista', 'newsletter')` |

**Por que não deu erro:** para o Postgres, `'anul'` é um valor tão válido quanto `'anual'`. Ele não tem como saber o que você quis escrever.

**Por que corrigir na hora:** os valores são usados em todo o projeto (caso de negócio, seed, consultas). Com `'inadiplente'` no banco, um `WHERE status = 'inadimplente'` daria **erro**, porque o valor não existe no ENUM. Corrigir depois, com dados, exigiria uma migration nova com `ALTER TYPE ... RENAME VALUE`.

**Lição:** `Successfully applied` significa que o SQL rodou, não que está certo. Confira sempre o resultado no banco.

### Conferir

O log do Flyway **não lista** os comandos executados. Ele trata o arquivo inteiro como uma unidade:

```
Successfully applied 1 migration to schema "public", now at version v1
```

Essa linha quer dizer que **todos** os comandos rodaram sem erro. Se um falhasse, o Flyway mostraria `ERROR` com o comando problemático e desfaria a migration inteira.

Para ver **o que** foi criado, consulte o banco:

```sql
SELECT t.typname AS tipo, e.enumlabel AS valor
FROM pg_type t
JOIN pg_enum e ON e.enumtypid = t.oid
ORDER BY t.typname, e.enumsortorder;
```

Ou pelo terminal:

```bash
docker exec pauta-postgres psql -U postgres -d pauta -c '\dT+'
```

No DBeaver: `pauta` → Esquemas → `public` → **Tipos de dados**.

Resultado esperado: **4 tipos e 14 valores**.

```
        tipo         |        valor
---------------------+----------------------
 motivo_cancelamento | preco
 motivo_cancelamento | conteudo
 motivo_cancelamento | pouco_uso
 motivo_cancelamento | inadimplencia
 motivo_cancelamento | trial_nao_convertido
 motivo_cancelamento | outro
 periodicidade       | mensal
 periodicidade       | anual
 status_assinatura   | trial
 status_assinatura   | ativa
 status_assinatura   | inadimplente
 status_assinatura   | cancelada
 tipo_publicacao     | revista
 tipo_publicacao     | newsletter
```

---

## 7. Tabelas do catálogo

As seis tabelas do V1 foram divididas em dois blocos:

| Bloco | Tabelas | Por quê |
| --- | --- | --- |
| **Catálogo** (esta seção) | `planos`, `publicacoes`, `plano_publicacoes` | O que a empresa vende. Não depende de nenhuma outra tabela |
| Operação (próxima) | `assinantes`, `assinaturas`, `historico_assinaturas` | Quem assina o quê. Depende do catálogo |

**O que foi feito:** acrescentadas ao `V1__schema_inicial.sql`, abaixo dos ENUMs:

```sql
CREATE TABLE planos (
    id              smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo          text NOT NULL UNIQUE,
    nome            text NOT NULL,
    periodicidade   periodicidade NOT NULL,
    preco_centavos  integer NOT NULL CHECK (preco_centavos >= 0),
    max_perfis      smallint NOT NULL DEFAULT 1 CHECK (max_perfis >= 1),
    ativo           boolean NOT NULL DEFAULT true
);

CREATE TABLE publicacoes (
    id         integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome       text NOT NULL,
    tipo       tipo_publicacao NOT NULL,
    categoria  text NOT NULL
);

CREATE TABLE plano_publicacoes (
    plano_id       smallint NOT NULL REFERENCES planos (id),
    publicacao_id  integer  NOT NULL REFERENCES publicacoes (id),
    PRIMARY KEY (plano_id, publicacao_id)
);
```

As colunas vêm do diagrama do [modelo de dados](../modelo-de-dados.md).

### A anatomia de um `CREATE TABLE`

Cada linha segue o padrão `nome_da_coluna  tipo  regras`:

| Regra | O que faz |
| --- | --- |
| `PRIMARY KEY` | Identificador único da linha. Não pode repetir nem ser nulo |
| `GENERATED ALWAYS AS IDENTITY` | O banco gera o `id` sozinho (1, 2, 3...). É a forma moderna do antigo `SERIAL` |
| `NOT NULL` | Campo obrigatório |
| `UNIQUE` | Não pode haver dois planos com o mesmo `codigo` |
| `DEFAULT 1` | Valor usado quando o `INSERT` não informa a coluna |
| `CHECK (...)` | Regra de negócio validada pelo banco |
| `REFERENCES tabela (coluna)` | Chave estrangeira (FK): só aceita valores que existam na outra tabela |

### Por que cada escolha

**`planos`**

- **`id` e `codigo`:** o `id` é técnico, usado nas FKs. O `codigo` (ex.: `essencial`, `completo_anual`) é legível e fixo, bom para usar em consultas e no seed sem depender do número que o banco gerou.
- **`periodicidade periodicidade`:** a coluna tem o mesmo nome do ENUM. É o primeiro uso de um tipo criado na seção anterior.
- **`preco_centavos integer`:** dinheiro em centavos, nunca em `float` (decisão **D6** em [decisoes.md](../decisoes.md)). R$ 19,90 vira `1990`.
- **`CHECK (preco_centavos >= 0)`:** é a constraint "de valores" da checklist. Preço negativo não existe.
- **`max_perfis` com `DEFAULT 1` e `CHECK (>= 1)`:** a maioria dos planos tem 1 perfil (só o Família tem até 4), e nenhum plano pode ter zero.
- **`ativo`:** permite tirar um plano de venda sem apagá-lo. Apagar quebraria as assinaturas antigas que apontam para ele.

**`publicacoes`**

- **`id integer`** e não `smallint`: planos são poucos e cabem em `smallint` (até 32.767), mas o catálogo de publicações pode crescer mais.
- **`tipo tipo_publicacao`:** o outro ENUM. Aqui a coluna tem nome diferente do tipo.
- **`categoria text`:** texto livre (`economia`, `tecnologia`...). Não virou ENUM porque novas categorias podem surgir, e adicionar valor a um ENUM exige migration.

**`plano_publicacoes`**

É a tabela de ligação **muitos para muitos**: um plano inclui várias publicações, e uma publicação está em vários planos (uma newsletter está no Essencial, no Completo e no Família).

- **Duas FKs:** o banco só aceita ligar um plano e uma publicação que existam.
- **`PRIMARY KEY (plano_id, publicacao_id)`:** chave **composta**, declarada no fim e não em uma coluna. Impede ligar a mesma publicação ao mesmo plano duas vezes.
- **Tipos iguais aos da origem:** `plano_id smallint` porque `planos.id` é `smallint`, e `publicacao_id integer` porque `publicacoes.id` é `integer`. Uma FK precisa do mesmo tipo da coluna para onde aponta.

### Por que nessa ordem

Uma FK só pode apontar para uma tabela que já existe. Como a `plano_publicacoes` aponta para `planos` e `publicacoes`, ela tem que vir **depois** das duas:

```
CREATE TABLE planos (...);
CREATE TABLE publicacoes (...);
CREATE TABLE plano_publicacoes (...);   ← depende das duas de cima
```

### Validar o SQL sem apagar o banco

Antes do `down -v`, dá para testar o arquivo num banco temporário, dentro do mesmo container:

```bash
docker exec pauta-postgres createdb -U postgres valida_v1
docker exec -i pauta-postgres psql -U postgres -d valida_v1 -v ON_ERROR_STOP=1 < migrations/V1__schema_inicial.sql
docker exec pauta-postgres psql -U postgres -d valida_v1 -c '\dt'
docker exec pauta-postgres dropdb -U postgres valida_v1
```

O `ON_ERROR_STOP=1` faz o `psql` parar no primeiro erro, como o Flyway faria. Se passar, o `down -v` + `up -d` vai funcionar.

### Conferir

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
```

Resultado:

```
 flyway_schema_history
 plano_publicacoes
 planos
 publicacoes
```

Para ver as colunas e constraints de uma tabela: `docker exec pauta-postgres psql -U postgres -d pauta -c '\d planos'`.

### Testar as constraints

**`CHECK` de preço**, com um valor negativo:

```sql
INSERT INTO planos (codigo, nome, periodicidade, preco_centavos)
VALUES ('teste', 'Teste', 'mensal', -100);
```

```
ERROR:  new row for relation "planos" violates check constraint "planos_preco_centavos_check"
DETAIL:  Failing row contains (1, teste, Teste, mensal, -100, 1, t).
```

**FK**, ligando um plano e uma publicação que não existem:

```sql
INSERT INTO plano_publicacoes VALUES (1, 99);
```

```
ERROR:  insert or update on table "plano_publicacoes" violates foreign key constraint "plano_publicacoes_plano_id_fkey"
DETAIL:  Key (plano_id)=(1) is not present in table "planos".
```

O Postgres dá nome às constraints automaticamente, no formato `tabela_coluna_tipo` (`_check`, `_fkey`, `_key`, `_pkey`). O nome aparece no erro e ajuda a achar a regra violada.

> **Detalhe do IDENTITY:** o `INSERT` que falhou no `CHECK` já tinha consumido o `id` 1 (aparece no `DETAIL`). O contador do IDENTITY **não volta** quando um `INSERT` falha, então o próximo plano inserido nesse banco receberia `id = 2`. Por isso o `codigo` é a forma confiável de identificar um plano, e não o número do `id`.

---

## 8. Tabelas da operação

**O que foi feito:** acrescentadas ao `V1__schema_inicial.sql`, abaixo da `plano_publicacoes`:

```sql
CREATE TABLE assinantes (
    id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome             text NOT NULL,
    email            citext NOT NULL UNIQUE,
    uf               char(2) NOT NULL CHECK (uf ~ '^[A-Z]{2}$'),
    cidade           text NOT NULL,
    data_nascimento  date,
    criado_em        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE assinaturas (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    assinante_id  bigint NOT NULL REFERENCES assinantes (id),
    plano_id      smallint NOT NULL REFERENCES planos (id),
    status        status_assinatura NOT NULL DEFAULT 'trial',
    iniciada_em   date NOT NULL DEFAULT current_date,
    periodo_fim   date NOT NULL,
    cancelada_em  timestamptz,
    motivo        motivo_cancelamento,
    CHECK ((status = 'cancelada') = (cancelada_em IS NOT NULL)
       AND (status = 'cancelada') = (motivo IS NOT NULL))
);

CREATE TABLE historico_assinaturas (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    assinatura_id  bigint NOT NULL REFERENCES assinaturas (id),
    evento         text NOT NULL,
    detalhes       jsonb,
    ocorrido_em    timestamptz NOT NULL DEFAULT now()
);
```

A ordem segue as dependências: `assinantes` não depende de ninguém, `assinaturas` aponta para `assinantes` e `planos`, e `historico_assinaturas` aponta para `assinaturas`.

### Por que cada escolha

**`assinantes`**

| Trecho | Por quê |
| --- | --- |
| `id bigint` | Assinantes podem chegar a milhões. O `bigint` dá folga de sobra |
| `email citext ... UNIQUE` | **O uso do `citext`**: `Joao@Email.com` e `joao@email.com` contam como o mesmo e-mail, e o `UNIQUE` recusa o segundo |
| `uf char(2)` | Texto de tamanho fixo, 2 caracteres |
| `CHECK (uf ~ '^[A-Z]{2}$')` | **`CHECK` de UF.** O `~` compara com uma expressão regular: exatamente 2 letras maiúsculas. Aceita `SP` e recusa `sp`, `S1` ou `São Paulo`. A UF importa porque o RLS da V5 filtra o atendimento por região |
| `data_nascimento` sem `NOT NULL` | Opcional: nem todo cadastro informa |
| `criado_em timestamptz DEFAULT now()` | Data e hora **com fuso horário**, preenchida automaticamente no `INSERT` |

> O `CHECK` de UF valida o **formato**, não se a UF existe: `XX` passaria. Validar as 27 UFs exigiria uma lista ou uma tabela de UFs.

**`assinaturas`**

| Trecho | Por quê |
| --- | --- |
| `assinante_id bigint` / `plano_id smallint` | Tipos iguais aos dos `id` para onde as FKs apontam |
| `status ... DEFAULT 'trial'` | Regra 2 do caso de negócio: toda assinatura nova começa em trial. O texto é convertido para o ENUM |
| `iniciada_em DEFAULT current_date` | A data de hoje, se não for informada |
| `periodo_fim NOT NULL` | Até quando o acesso está pago. Regra 6: depois de cancelar, o acesso continua até essa data |
| `cancelada_em` e `motivo` sem `NOT NULL` | Ficam vazios enquanto a assinatura não é cancelada. Quem garante o preenchimento no cancelamento é o `CHECK` |
| Sem `cupom_id` | O diagrama mostra a coluna, mas ela entra na V3 |

**`historico_assinaturas`**

- **`detalhes jsonb`:** JSON guardado em formato binário e indexável. Os detalhes variam com o evento (`{"de": "trial", "para": "ativa"}` numa troca de status, `{"plano_anterior": 1, "plano_novo": 2}` numa troca de plano), e uma coluna fixa para cada caso não daria conta.
- A tabela fica **vazia por enquanto**. Quem vai preenchê-la é um trigger da V2, automaticamente, a cada mudança na assinatura.

### `CHECK` no fim da tabela

O `CHECK` de cancelamento envolve **várias colunas**, então não pertence a nenhuma delas. Ele é declarado no fim, depois das colunas, como a chave composta da `plano_publicacoes`. Por isso a coluna `motivo`, que vem antes dele, precisa de vírgula.

### O problema que aconteceu: o `CHECK` de cancelamento tinha um buraco

A primeira versão era a do modelo de dados:

```sql
CHECK ((status = 'cancelada') = (cancelada_em IS NOT NULL AND motivo IS NOT NULL))
```

A ideia é comparar dois verdadeiro/falso e exigir que sejam iguais. O problema é o `AND` juntando data e motivo: para uma assinatura **não cancelada**, basta faltar **um** dos dois para o lado direito dar falso, e o `CHECK` passa. Uma assinatura `ativa` com motivo `preco` e sem data foi **aceita** no teste.

A tabela verdade completa mostra o buraco:

| status | data | motivo | `CHECK` original | `CHECK` corrigido |
| --- | --- | --- | --- | --- |
| ativa | sim | sim | recusa | recusa |
| ativa | **sim** | **não** | **aceita** ❌ | recusa |
| ativa | **não** | **sim** | **aceita** ❌ | recusa |
| ativa | não | não | aceita | aceita |
| cancelada | sim | sim | aceita | aceita |
| cancelada | sim | não | recusa | recusa |
| cancelada | não | sim | recusa | recusa |
| cancelada | não | não | recusa | recusa |

**Correção:** comparar **cada campo separadamente** com o status:

```sql
CHECK ((status = 'cancelada') = (cancelada_em IS NOT NULL)
   AND (status = 'cancelada') = (motivo IS NOT NULL))
```

Lê-se: "data preenchida **se e somente se** cancelada, **e** motivo preenchido **se e somente se** cancelada". A regra em [modelo-de-dados.md](../modelo-de-dados.md) foi corrigida junto.

**Lição:** ao escrever um `CHECK` com várias condições, monte a tabela verdade com **todas** as combinações. Testar só os casos "tudo preenchido" e "nada preenchido" esconde os casos do meio. Dá para gerar a tabela no próprio Postgres:

```sql
SELECT s AS status, d AS tem_data, m AS tem_motivo,
       ((s = 'cancelada') = (d AND m))                    AS check_original,
       ((s = 'cancelada') = d AND (s = 'cancelada') = m)  AS check_corrigido
FROM (VALUES ('ativa'), ('cancelada')) a(s),
     (VALUES (true), (false)) b(d),
     (VALUES (true), (false)) c(m)
ORDER BY 1, 2 DESC, 3 DESC;
```

### Testar as constraints

Os testes rodaram num banco temporário (`valida_v1`, ver seção 7), para não consumir ids do `pauta`.

| # | Teste | Resultado |
| --- | --- | --- |
| 1 | Assinante válido | ✅ aceito |
| 2 | `JOAO@Email.com` depois de `joao@email.com` | ✅ recusado: `assinantes_email_key` |
| 3 | UF `sp` minúscula | ✅ recusado: `assinantes_uf_check` |
| 4 | Assinatura sem informar o status | ✅ entrou como `trial`, com `iniciada_em` = hoje |
| 5 | Ativa com motivo, sem data | ✅ recusado: `assinaturas_check` (era aceito antes da correção) |
| 6 | Ativa com data, sem motivo | ✅ recusado: `assinaturas_check` |
| 7 | Cancelada sem motivo | ✅ recusado: `assinaturas_check` |
| 8 | Cancelada com data e motivo | ✅ aceito |
| 9 | Histórico com `detalhes` em `jsonb` | ✅ aceito |

Exemplo de erro do e-mail repetido:

```
ERROR:  duplicate key value violates unique constraint "assinantes_email_key"
DETAIL:  Key (email)=(JOAO@Email.com) already exists.
```

Para conferir a constraint aplicada no banco:

```sql
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'assinaturas_check';
```

---

## 9. Índice único parcial

**O que foi feito:** acrescentado ao fim do `V1__schema_inicial.sql`, abaixo da `historico_assinaturas`:

```sql
CREATE UNIQUE INDEX uq_assinaturas_ativa_por_assinante
    ON assinaturas (assinante_id)
    WHERE status <> 'cancelada';
```

Em português: "na tabela `assinaturas`, o `assinante_id` não pode se repetir **entre as assinaturas que não estão canceladas**".

### O problema que ele resolve

Regra 1 do [caso de negócio](../caso-de-negocio.md): **uma assinatura ativa por assinante**. Um assinante pode ter várias assinaturas no histórico (cancelou e voltou depois), mas só uma em andamento, ou seja, em `trial`, `ativa` ou `inadimplente`.

| Assinaturas do assinante | Permitido? |
| --- | --- |
| 1 ativa | ✅ |
| 1 ativa + 3 canceladas (reassinou) | ✅ |
| 1 ativa + 1 trial | ❌ duas em andamento |
| 1 inadimplente + 1 ativa | ❌ duas em andamento |

### Por que um `UNIQUE` comum não serve

`UNIQUE (assinante_id)` permitiria **uma única assinatura por assinante, para sempre**. A reassinatura (cancelar e voltar meses depois) seria bloqueada, e o caso de negócio prevê reassinaturas.

A regra precisa ser "único, **mas só entre as não canceladas**". Isso é um índice **parcial**: um índice que só inclui as linhas que atendem a um `WHERE`.

| Parte | O que faz |
| --- | --- |
| `UNIQUE INDEX` | Índice que não aceita valores repetidos. É assim que o Postgres implementa o `UNIQUE` por baixo |
| `ON assinaturas (assinante_id)` | Qual coluna não pode repetir |
| `WHERE status <> 'cancelada'` | **A parte "parcial"**: só as linhas que atendem à condição entram no índice. As canceladas ficam de fora e podem repetir à vontade |

- `<>` quer dizer "diferente de". Entram no índice as assinaturas em `trial`, `ativa` e `inadimplente`, exatamente as três "em andamento" da regra 1.
- Uma constraint `UNIQUE` **não aceita `WHERE`**. Para uma regra condicional como esta, só um índice resolve.

### O nome do índice

O nome é livre, mas aparece na mensagem de erro, então vale ser descritivo. O padrão usado foi `uq_` (de *unique*) + tabela + o que ele garante: `uq_assinaturas_ativa_por_assinante`. Diferente das constraints, o Postgres não gera um nome bom para índices criados com `CREATE INDEX`.

### Por que no fim do arquivo

O índice depende da tabela `assinaturas` e do ENUM `status_assinatura`. Ele poderia vir logo depois da `assinaturas`, mas deixar os índices no fim, separados das tabelas, facilita encontrá-los.

### Conferir

```sql
SELECT indexdef FROM pg_indexes
WHERE indexname = 'uq_assinaturas_ativa_por_assinante';
```

```
CREATE UNIQUE INDEX uq_assinaturas_ativa_por_assinante ON public.assinaturas
USING btree (assinante_id) WHERE (status <> 'cancelada'::status_assinatura)
```

O `USING btree` é o tipo de índice padrão do Postgres, usado quando nenhum outro é informado.

### Testar

Os testes rodaram num banco temporário (`valida_v1`), com dois assinantes, João e Maria:

| # | Cenário | Esperado | Resultado |
| --- | --- | --- | --- |
| 1 | 1ª assinatura do João | aceitar | ✅ |
| 2 | 2ª assinatura em andamento do João | recusar | ✅ `uq_assinaturas_ativa_por_assinante` |
| 3 | Assinatura da Maria (outro assinante) | aceitar | ✅ |
| 4 | João cancela e reassina | aceitar | ✅ |
| 5 | João cancela de novo e reassina (fica com 2 canceladas) | aceitar | ✅ |
| 6 | Reativar uma cancelada enquanto o João tem outra em andamento | recusar | ✅ |

```
ERROR:  duplicate key value violates unique constraint "uq_assinaturas_ativa_por_assinante"
DETAIL:  Key (assinante_id)=(1) already exists.
```

Estado final:

```
 id | nome  |  status
----+-------+-----------
  1 | Joao  | cancelada
  3 | Maria | trial
  4 | Joao  | cancelada
  5 | Joao  | trial
```

O João tem 3 assinaturas no histórico, mas só uma em andamento.

- **Teste 6:** o índice não protege só o `INSERT`. Ele também barra um `UPDATE` que tente reativar uma assinatura antiga.
- **O `id` 2 sumiu:** foi consumido pelo `INSERT` recusado no teste 2. É o mesmo comportamento do IDENTITY visto na seção 7.

Para testar no próprio `pauta` sem deixar dados para trás, use uma transação com `ROLLBACK`:

```sql
BEGIN;

INSERT INTO planos (codigo, nome, periodicidade, preco_centavos)
VALUES ('teste', 'Teste', 'mensal', 1000);
INSERT INTO assinantes (nome, email, uf, cidade)
VALUES ('Teste', 'teste@email.com', 'SP', 'São Paulo');

-- 1ª assinatura: deve aceitar
INSERT INTO assinaturas (assinante_id, plano_id, periodo_fim)
SELECT a.id, p.id, current_date + 7 FROM assinantes a, planos p;

-- 2ª assinatura em andamento para o mesmo assinante: deve dar ERRO
INSERT INTO assinaturas (assinante_id, plano_id, periodo_fim)
SELECT a.id, p.id, current_date + 7 FROM assinantes a, planos p;

ROLLBACK;
```

> O `ROLLBACK` desfaz as linhas, mas os ids consumidos pelo IDENTITY não voltam.

---

## 10. Carga dos planos e das publicações

**O que foi feito:** acrescentados ao fim do `V1__schema_inicial.sql`, depois do índice, três `INSERT`:

```sql
INSERT INTO planos (codigo, nome, periodicidade, preco_centavos, max_perfis) VALUES
    ('essencial',      'Essencial',      'mensal',  1990, 1),
    ('completo',       'Completo',       'mensal',  3990, 1),
    ('completo_anual', 'Completo Anual', 'anual',  39900, 1),
    ('familia',        'Família',        'mensal',  5990, 4);

INSERT INTO publicacoes (nome, tipo, categoria) VALUES
    ('Pauta Economia',       'revista',    'economia'),
    ('Mercado em 5 Minutos', 'newsletter', 'economia'),
    ('Pauta Tech',           'revista',    'tecnologia'),
    ('Bits da Semana',       'newsletter', 'tecnologia'),
    ('Pauta Cultura',        'revista',    'cultura'),
    ('Agenda Cultural',      'newsletter', 'cultura'),
    ('Pauta Esporte',        'revista',    'esportes'),
    ('Placar da Semana',     'newsletter', 'esportes');

INSERT INTO plano_publicacoes (plano_id, publicacao_id)
SELECT p.id, pub.id
FROM planos p
CROSS JOIN publicacoes pub
WHERE p.codigo <> 'essencial'
   OR pub.tipo = 'newsletter';
```

### Por que esses dados ficam na migration

| Dado | Onde fica | Por quê |
| --- | --- | --- |
| Planos e publicações | **Migration (V1)** | Dados fixos do negócio. Sem eles nenhuma assinatura pode existir, e precisam ser iguais em qualquer banco |
| Assinantes e assinaturas | Seed Python | Dados de exemplo, que variam em volume e conteúdo |

Uma mudança de preço ou um plano novo, no futuro, viraria uma nova migration, e o histórico do Flyway registraria quando o catálogo mudou.

### Planos

Os dados vêm da tabela de planos do [caso de negócio](../caso-de-negocio.md):

| Plano | Preço | Em centavos | Perfis |
| --- | --- | --- | --- |
| Essencial | R$ 19,90 | `1990` | 1 |
| Completo | R$ 39,90 | `3990` | 1 |
| Completo Anual | R$ 399,00 | `39900` | 1 |
| Família | R$ 59,90 | `5990` | 4 |

- **Várias linhas num único `INSERT`:** cada linha entre parênteses, separadas por vírgula, e `;` só no fim.
- **O `id` não aparece:** o IDENTITY gera sozinho.
- **O `ativo` também não aparece:** usa o `DEFAULT true`.
- **Preço em centavos:** sempre multiplique por 100 (decisão **D6**).
- **O `codigo`** (`essencial`, `completo_anual`...) é o identificador estável do plano, usado no `INSERT` das ligações e, mais adiante, no seed.

### Publicações

O caso de negócio diz que há revistas e newsletters sobre economia, tecnologia, cultura e esportes, mas **não dá os nomes**. A decisão foi criar uma revista e uma newsletter por categoria, 8 publicações no total, com nomes fictícios.

A `categoria` fica sempre **em minúsculas e sem acento**. Como ela é `text` e não ENUM, o banco não barra variações: `Economia` e `economia` virariam categorias diferentes nas consultas.

### Ligações plano × publicação

A regra do caso de negócio: **o Essencial tem só as newsletters, e os outros 3 planos têm tudo**. Em vez de escrever 28 linhas com ids (`(1, 2), (1, 4)...`), o banco monta as combinações:

| Trecho | O que faz |
| --- | --- |
| `INSERT ... SELECT` | Insere o resultado de uma consulta, em vez de valores digitados |
| `CROSS JOIN` | Combina **cada** plano com **cada** publicação: 4 × 8 = 32 combinações |
| `WHERE p.codigo <> 'essencial' OR pub.tipo = 'newsletter'` | Mantém a combinação se o plano **não** for o Essencial (leva tudo) **ou** se a publicação for newsletter. O Essencial perde as 4 revistas, e sobram **28 ligações** |

**Por que não usar ids fixos:** o IDENTITY pode pular números (seções 7 e 9). Buscar pelo `codigo` e pelo `tipo` funciona sejam quais forem os ids gerados. Também fica mais legível: a regra de negócio está escrita no `WHERE`.

### Por que nessa ordem

Planos → publicações → ligações. As ligações leem as duas tabelas, então os dois lados precisam existir antes. Pelo mesmo motivo, a carga vem depois de todos os `CREATE TABLE`.

### Conferir

**Planos:**

```sql
SELECT id, codigo, nome, periodicidade, preco_centavos, max_perfis, ativo
FROM planos
ORDER BY id;
```

```
 id |     codigo     |      nome      | periodicidade | preco_centavos | max_perfis | ativo
----+----------------+----------------+---------------+----------------+------------+-------
  1 | essencial      | Essencial      | mensal        |           1990 |          1 | t
  2 | completo       | Completo       | mensal        |           3990 |          1 | t
  3 | completo_anual | Completo Anual | anual         |          39900 |          1 | t
  4 | familia        | Família        | mensal        |           5990 |          4 | t
```

A coluna `ativo` veio `t` (verdadeiro) sem estar no `INSERT`: é o `DEFAULT true` agindo. Para ver os preços em reais, sem mudar como estão guardados:

```sql
SELECT nome, preco_centavos / 100.0 AS preco_reais FROM planos;
```

**Publicações:**

```sql
SELECT id, nome, tipo, categoria
FROM publicacoes
ORDER BY categoria, tipo;
```

**O que cada plano inclui** (o teste principal):

```sql
SELECT p.nome AS plano,
       count(*) AS publicacoes,
       count(*) FILTER (WHERE pub.tipo = 'revista')    AS revistas,
       count(*) FILTER (WHERE pub.tipo = 'newsletter') AS newsletters
FROM planos p
JOIN plano_publicacoes pp ON pp.plano_id = p.id
JOIN publicacoes pub      ON pub.id = pp.publicacao_id
GROUP BY p.id, p.nome
ORDER BY p.id;
```

```
     plano      | publicacoes | revistas | newsletters
----------------+-------------+----------+-------------
 Essencial      |           4 |        0 |           4
 Completo       |           8 |        4 |           4
 Completo Anual |           8 |        4 |           4
 Família        |           8 |        4 |           4
```

A linha que importa é a do **Essencial**: `0` revistas. O `count(*) FILTER (WHERE ...)` conta só as linhas que atendem à condição, o que permite várias contagens diferentes numa única consulta.

Para ver **os nomes** em vez de números:

```sql
SELECT p.nome AS plano,
       string_agg(pub.nome, ', ' ORDER BY pub.nome) AS publicacoes
FROM planos p
JOIN plano_publicacoes pp ON pp.plano_id = p.id
JOIN publicacoes pub      ON pub.id = pp.publicacao_id
GROUP BY p.id, p.nome
ORDER BY p.id;
```

O `string_agg` junta os nomes de cada plano num texto só, separado por vírgula.

**As regras continuam valendo com dados:** um plano com código repetido é recusado.

```sql
INSERT INTO planos (codigo, nome, periodicidade, preco_centavos)
VALUES ('essencial', 'Outro Essencial', 'mensal', 990);
-- ERRO: duplicate key value violates unique constraint "planos_codigo_key"
```

---

## 11. Conferir o V1 inteiro

Duas consultas para garantir que o V1 foi aplicado por completo.

### Resumo: está tudo lá?

```sql
SELECT 'extensões' AS item, count(*) AS total, 2 AS esperado
FROM pg_extension WHERE extname IN ('citext', 'pg_stat_statements')
UNION ALL
SELECT 'tipos ENUM', count(DISTINCT enumtypid), 4 FROM pg_enum
UNION ALL
SELECT 'valores ENUM', count(*), 14 FROM pg_enum
UNION ALL
SELECT 'tabelas', count(*), 6
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
  AND table_name <> 'flyway_schema_history'
UNION ALL
SELECT 'constraints', count(*), 17
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
  AND conrelid <> 'flyway_schema_history'::regclass
  AND contype <> 'n'
UNION ALL
SELECT 'índices parciais', count(*), 1
FROM pg_indexes
WHERE schemaname = 'public' AND indexdef LIKE '% WHERE %'
UNION ALL
SELECT 'planos', count(*), 4 FROM planos
UNION ALL
SELECT 'publicações', count(*), 8 FROM publicacoes
UNION ALL
SELECT 'ligações plano × publicação', count(*), 28 FROM plano_publicacoes;
```

Se `total` for igual a `esperado` em todas as linhas, o V1 está completo:

```
            item             | total | esperado
-----------------------------+-------+----------
 extensões                   |     2 |        2
 tipos ENUM                  |     4 |        4
 valores ENUM                |    14 |       14
 tabelas                     |     6 |        6
 constraints                 |    17 |       17
 índices parciais            |     1 |        1
 planos                      |     4 |        4
 publicações                 |     8 |        8
 ligações plano × publicação |    28 |       28
```

As 17 constraints são 6 `PRIMARY KEY`, 5 `FOREIGN KEY`, 4 `CHECK` e 2 `UNIQUE`.

**Por que `contype <> 'n'`:** no Postgres 18, cada `NOT NULL` também é registrado como constraint (tipo `n`). Sem esse filtro aparecem 46 linhas, 29 delas só de `NOT NULL`.

> As contagens de planos, publicações e ligações valem para o catálogo fixo. Depois do seed, as tabelas de assinantes e assinaturas vão ter dados, mas essas três devem continuar iguais.

### Detalhe: quais são as regras

```sql
SELECT conrelid::regclass AS tabela,
       CASE contype
           WHEN 'p' THEN 'PRIMARY KEY'
           WHEN 'f' THEN 'FOREIGN KEY'
           WHEN 'u' THEN 'UNIQUE'
           WHEN 'c' THEN 'CHECK'
       END AS tipo,
       pg_get_constraintdef(oid) AS regra
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
  AND conrelid <> 'flyway_schema_history'::regclass
  AND contype <> 'n'
ORDER BY tabela::text, tipo;
```

Mostra cada regra por extenso, como `CHECK ((uf ~ '^[A-Z]{2}$'))` ou `FOREIGN KEY (plano_id) REFERENCES planos(id)`. Serve para conferir se a regra no banco é a que foi escrita.

### O que essas consultas não garantem

Elas confirmam que as regras **existem**, não que **funcionam**. O `CHECK` de cancelamento com defeito (seção 8) também apareceria na lista e passaria na contagem. Para saber se uma regra funciona, só tentando inserir dados errados, como nos testes das seções 7, 8 e 9.

---

## Próximo passo

A Migration V1 está completa. Para fechar a v0.3.0 na [checklist](../checklist.md), faltam: confirmar que tudo sobe do zero (`docker compose down -v && docker compose up -d`), atualizar o README e o modelo de dados com o novo escopo e publicar a release.

Depois vem a v0.4.0: gerar dados de exemplo em SQL e criar a `V2__cupons.sql`, aplicando-a num banco **com dados**, sem `down -v`.
