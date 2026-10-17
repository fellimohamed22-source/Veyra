-- V4 L4 (CL-AUTH / RGPD) : journal des consentements. Append-only : un
-- retrait est une nouvelle ligne granted=false, l'historique n'est jamais
-- réécrit (preuve du consentement). CGU et confidentialité sont requises
-- à l'inscription ; le marketing est facultatif et distinct.
-- document_version = version du texte accepté (veyra.legal.*-version) ;
-- les textes eux-mêmes restent soumis à validation juridique (DEC-14).
-- Rollback : DROP TABLE user_consents;
CREATE TABLE user_consents(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  consent_type VARCHAR(24) NOT NULL CHECK (consent_type IN ('TERMS','PRIVACY','MARKETING')),
  granted BOOLEAN NOT NULL,
  document_version VARCHAR(40) NOT NULL,
  source VARCHAR(32) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_user_consents_user_type ON user_consents(user_id,consent_type,created_at DESC);
