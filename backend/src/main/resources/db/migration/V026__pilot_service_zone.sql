DO $$
DECLARE
  zone_uuid UUID;
BEGIN
  SELECT id INTO zone_uuid
  FROM service_zones
  WHERE code='FR_SOUTH_COAST_MARSEILLE_MENTON';

  IF zone_uuid IS NULL THEN
    INSERT INTO service_zones(id,code,name,status)
    VALUES (
      gen_random_uuid(),
      'FR_SOUTH_COAST_MARSEILLE_MENTON',
      'Zone pilote Marseille - Menton',
      'ACTIVE'
    )
    RETURNING id INTO zone_uuid;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM service_zone_versions
    WHERE zone_id=zone_uuid AND status='ACTIVE'
  ) THEN
    INSERT INTO service_zone_versions(
      zone_id,
      polygon,
      effective_from,
      status
    )
    VALUES (
      zone_uuid,
      ST_GeogFromText(
        'SRID=4326;POLYGON((' ||
        '5.00 42.95,' ||
        '5.00 43.80,' ||
        '5.70 43.95,' ||
        '6.40 44.15,' ||
        '7.10 44.20,' ||
        '7.70 44.05,' ||
        '7.70 43.45,' ||
        '7.10 43.25,' ||
        '6.20 43.05,' ||
        '5.00 42.95' ||
        '))'
      ),
      now(),
      'ACTIVE'
    );
  END IF;
END $$;
