# 04 — Backup e restore

Com o schema evoluindo sem perder dados (ver [03 — Evoluir o schema com dados](03%20-%20evoluir%20o%20schema.md)), falta a última garantia: conseguir **salvar o banco e recuperá-lo**.

Um backup só vale alguma coisa se o restore funcionar. Por isso esta etapa não termina no `pg_dump`: o backup é restaurado num banco novo e comparado com o original.

Itens da [checklist](../checklist.md) (v1.0.0):

- Backup do banco com `pg_dump`
- Restore num banco limpo com `pg_restore` e conferir os dados

---

## 1. Fazer o backup

**O que foi feito:**

```bash
mkdir -p backups
docker compose exec -T postgres pg_dump -U postgres -d pauta -Fc > backups/pauta_$(date +%Y%m%d_%H%M).dump
```

| Parte | Significado |
| --- | --- |
| `pg_dump` | Gera uma cópia **lógica** do banco: estrutura e dados, como instruções para recriá-los |
| `-Fc` | Formato *custom*: binário, compactado, e permite restaurar só partes do banco |
| `-T` | Desliga o terminal interativo do `exec`. Obrigatório quando a saída vai para um arquivo: sem ele, o Docker pode corromper os bytes do dump |
| `> backups/...` | O dump sai do container direto para a pasta do projeto |
| `$(date +%Y%m%d_%H%M)` | Data e hora no nome do arquivo: `pauta_20261014_1547.dump` |

Resultado: um arquivo de **39 KB** com 500 assinantes, 500 assinaturas e o schema inteiro.

### O problema que aconteceu: a pasta não existia

A primeira tentativa rodou só a linha do `pg_dump`:

```
-bash: backups/pauta_20261014_1544.dump: No such file or directory
```

O redirecionamento `>` cria o **arquivo**, mas não cria **pastas**. Faltava o `mkdir -p backups`. O `-p` faz o comando não reclamar se a pasta já existir, então pode ficar sempre antes do backup.

### Por que o `pg_dump` roda dentro do container

O `pg_dump` precisa ser da mesma versão do servidor, ou mais nova. Rodando **dentro** do container, as versões sempre batem: o próprio dump registra `Dumped from database version: 18.6` e `Dumped by pg_dump version: 18.6`. Um `pg_dump` mais antigo instalado na máquina poderia recusar o servidor 18.

### Formato custom ou SQL puro

| `-Fc` (custom) | Sem `-F` (SQL puro) |
| --- | --- |
| Binário e compactado (gzip) | Texto legível |
| Restaurado com `pg_restore` | Restaurado com `psql -f` |
| Permite restaurar só uma tabela, listar o conteúdo, restaurar em paralelo | Só restaura inteiro |

O SQL puro é útil para ler ou comparar. Para backup de verdade, o padrão é o custom.

### Backup não vai para o git

A pasta `backups/` está no `.gitignore` desde a v0.2.0. Um dump contém **todos os dados** do banco; num sistema real, isso inclui e-mails e dados pessoais de clientes.

---

## 2. Ver o que tem dentro do backup

```bash
ARQ=$(ls -t backups/*.dump | head -1)
docker compose exec -T postgres pg_restore -l < "$ARQ" | head -40
```

- `ls -t ... | head -1` pega o dump mais recente e guarda o caminho na variável `ARQ`.
- `pg_restore -l` lista o índice (*TOC*, *table of contents*) do arquivo **sem restaurar nada**.

Cabeçalho obtido:

```
;     dbname: pauta
;     TOC Entries: 61
;     Compression: gzip
;     Format: CUSTOM
;     Dumped from database version: 18.6 (Debian 18.6-1.pgdg13+2)
;     Dumped by pg_dump version: 18.6 (Debian 18.6-1.pgdg13+2)
```

E o índice, na ordem em que o restore recria os objetos:

| Ordem | Objetos | Por quê |
| --- | --- | --- |
| 1 | `EXTENSION` (`citext`, `pg_stat_statements`) | As tabelas dependem delas |
| 2 | `TYPE` (os 5 ENUMs, incluindo `tipo_desconto` da V2) | As colunas dependem deles |
| 3 | `TABLE` e `SEQUENCE` | Incluindo a `flyway_schema_history` |
| 4 | `TABLE DATA` | Os dados de cada tabela |
| 5 | Constraints, índices, FKs e valores das sequências | Por último, para os dados entrarem sem checar a ordem entre tabelas |

**A `flyway_schema_history` está no backup.** O histórico de migrations viaja junto com os dados.

---

## 3. Restaurar num banco limpo

```bash
docker compose exec postgres createdb -U postgres pauta_restore
docker compose exec -T postgres pg_restore -U postgres -d pauta_restore --no-owner --exit-on-error < "$ARQ"
```

| Opção | Por quê |
| --- | --- |
| `createdb` | O `pg_restore` restaura **dentro** de um banco existente; é preciso criar um vazio antes |
| `--no-owner` | Não tenta recriar o dono original de cada objeto. Evita erro quando o usuário do destino é outro |
| `--exit-on-error` | Para no primeiro erro (como o `ON_ERROR_STOP` do `psql`). Sem ele, o restore segue e o banco pode ficar pela metade sem ninguém perceber |

Sem mensagem de saída: o restore funcionou.

### Por que um banco separado

O restore foi feito no `pauta_restore`, no mesmo servidor, e não por cima do `pauta`. Assim o original nunca corre risco: se o backup estivesse com problema, nada seria perdido.

---

## 4. Conferir os dados restaurados

Contar linhas não basta: dois bancos podem ter 500 assinaturas cada e conteúdos diferentes. A consulta também calcula uma **impressão digital** (`md5`) de todas as assinaturas. Se um único campo de uma única linha mudar, o resultado muda.

Esta conferência é parcial: compara contagens de três tabelas e o conteúdo de `assinaturas`. Não comprova igualdade do conteúdo das demais tabelas, das sequências ou de toda a estrutura. Faça a comparação sem escritas concorrentes e com as mesmas configurações de sessão, incluindo fuso horário, para manter a representação textual estável.

```bash
Q="SELECT (SELECT count(*) FROM assinantes) AS assinantes,
          (SELECT count(*) FROM assinaturas) AS assinaturas,
          (SELECT count(*) FROM cupons) AS cupons,
          (SELECT md5(string_agg(a::text, ',' ORDER BY a.id)) FROM assinaturas a) AS impressao_digital;"

for db in pauta pauta_restore; do
  echo "== $db"
  docker compose exec postgres psql -U postgres -d $db -c "$Q"
done
```

Como a impressão digital é montada:

- `a::text` transforma cada linha inteira da tabela em texto: `(1,1,3,ativa,2025-03-02,...)`.
- `string_agg(..., ',' ORDER BY a.id)` junta todas as linhas num único texto, **sempre na mesma ordem**. Sem o `ORDER BY`, a ordem poderia variar e o `md5` mudaria mesmo com os dados iguais.
- `md5(...)` resume esse texto num código de 32 caracteres.

Resultado obtido:

```
== pauta
 assinantes | assinaturas | cupons |        impressao_digital
------------+-------------+--------+----------------------------------
        500 |         500 |      3 | 3e2f8562d387aa5b0152c12ac7563c69

== pauta_restore
 assinantes | assinaturas | cupons |        impressao_digital
------------+-------------+--------+----------------------------------
        500 |         500 |      3 | 3e2f8562d387aa5b0152c12ac7563c69
```

Impressões digitais idênticas: o conteúdo das 500 assinaturas é o mesmo, campo a campo.

### O Flyway reconhece o banco restaurado

```bash
docker compose run --rm -e FLYWAY_URL=jdbc:postgresql://postgres:5432/pauta_restore flyway info
```

O `-e FLYWAY_URL=...` aponta o Flyway para o `pauta_restore` só nesta execução, sem mudar o compose.

```
Schema version: 2

+-----------+---------+----------------+------+---------------------+---------+----------+
| Category  | Version | Description    | Type | Installed On        | State   | Undoable |
+-----------+---------+----------------+------+---------------------+---------+----------+
| Versioned | 1       | schema inicial | SQL  | 2026-10-14 15:38:39 | Success | No       |
| Versioned | 2       | cupons         | SQL  | 2026-10-14 15:46:43 | Success | No       |
+-----------+---------+----------------+------+---------------------+---------+----------+
```

As datas de instalação são as **originais**, de quando cada migration rodou no `pauta`. Se o banco restaurado virasse o principal, o Flyway continuaria a partir da V3, sem reaplicar nada.

---

## 5. Limpar

```bash
docker compose exec postgres dropdb -U postgres pauta_restore
```

O arquivo em `backups/` fica na máquina, fora do git.

---

## Aprendizados

- **Backup sem restore testado não é backup.** O `pg_dump` terminar sem erro não prova que o arquivo serve para alguma coisa.
- **Contagem não prova igualdade.** A impressão digital com `md5` compara o conteúdo, não só a quantidade.
- **O histórico de migrations faz parte do banco.** Restaurar o dump restaura também a versão do schema que o Flyway enxerga.
- **`-T` em todo `exec` com redirecionamento** (`<` ou `>`): sem ele, o terminal interativo pode alterar os bytes no caminho.

---

## Próximo passo

Para executar backup e restore no Windows PowerShell sem redirecionar bytes binários, consulte a alternativa com `pg_dump -f` e `docker compose cp` no [README](../../README.md#windows-powershell).

Com o backup e o restore validados e o README atualizado, falta só a release v1.0.0 na [checklist](../checklist.md).
