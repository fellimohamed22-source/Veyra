-- Second pair of test accounts, deliberately different in purpose from
-- V029's: client@test.com/chauffeur@test.com test the real KYC-gated
-- path (driver left PENDING_KYC/marketplace_enabled=false on purpose,
-- as documented there). These two are meant to navigate the entire app
-- end-to-end during testing, so the driver here is made genuinely
-- eligible -- the real gate, confirmed directly in
-- DriverOpportunityController, requires all three of status='ACTIVE',
-- kyc_status='APPROVED', and marketplace_enabled=true together, not
-- marketplace_enabled alone.
--
-- Passwords hashed with bcrypt cost 12 (matching SecurityConfig.encoder()
-- and V029's own hashes), generated and round-trip-verified locally
-- before being embedded here, not typed by hand:
--   client2@test.com    / Client2@12345
--   chauffeur2@test.com / Chauffeur2@12345

INSERT INTO users(id,first_name,last_name,email,password_hash,status,email_verified_at)
VALUES (
  gen_random_uuid(),'Client2','Test','client2@test.com',
  '$2b$12$NGdMVgUWP363W6hYNKKlLutV8M7AyniIiwujHL7TqEXEYKEc2fFpq',
  'ACTIVE', now()
) ON CONFLICT (email) DO NOTHING;

INSERT INTO users(id,first_name,last_name,email,password_hash,status,email_verified_at)
VALUES (
  gen_random_uuid(),'Chauffeur2','Test','chauffeur2@test.com',
  '$2b$12$d/jC/i9KVX9aN7st/xIs9uQRBWYSxTygrVJGKn2J5GUgnK49NPuLS',
  'ACTIVE', now()
) ON CONFLICT (email) DO NOTHING;

INSERT INTO user_roles(user_id,role_id)
SELECT u.id, r.id FROM users u, roles r
WHERE u.email='client2@test.com' AND r.code='CLIENT'
ON CONFLICT DO NOTHING;

INSERT INTO user_roles(user_id,role_id)
SELECT u.id, r.id FROM users u, roles r
WHERE u.email='chauffeur2@test.com' AND r.code='DRIVER'
ON CONFLICT DO NOTHING;

-- Fully eligible driver: ACTIVE + APPROVED + marketplace_enabled, the
-- real three-part condition DriverOpportunityController checks -- not
-- just flipping one flag and assuming it's enough.
INSERT INTO drivers(id,user_id,status,kyc_status,marketplace_enabled)
SELECT gen_random_uuid(), u.id, 'ACTIVE', 'APPROVED', TRUE
FROM users u WHERE u.email='chauffeur2@test.com'
ON CONFLICT (user_id) DO NOTHING;

-- A real vehicle, referencing the actual seeded STANDARD category by its
-- real id rather than a hardcoded UUID guessed at -- submitting an offer
-- requires a vehicle to exist for this driver at all.
INSERT INTO vehicles(id,driver_id,category_id,brand,model,year,plate_number,color,status)
SELECT gen_random_uuid(), d.id, c.id, 'Peugeot', '508', 2023, 'TEST-002-QA', 'Noir', 'ACTIVE'
FROM drivers d
JOIN users u ON u.id=d.user_id
JOIN vehicle_categories c ON c.code='STANDARD'
WHERE u.email='chauffeur2@test.com'
ON CONFLICT (plate_number) DO NOTHING;
