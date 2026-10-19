-- V4 PART-16 (portail partenaire validé, DEC-13) : invitation d'un membre
-- de l'équipe par e-mail. Un compte existant est rattaché tout de suite ;
-- sinon l'invitation attend et s'applique à la première connexion de
-- cette adresse. Rollback : DROP TABLE partner_invitations;
CREATE TABLE IF NOT EXISTS partner_invitations(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id UUID NOT NULL REFERENCES partner_organizations(id),
  email VARCHAR(254) NOT NULL,
  partner_role VARCHAR(32) NOT NULL CHECK (partner_role IN ('PARTNER_OWNER','PARTNER_STAFF','PARTNER_FINANCE')),
  status VARCHAR(16) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','ACCEPTED','REVOKED')),
  invited_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_partner_invitation_pending ON partner_invitations(partner_id, lower(email)) WHERE status='PENDING';
