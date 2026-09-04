INSERT INTO service_zones(code,name,status)
VALUES ('PILOT_MARSEILLE_MENTON','Zone pilote Marseille → Menton','ACTIVE')
ON CONFLICT(code) DO NOTHING;

INSERT INTO service_zone_versions(zone_id,polygon,effective_from,status)
SELECT z.id,
       ST_MakeEnvelope(5.20,43.00,7.60,43.90,4326)::geography,
       now(),
       'ACTIVE'
FROM service_zones z
WHERE z.code='PILOT_MARSEILLE_MENTON'
  AND NOT EXISTS (
    SELECT 1 FROM service_zone_versions v
    WHERE v.zone_id=z.id AND v.status='ACTIVE'
  );
