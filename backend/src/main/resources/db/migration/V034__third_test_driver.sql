-- Third test account: chauffeur3@test.com / chauffeur3@12345
-- Same pattern as V030's chauffeur2 -- fully eligible driver
-- (status='ACTIVE', kyc_status='APPROVED', marketplace_enabled=true --
-- the real three-part condition DriverOpportunityController's own
-- eligibility check requires, confirmed there rather than assumed),
-- with a real vehicle so offer submission actually works end-to-end.
--
-- Password hash generated and round-trip-verified locally (bcrypt cost
-- 12, matching SecurityConfig.encoder() and every other seeded
-- account's own hashes) before being embedded here, not typed by hand.

INSERT INTO users(id,first_name,last_name,email,password_hash,status,email_verified_at)
VALUES (
  gen_random_uuid(),'Chauffeur3','Test','chauffeur3@test.com',
  '$2b$12$YxQ0qHQYCrAZ/rCU/085b.Cq6gMGc3fJJw4XZNzyS60DEWhrhQW02',
  'ACTIVE', now()
) ON CONFLICT (email) DO NOTHING;

INSERT INTO user_roles(user_id,role_id)
SELECT u.id, r.id FROM users u, roles r
WHERE u.email='chauffeur3@test.com' AND r.code='DRIVER'
ON CONFLICT DO NOTHING;

INSERT INTO drivers(id,user_id,status,kyc_status,marketplace_enabled)
SELECT gen_random_uuid(), u.id, 'ACTIVE', 'APPROVED', TRUE
FROM users u WHERE u.email='chauffeur3@test.com'
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO vehicles(id,driver_id,category_id,brand,model,year,plate_number,color,status)
SELECT gen_random_uuid(), d.id, c.id, 'Renault', 'Talisman', 2024, 'TEST-003-QA', 'Gris', 'ACTIVE'
FROM drivers d
JOIN users u ON u.id=d.user_id
JOIN vehicle_categories c ON c.code='STANDARD'
WHERE u.email='chauffeur3@test.com'
ON CONFLICT (plate_number) DO NOTHING;
