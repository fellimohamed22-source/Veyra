-- VTC companies (SOC-01..10) and affiliated drivers (DR-AFF-01..07).
-- A company manages its fleet, its operating documents and the drivers
-- attached to it; VEYRA approval of the company, of each vehicle and of
-- each driver is still required before any marketplace access.
-- Rollback : DROP TABLE company_invitations, company_affiliations, company_documents, company_members;
--            ALTER TABLE vehicles DROP COLUMN company_id; DROP TABLE vtc_companies;

CREATE TABLE vtc_companies(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_name VARCHAR(180) NOT NULL,
  siren VARCHAR(9) NOT NULL UNIQUE,
  revtc_number VARCHAR(32),
  address VARCHAR(255),
  contact_email VARCHAR(254),
  status VARCHAR(16) NOT NULL DEFAULT 'DRAFT',
  invite_code VARCHAR(16) NOT NULL UNIQUE,
  rejection_reason_code VARCHAR(64),
  created_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT vtc_companies_status_chk CHECK (status IN ('DRAFT','SUBMITTED','APPROVED','REJECTED','SUSPENDED')),
  CONSTRAINT vtc_companies_siren_chk CHECK (siren ~ '^[0-9]{9}$')
);

CREATE TABLE company_members(
  company_id UUID NOT NULL REFERENCES vtc_companies(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id),
  company_role VARCHAR(24) NOT NULL DEFAULT 'COMPANY_OWNER',
  status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(company_id,user_id),
  CONSTRAINT company_members_role_chk CHECK (company_role IN ('COMPANY_OWNER','COMPANY_MANAGER')),
  CONSTRAINT company_members_status_chk CHECK (status IN ('ACTIVE','INACTIVE'))
);

-- Fleet vehicles belong to the company; driver_id is the driver the
-- vehicle is currently assigned to (null while unassigned).
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES vtc_companies(id);
ALTER TABLE vehicles ALTER COLUMN driver_id DROP NOT NULL;
ALTER TABLE vehicles ADD CONSTRAINT vehicles_owner_chk CHECK (driver_id IS NOT NULL OR company_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS vehicles_company_idx ON vehicles(company_id) WHERE company_id IS NOT NULL;

-- Operating documents (company) and vehicle documents (vehicle_id set).
CREATE TABLE company_documents(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES vtc_companies(id),
  vehicle_id UUID REFERENCES vehicles(id),
  type VARCHAR(48) NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'SUBMITTED',
  storage_key VARCHAR(512) NOT NULL,
  original_filename VARCHAR(255),
  content_type VARCHAR(120),
  expires_at DATE,
  rejection_reason_code VARCHAR(64),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT company_documents_status_chk CHECK (status IN ('SUBMITTED','APPROVED','REJECTED','SUPERSEDED'))
);
CREATE INDEX company_documents_company_idx ON company_documents(company_id);
CREATE INDEX company_documents_vehicle_idx ON company_documents(vehicle_id) WHERE vehicle_id IS NOT NULL;

CREATE TABLE company_affiliations(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES vtc_companies(id),
  driver_id UUID NOT NULL REFERENCES drivers(id),
  status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at TIMESTAMPTZ,
  decided_by UUID REFERENCES users(id),
  CONSTRAINT company_affiliations_status_chk CHECK (status IN ('PENDING','ACTIVE','REJECTED','ENDED'))
);
-- A driver belongs to at most one company at a time.
CREATE UNIQUE INDEX company_affiliations_open_uq ON company_affiliations(driver_id) WHERE status IN ('PENDING','ACTIVE');
CREATE INDEX company_affiliations_company_idx ON company_affiliations(company_id);

CREATE TABLE company_invitations(
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES vtc_companies(id),
  email VARCHAR(254) NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
  invited_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT company_invitations_status_chk CHECK (status IN ('PENDING','ACCEPTED','REVOKED'))
);
CREATE UNIQUE INDEX company_invitations_pending_uq ON company_invitations(company_id, lower(email)) WHERE status='PENDING';

INSERT INTO roles(code,name) VALUES ('COMPANY_OWNER','Société VTC') ON CONFLICT DO NOTHING;
