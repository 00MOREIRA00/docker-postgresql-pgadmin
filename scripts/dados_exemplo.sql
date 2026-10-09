-- Dados de exemplo: assinantes e assinaturas.
-- Não é migration: roda sob demanda e pode ser executado de novo (começa limpando as tabelas).

TRUNCATE assinaturas, assinantes RESTART IDENTITY CASCADE;

INSERT INTO assinantes (nome, email, uf, cidade, data_nascimento, criado_em)
SELECT 'Assinante ' || n,
       'assinante' || n || '@exemplo.com',
       (ARRAY['SP', 'RJ', 'MG', 'RS', 'PR', 'BA', 'PE', 'CE'])[1 + n % 8],
       (ARRAY['São Paulo', 'Rio de Janeiro', 'Belo Horizonte', 'Porto Alegre',
              'Curitiba', 'Salvador', 'Recife', 'Fortaleza'])[1 + n % 8],
       date '1960-01-01' + (random() * 15000)::int,
       now() - random() * interval '730 days'
FROM generate_series(1, 500) AS n;

INSERT INTO assinaturas (assinante_id, plano_id, status, iniciada_em, periodo_fim, cancelada_em, motivo)
SELECT b.assinante_id,
       p.id,
       b.status,
       b.inicio,
       b.inicio + 30,
       CASE WHEN b.status = 'cancelada' THEN b.inicio + interval '20 days' END,
       CASE WHEN b.status = 'cancelada'
            THEN (ARRAY['preco', 'conteudo', 'pouco_uso', 'outro'])[1 + floor(random() * 4)::int]::motivo_cancelamento
       END
FROM (
    SELECT id AS assinante_id,
           criado_em::date AS inicio,
           (ARRAY['essencial', 'completo', 'completo_anual', 'familia'])[1 + floor(random() * 4)::int] AS plano,
           CASE
               WHEN r < 0.10 THEN 'trial'
               WHEN r < 0.70 THEN 'ativa'
               WHEN r < 0.80 THEN 'inadimplente'
               ELSE 'cancelada'
           END::status_assinatura AS status
    FROM (SELECT id, criado_em, random() AS r FROM assinantes) AS sorteio
) AS b
JOIN planos p ON p.codigo = b.plano;
