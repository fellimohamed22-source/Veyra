-- V4 L10 (DEC-04 : carte enregistrée, débit à la réservation) : lien entre
-- un utilisateur VEYRA et son client chez le PSP. Les données de carte
-- restent chez Stripe (jamais de PAN côté VEYRA) ; seule la référence du
-- client Stripe est conservée.
-- Rollback : DROP TABLE payment_customers;
CREATE TABLE payment_customers(
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  provider VARCHAR(32) NOT NULL DEFAULT 'STRIPE',
  provider_customer_id VARCHAR(128) NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
