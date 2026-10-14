# 03 — Evoluir o schema com dados

Até aqui, toda mudança no banco foi feita **editando o V1 e apagando o banco** com `docker compose down -v` (ver [02 — Primeira migration (V1)](02%20-%20migration.md)). Isso só funciona porque o banco ainda era descartável.

Esta etapa faz o contrário: muda o schema de um banco que **já tem dados**, sem apagar nada. É para isso que o Flyway existe.

Itens da [checklist](../checklist.md) (v0.4.0):

- Script `scripts/dados_exemplo.sql` com `generate_series`: assinantes e assinaturas de exemplo
- Migration `V2__cupons.sql`: tabela `cupons` e coluna `cupom_id` em `assinaturas`
- Aplicar a V2 com `docker compose up` (sem `down -v`) e confirmar que os dados continuam lá
- Ver as duas versões na `flyway_schema_history` e provocar o erro de checksum editando o V1

---

## 1. Corrigir os dados de exemplo

**O que foi feito:** o script `scripts/dados_exemplo.sql` foi reescrito para que as datas das assinaturas façam sentido com o status e o plano.

O script **não é uma migration**. Ele roda sob demanda, começa com `TRUNCATE` e pode ser executado quantas vezes for preciso. Migrations mudam a *estrutura*; este script só preenche dados para testar.

### O problema que aconteceu: dados que o banco aceitou, mas o negócio não

A primeira versão calculava o fim do período assim:

```sql
b.inicio + 30,
```

Nenhuma constraint reclamou, mas os dados contradiziam o [caso de negócio](../caso-de-negocio.md):

| Situação | O que o script gerava | O que deveria acontecer |
| --- | --- | --- |
| Plano anual | Período de 30 dias | Período de 365 dias |
| `trial` | Podia ter começado há 2 anos | O trial dura 7 dias: só quem entrou na última semana está em trial |
| `ativa` | `periodo_fim` quase sempre no passado | Se está ativa, o ciclo atual ainda não venceu |

É o mesmo tipo de problema da seção 6 do [02](02%20-%20migration.md): o banco só barra o que tem regra para barrar.

### A lógica nova

1. **O status depende de quando o assinante entrou.** Quem entrou nos últimos 7 dias está em `trial`. Os demais são sorteados: 75% `ativa`, 10% `inadimplente`, 15% `cancelada`.
2. **O fim do período depende do status e do plano:**

| Status | `periodo_fim` |
| --- | --- |
| `trial` | início + 7 dias |
| `ativa` | uma data no futuro, dentro de um ciclo |
| `inadimplente` | uma data no passado (o ciclo venceu e não foi pago) |
| `cancelada` | início + um ciclo (o acesso vale até o fim do período pago) |

3. **O tamanho do ciclo vem do banco**, pela coluna `planos.periodicidade` (30 ou 365 dias), e não de um número fixo no script.

### Como a consulta funciona

O `INSERT` das assinaturas é lido de dentro para fora:

1. A subconsulta mais interna sorteia um plano e um número aleatório (`r`) para cada assinante.
2. A do meio junta com `planos` para descobrir o tamanho do ciclo e decide o status.
3. O `SELECT` de fora calcula as datas a partir disso.

Detalhes:

- **`GREATEST` e `LEAST`** mantêm as datas coerentes: um inadimplente que entrou há 10 dias não pode ter o período vencido há 25, e um cancelamento não pode estar no futuro.
- **`date + inteiro`** soma dias e devolve `date`. Já `date + interval` devolveria `timestamp`, por isso o script usa inteiros.

### Rodar

Com o banco no ar:

```bash
docker compose cp scripts/dados_exemplo.sql postgres:/tmp/dados_exemplo.sql
docker compose exec postgres psql -U postgres -d pauta -v ON_ERROR_STOP=1 -f /tmp/dados_exemplo.sql
```

- `docker compose cp` copia o arquivo para dentro do container. Funciona igual no PowerShell, no CMD e no WSL.
- `-v ON_ERROR_STOP=1` faz o `psql` parar no primeiro erro, em vez de seguir e esconder o problema.

O aviso `NOTICE: truncate cascades to table "historico_assinaturas"` é esperado.

### Conferir

```sql
SELECT a.status, p.periodicidade, count(*),
       min(periodo_fim - iniciada_em) AS menor_periodo,
       count(*) FILTER (WHERE periodo_fim < current_date) AS vencidos
FROM assinaturas a JOIN planos p ON p.id = a.plano_id
GROUP BY 1, 2 ORDER BY 1, 2;
```

Resultado obtido (os números variam a cada execução por causa do `random()`):

```
    status    | periodicidade | count | menor_periodo | vencidos
--------------+---------------+-------+---------------+----------
 trial        | mensal        |     4 |             7 |        0
 trial        | anual         |     3 |             7 |        0
 ativa        | mensal        |   276 |            12 |        0
 ativa        | anual         |    99 |            31 |        0
 inadimplente | mensal        |    32 |             1 |       32
 inadimplente | anual         |     7 |            14 |        7
 cancelada    | mensal        |    63 |            30 |       61
 cancelada    | anual         |    16 |           365 |        9
```

| O que conferir | Resultado |
| --- | --- |
| Trials com 7 dias e nenhum vencido | ✅ |
| Nenhuma ativa vencida | ✅ |
| Todas as inadimplentes vencidas | ✅ |
| Canceladas com 30 dias (mensal) e 365 (anual) | ✅ |

Algumas canceladas não aparecem como vencidas: o período pago ainda não acabou e, pela regra do caso, o acesso continua até lá.

---

## 2. Criar a migration `V2__cupons.sql`

**O que foi feito:** criado o arquivo `migrations/V2__cupons.sql` com o tipo `tipo_desconto`, a tabela `cupons`, a coluna `cupom_id` em `assinaturas`, um índice e três cupons iniciais.

```sql
-- V2: cupons de desconto.
-- Roda num banco que já tem dados: só acrescenta estruturas, não recria nem apaga nada.

-- 1. Tipo do desconto
CREATE TYPE tipo_desconto AS ENUM ('percentual', 'valor_fixo');

-- 2. Tabela de cupons
CREATE TABLE cupons (
    id           integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo       citext NOT NULL UNIQUE,                          -- 'bemvindo10' = 'BEMVINDO10'
    tipo         tipo_desconto NOT NULL,
    valor        integer NOT NULL CHECK (valor > 0),              -- % ou centavos, conforme o tipo
    ciclos       smallint NOT NULL DEFAULT 1 CHECK (ciclos >= 1), -- quantas cobranças recebem o desconto
    valido_ate   date,                                            -- NULL = sem data de validade
    limite_usos  integer CHECK (limite_usos > 0),                 -- NULL = sem limite
    CONSTRAINT ck_cupons_percentual_max
        CHECK (tipo <> 'percentual' OR valor <= 100)              -- percentual não passa de 100%
);

-- 3. Ligação com as assinaturas existentes
--    A coluna nasce NULL: as assinaturas que já existem ficam "sem cupom".
ALTER TABLE assinaturas
    ADD COLUMN cupom_id integer REFERENCES cupons (id);

CREATE INDEX ix_assinaturas_cupom_id ON assinaturas (cupom_id);

-- 4. Cupons iniciais
INSERT INTO cupons (codigo, tipo, valor, ciclos, valido_ate, limite_usos) VALUES
    ('BEMVINDO10',  'percentual', 10,   1, NULL,         NULL),
    ('ANUAL50',     'valor_fixo', 5000, 1, NULL,         NULL),
    ('BLACKFRIDAY', 'percentual', 50,   3, '2026-11-30', 1000);
```

### O que muda numa migration para um banco com dados

| V1 (banco vazio) | V2 (banco com dados) |
| --- | --- |
| `CREATE TABLE` com todas as colunas | `ALTER TABLE ... ADD COLUMN` em tabela existente |
| Qualquer `NOT NULL` funciona | Coluna nova em tabela com linhas precisa aceitar `NULL` ou ter `DEFAULT` |
| Se errar, apaga o banco e recomeça | Se errar, os dados estão em jogo |

### Por que cada escolha

**`cupom_id` aceita `NULL`.** É o ponto central da migration. As 500 assinaturas que já existem não têm cupom, e `NULL` representa exatamente isso.

- Com `NOT NULL` sem `DEFAULT`, o Postgres recusaria o `ALTER TABLE`: não saberia o que colocar nas linhas existentes.
- Adicionar uma coluna que aceita `NULL` é instantâneo: o Postgres só altera o catálogo, não reescreve a tabela. Com milhões de linhas, isso faz muita diferença.

**`REFERENCES cupons (id)`.** A chave estrangeira impede apontar para um cupom que não existe. Valores `NULL` passam pela FK, então os dados antigos não são afetados.

**Índice em `cupom_id`.** O Postgres cria índice automaticamente em `PRIMARY KEY` e `UNIQUE`, mas **não** em chaves estrangeiras. Sem ele, "quais assinaturas usaram o cupom X?" lê a tabela inteira.

**`codigo` como `citext`.** O mesmo tipo do e-mail: `bemvindo10`, `BemVindo10` e `BEMVINDO10` são o mesmo cupom. A extensão já foi criada na V1; a V2 só a reutiliza.

**`valor` com dois significados.** Percentual quando `tipo = 'percentual'`, centavos quando `tipo = 'valor_fixo'` (dinheiro em centavos, decisão **D6** em [decisoes.md](../decisoes.md)).

**`CHECK` com nome.** `CONSTRAINT ck_cupons_percentual_max` faz o erro dizer qual regra foi quebrada, em vez de um nome gerado como `cupons_check`.

### A migration é uma transação

No Postgres, até `CREATE TABLE` e `ALTER TABLE` podem ser desfeitos. O Flyway aproveita isso: se qualquer linha da V2 falhar, **nada** dela fica aplicado e o banco volta ao estado da V1. Não existe migration pela metade.

---

## 3. Aplicar a V2 sem `down -v`

**O que foi feito:** com os dados da seção 1 já no banco, apenas:

```bash
docker compose up
```

### O log

```
pauta-postgres | database system was shut down at 2026-10-14 15:46:26 UTC
pauta-flyway   | Successfully validated 2 migrations (execution time 00:00.058s)
pauta-flyway   | Current version of schema "public": 1
pauta-flyway   | Migrating schema "public" to version "2 - cupons"
pauta-flyway   | Successfully applied 1 migration to schema "public", now at version v2 (execution time 00:00.038s)
pauta-flyway exited with code 0
```

| Linha | O que significa |
| --- | --- |
| `database system was shut down at ...` | O Postgres encontrou um banco existente, desligado normalmente. Numa subida do zero apareceriam os logs de criação e do `initdb/` |
| `Successfully validated 2 migrations` | O Flyway achou V1 e V2 e conferiu que a V1 não mudou desde que foi aplicada |
| `Current version ...: 1` | O banco estava na versão 1 |
| `Migrating ... to version "2 - cupons"` | Só a V2 é aplicada. A V1 não roda de novo |
| `exited with code 0` | Terminou sem erro |

### Conferir que os dados sobreviveram

```bash
docker compose exec postgres psql -U postgres -d pauta -c "SELECT count(*) AS assinaturas, count(cupom_id) AS com_cupom FROM assinaturas;"
```

```
 assinaturas | com_cupom
-------------+-----------
         500 |         0
```

As 500 assinaturas continuam lá, e nenhuma tem cupom: a coluna nasceu `NULL`.

```bash
docker compose exec postgres psql -U postgres -d pauta -c "SELECT codigo, tipo, valor, ciclos, valido_ate FROM cupons;"
```

```
   codigo    |    tipo    | valor | ciclos | valido_ate
-------------+------------+-------+--------+------------
 BEMVINDO10  | percentual |    10 |      1 |
 ANUAL50     | valor_fixo |  5000 |      1 |
 BLACKFRIDAY | percentual |    50 |      3 | 2026-11-30
```

### Dados novos convivendo com os antigos

Aplicar o cupom `BEMVINDO10` aos assinantes em trial:

```bash
docker compose exec postgres psql -U postgres -d pauta -c "UPDATE assinaturas SET cupom_id = (SELECT id FROM cupons WHERE codigo = 'BEMVINDO10') WHERE status = 'trial';"
# UPDATE 7

docker compose exec postgres psql -U postgres -d pauta -c "SELECT c.codigo, count(*) FROM assinaturas a JOIN cupons c ON c.id = a.cupom_id GROUP BY c.codigo;"
```

```
   codigo   | count
------------+-------
 BEMVINDO10 |     7
```

Os 7 trials da seção 1 receberam o cupom.

---

## 4. Testar as regras da V2

Os três comandos abaixo **devem falhar**:

```bash
docker compose exec postgres psql -U postgres -d pauta -c "INSERT INTO cupons (codigo, tipo, valor) VALUES ('bemvindo10', 'percentual', 5);"
docker compose exec postgres psql -U postgres -d pauta -c "INSERT INTO cupons (codigo, tipo, valor) VALUES ('ERRO', 'percentual', 150);"
docker compose exec postgres psql -U postgres -d pauta -c "UPDATE assinaturas SET cupom_id = 99 WHERE id = 1;"
```

```
ERROR:  duplicate key value violates unique constraint "cupons_codigo_key"
DETAIL:  Key (codigo)=(bemvindo10) already exists.
ERROR:  new row for relation "cupons" violates check constraint "ck_cupons_percentual_max"
DETAIL:  Failing row contains (35, ERRO, percentual, 150, 1, null, null).
ERROR:  insert or update on table "assinaturas" violates foreign key constraint "assinaturas_cupom_id_fkey"
DETAIL:  Key (cupom_id)=(99) is not present in table "cupons".
```

| Teste | Regra que barrou |
| --- | --- |
| `bemvindo10` já existe como `BEMVINDO10` | `UNIQUE` + `citext` |
| Desconto de 150% | `ck_cupons_percentual_max` (aparece pelo nome) |
| Cupom 99 não existe | Chave estrangeira |

### Curiosidade: por que `id = 35` se só existem 3 cupons

Cada `INSERT`, **mesmo o que falha**, consome um número da sequência do `IDENTITY`, e esse consumo não é desfeito no rollback. É proposital: assim duas transações nunca disputam o mesmo número.

Por isso, buracos na numeração de IDs são normais no Postgres, e um ID nunca deve ser usado como contagem.

---

## 5. O histórico do Flyway e o erro de checksum

### O histórico

O Flyway registra cada migration aplicada em `flyway_schema_history`:

```bash
docker compose exec postgres psql -U postgres -d pauta -c "SELECT installed_rank, version, description, script, checksum, installed_on, execution_time, success FROM flyway_schema_history;"
```

Ou, de forma mais legível, pelo próprio Flyway:

```bash
docker compose run --rm flyway info
```

O `run --rm` cria um container temporário do serviço `flyway`, roda `info` no lugar do `migrate` e apaga o container no fim.

| Coluna | Para que serve |
| --- | --- |
| `version` | Ordem das migrations; é por ela que o Flyway sabe o que já rodou |
| `script` | Nome do arquivo |
| `checksum` | "Impressão digital" do conteúdo do arquivo no momento em que foi aplicado |
| `installed_on` | Quando foi aplicada (V1 e V2 têm datas diferentes) |
| `success` | Se terminou sem erro |

### Provocar o erro

**O que foi feito:** acrescentado um comentário na primeira linha do `V1__schema_inicial.sql`:

```sql
-- teste de checksum
```

E rodado de novo:

```bash
docker compose up flyway
```

```
pauta-flyway  | ERROR: Validate failed: Migrations have failed validation
pauta-flyway  | Migration checksum mismatch for migration version 1
pauta-flyway  | -> Applied to database : -231477694
pauta-flyway  | -> Resolved locally    : -1275817333
pauta-flyway  | Either revert the changes to the migration, or run repair to update the schema history.
pauta-flyway exited with code 1
```

- **Applied to database:** o checksum guardado quando a V1 foi aplicada.
- **Resolved locally:** o checksum do arquivo no disco agora, com o comentário.

O Flyway não sabe que foi só um comentário. Para ele, a V1 do disco não é mais a V1 que criou o banco. Se aceitasse, um banco novo criado do zero com o arquivo editado poderia ficar diferente deste, e ninguém perceberia.

### Com o erro, nada roda

O `migrate` tem duas etapas, nesta ordem:

1. **Validar:** compara as migrations já aplicadas com os arquivos (checksum, arquivos sumidos ou renomeados).
2. **Migrar:** aplica as pendentes.

Se a validação falha, o Flyway para ali: não abre transação, não roda SQL e não escreve no histórico. Se houvesse uma V3 pendente, ela também não teria rodado. Esse comportamento vem da opção `validateOnMigrate`, ligada por padrão.

### Desfazer

A linha foi apagada **à mão, no editor**, e o Flyway rodado de novo:

```
pauta-flyway  | Successfully validated 2 migrations (execution time 00:00.050s)
pauta-flyway  | Current version of schema "public": 2
pauta-flyway  | Schema "public" is up to date. No migration necessary.
pauta-flyway exited with code 0
```

O checksum voltou a bater, o banco está na V2 e não há nada pendente.

### E o `flyway repair`?

O próprio erro sugere `repair`: ele regrava o checksum do histórico com o valor do arquivo atual, ou seja, **aceita** a mudança. Existe para casos raros, como corrigir um comentário numa migration que comprovadamente não mudou o schema.

Usado sem cuidado, ele esconde exatamente a divergência que o checksum existe para detectar. A regra do projeto continua: **migration aplicada não se edita; correção entra como nova versão.**

---

## 6. Aprendizados

### O Postgres continua no ar quando o Flyway falha

No erro de checksum, só o container do Flyway saiu com código 1. O Postgres seguiu rodando, e um `docker compose up` completo também subiria o pgAdmin, que depende só do Postgres saudável.

Num projeto com aplicação, isso é um risco: ela subiria sobre um banco não migrado. A proteção é fazer a aplicação depender do Flyway terminar com sucesso:

```yaml
depends_on:
  flyway:
    condition: service_completed_successfully
```

### `down` sem `-v` preserva os dados

Entre um teste e outro, os containers foram removidos com `docker compose down` e recriados (`Container pauta-postgres Created` no log). Mesmo assim, o Flyway encontrou o histórico com a V1 e a V2 aplicadas: os dados vivem no **volume** `pgdata`, não no container.

| Comando | Containers | Volume (dados) |
| --- | --- | --- |
| `docker compose down` | Removidos | Mantido |
| `docker compose down -v` | Removidos | **Apagado** |

---

## Próximo passo

Os itens técnicos da v0.4.0 estão concluídos na [checklist](../checklist.md). Para fechar a versão, falta atualizar o README e o [modelo de dados](../modelo-de-dados.md) (V2 como feita, `codigo` do cupom como `citext`) e publicar a release v0.4.0.
