# Checklist de desenvolvimento

Foco do projeto: **Docker + PostgreSQL + migrations com Flyway**. Marque `[x]` conforme for concluindo e faça commit junto com a mudança correspondente.

Referências: [caso de negócio](caso-de-negocio.md) · [modelo de dados](modelo-de-dados.md) · [decisões](decisoes.md)

| Versão | Escopo | Status |
|--------|--------|--------|
| v0.1.0 | Versão original | ✅ Publicada |
| v0.2.0 | Correções da base | ✅ Publicada |
| v0.3.0 | Flyway e schema inicial | Publicada |
| v0.4.0 | Evoluir o schema com dados | ⬜ A fazer |
| v1.0.0 | Backup e fechamento | ⬜ A fazer |

---

## Pendências da v0.2.0

- [ ] Decidir o destino da pasta `wiki/` no repositório principal: remover (`git rm -r wiki`) ou manter como cópia da wiki
- [x] Trocar *a publicar* pela data nas páginas **Histórico de versões** e **v0.2.0 Correções da base** da wiki

---

## v0.3.0 — Flyway e schema inicial

- [x] Serviço `flyway` no compose, com versão fixa, pasta `migrations/` montada e credenciais do `.env`
- [x] Migration `V1__schema_inicial.sql`: extensão, ENUMs, tabelas, constraints, índice parcial e carga dos planos e publicações
- [x] Testar as constraints: inserir dados inválidos e confirmar o erro
- [x] `docker compose down -v && docker compose up -d` sobe tudo do zero
- [x] Atualizar o README e o `docs/modelo-de-dados.md` com o novo escopo
- [x] Release v0.3.0

---

## v0.4.0 — Evoluir o schema com dados

A lição central do Flyway: mudar um banco que **já tem dados**, sem `down -v`.

- [ ] Script `scripts/dados_exemplo.sql` com `generate_series`: assinantes e assinaturas de exemplo
- [ ] Migration `V2__cupons.sql`: tabela `cupons` e coluna `cupom_id` em `assinaturas`
- [ ] Aplicar a V2 com `docker compose up` (sem `down -v`) e confirmar que os dados continuam lá
- [ ] Ver as duas versões na `flyway_schema_history` e provocar o erro de checksum editando o V1
- [ ] Release v0.4.0

---

## v1.0.0 — Backup e fechamento

- [ ] Backup do banco com `pg_dump`
- [ ] Restore num banco limpo com `pg_restore` e conferir os dados
- [ ] README final: remover o aviso "em construção"
- [ ] Release v1.0.0

---

**Fora do escopo:** script Python, faturamento e auditoria (triggers e views), consultas analíticas, performance e roles/RLS. Ficam como ideias para depois, se fizer sentido.
