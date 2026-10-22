-- Owner request 22/10/2026: test account chauffeur2@test.com drives an
-- approved STANDARD vehicle. V030 created its Peugeot 508 with status
-- 'ACTIVE', which offers and the ride screens do not treat as approved
-- (they require 'APPROVED'), so the vehicle never showed up.
-- Idempotent; does nothing when the test account does not exist.
-- Rollback : UPDATE vehicles SET status='ACTIVE' WHERE plate_number='TEST-002-QA';

INSERT INTO vehicles(id,driver_id,category_id,brand,model,year,plate_number,color,status,seats,baggage_capacity)
SELECT gen_random_uuid(), d.id, c.id, 'Peugeot', '508', 2023, 'TEST-002-QA', 'Noir', 'APPROVED', 4, 3
FROM drivers d
JOIN users u ON u.id=d.user_id
JOIN vehicle_categories c ON c.code='STANDARD'
WHERE u.email='chauffeur2@test.com'
ON CONFLICT (plate_number) DO NOTHING;

UPDATE vehicles v
SET status='APPROVED',
    category_id=(SELECT id FROM vehicle_categories WHERE code='STANDARD'),
    seats=COALESCE(v.seats,4),
    baggage_capacity=COALESCE(v.baggage_capacity,3)
FROM drivers d JOIN users u ON u.id=d.user_id
WHERE v.driver_id=d.id AND u.email='chauffeur2@test.com' AND v.plate_number='TEST-002-QA';
