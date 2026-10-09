# 03 — Evoluir o schema com dados

Até aqui, toda mudança no banco foi feita **editando o V1 e apagando o banco** com `docker compose down -v` (ver [02 — Primeira migration (V1)](02%20-%20migration.md)). Isso só funciona porque o banco ainda era descartável.

Esta etapa faz o contrário: muda o schema de um banco que **já tem dados**, sem apagar nada. É para isso que o Flyway existe.

Itens da [checklist](../checklist.md) (v0.4.0):

- Script `scripts/dados_exemplo.sql` com `generate_series`: assinantes e assinaturas de exemplo
- Migration `V2__cupons.sql`: tabela `cupons` e coluna `cupom_id` em `assinaturas`
- Aplicar a V2 com `docker compose up` (sem `down -v`) e confirmar que os dados continuam lá
- Ver as duas versões na `flyway_schema_history` e provocar o erro de checksum editando o V1

---
