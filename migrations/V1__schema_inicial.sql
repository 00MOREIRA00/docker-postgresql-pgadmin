CREATE EXTENSION IF NOT EXISTS citext;

CREATE TYPE periodicidade AS ENUM ('mensal', 'anual');

CREATE TYPE tipo_publicacao AS ENUM ('revista', 'newsletter');

CREATE TYPE status_assinatura AS ENUM ('trial', 'ativa', 'inadimplente', 'cancelada');

CREATE TYPE motivo_cancelamento AS ENUM ('preco', 'conteudo', 'pouco_uso', 'inadimplencia', 'trial_nao_convertido', 'outro');

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

CREATE UNIQUE INDEX uq_assinaturas_ativa_por_assinante
    ON assinaturas (assinante_id)
    WHERE status <> 'cancelada';

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
