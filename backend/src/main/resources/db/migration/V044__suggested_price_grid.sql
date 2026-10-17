-- V4 L14 (DEC-18) : grille de prix conseillé, une ligne par catégorie de
-- véhicule. Les montants sont des PRIX NETS CHAUFFEUR (méthode A : le
-- chauffeur saisit son net, la commission s'ajoute ensuite). Aucune valeur
-- n'est fournie : la grille est renseignée par le propriétaire via l'API
-- admin ; sans ligne pour une catégorie, aucun prix conseillé n'est affiché.
-- Prix central = max(minimum, prise en charge + €/km × km + €/min × min),
-- fourchette = central ± spread_bps.
-- Rollback : DROP TABLE suggested_price_grid;
CREATE TABLE suggested_price_grid(
  category_id UUID PRIMARY KEY REFERENCES vehicle_categories(id),
  base_minor BIGINT NOT NULL CHECK (base_minor>=0),
  per_km_minor BIGINT NOT NULL CHECK (per_km_minor>=0),
  per_minute_minor BIGINT NOT NULL CHECK (per_minute_minor>=0),
  minimum_minor BIGINT NOT NULL DEFAULT 0 CHECK (minimum_minor>=0),
  spread_bps INT NOT NULL DEFAULT 1000 CHECK (spread_bps BETWEEN 0 AND 5000),
  currency CHAR(3) NOT NULL DEFAULT 'EUR',
  active BOOLEAN NOT NULL DEFAULT TRUE,
  updated_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
