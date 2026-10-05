-- Executado automaticamente apenas na primeira subida do container (volume vazio).
-- O schema da aplicação NÃO fica aqui: ele será versionado em migrations/ (Flyway).

-- Estatísticas de execução de consultas (requer shared_preload_libraries,
-- configurado no docker-compose.yml)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
