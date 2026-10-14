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