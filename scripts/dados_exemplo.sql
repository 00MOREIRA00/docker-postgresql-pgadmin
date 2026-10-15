-- Dados de exemplo: assinantes e assinaturas.
-- Não é migration: roda sob demanda e pode ser executado de novo (começa limpando as tabelas).

-- Limpeza e carga são atômicas: um erro desfaz também o TRUNCATE.
BEGIN;

TRUNCATE assinaturas, assinantes RESTART IDENTITY CASCADE;

-- 1. Assinantes, criados ao longo dos últimos 2 anos
INSERT INTO assinantes (nome, email, uf, cidade, data_nascimento, criado_em)
SELECT 'Assinante ' || n,
       'assinante' || n || '@exemplo.com',
       (ARRAY['SP', 'RJ', 'MG', 'RS', 'PR', 'BA', 'PE', 'CE'])[1 + n % 8],
       (ARRAY['São Paulo', 'Rio de Janeiro', 'Belo Horizonte', 'Porto Alegre',
              'Curitiba', 'Salvador', 'Recife', 'Fortaleza'])[1 + n % 8],
       date '1960-01-01' + (random() * 15000)::int,
       now() - random() * interval '730 days'
FROM generate_series(1, 500) AS n;

-- 2. Uma assinatura por assinante. O status depende de quando ele entrou,
--    e o fim do período depende do status e do plano.
INSERT INTO assinaturas (assinante_id, plano_id, status, iniciada_em, periodo_fim, cancelada_em, motivo)
SELECT s.assinante_id,
       s.plano_id,
       s.status,
       s.inicio,
       CASE s.status
           WHEN 'trial'        THEN s.inicio + 7                                           -- trial de 7 dias
           WHEN 'ativa'        THEN current_date + 1 + floor(random() * s.dias_ciclo)::int -- ciclo atual ainda vigente
           WHEN 'inadimplente' THEN GREATEST(s.inicio + 1,
                                             current_date - 1 - floor(random() * 30)::int) -- ciclo vencido
           ELSE                     s.inicio + s.dias_ciclo                                -- cancelada: 1º ciclo
       END,
       CASE WHEN s.status = 'cancelada'
            THEN LEAST(s.inicio + 1 + floor(random() * s.dias_ciclo)::int, current_date)::timestamptz
       END,
       CASE WHEN s.status = 'cancelada'
            THEN (ARRAY['preco', 'conteudo', 'pouco_uso', 'outro'])[1 + floor(random() * 4)::int]::motivo_cancelamento
       END
FROM (
    SELECT a.id AS assinante_id,
           p.id AS plano_id,
           a.criado_em::date AS inicio,
           CASE p.periodicidade WHEN 'anual' THEN 365 ELSE 30 END AS dias_ciclo,
           CASE
               WHEN a.criado_em > now() - interval '7 days' THEN 'trial'
               WHEN a.r < 0.75 THEN 'ativa'
               WHEN a.r < 0.85 THEN 'inadimplente'
               ELSE 'cancelada'
           END::status_assinatura AS status
    FROM (
        SELECT id, criado_em, random() AS r,
               (ARRAY['essencial', 'completo', 'completo_anual', 'familia'])[1 + floor(random() * 4)::int] AS plano
        FROM assinantes
    ) AS a
    JOIN planos p ON p.codigo = a.plano
) AS s;

COMMIT;
