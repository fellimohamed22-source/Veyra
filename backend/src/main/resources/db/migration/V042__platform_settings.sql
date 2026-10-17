-- V4 L8/L9 : paramètres métier modifiables sans déploiement (DEC-09, DEC-10).
-- Valeurs numériques uniquement ; bornes contrôlées par l'API admin.
-- Les valeurs initiales reprennent l'existant (application.yml V3) et les
-- décisions du 17/10/2026 (rayon de prise en charge 200 m).
-- Rollback : DROP TABLE platform_settings;
CREATE TABLE platform_settings(
  setting_key VARCHAR(64) PRIMARY KEY,
  value_number BIGINT NOT NULL,
  min_value BIGINT NOT NULL,
  max_value BIGINT NOT NULL,
  description VARCHAR(300) NOT NULL,
  updated_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (min_value<=max_value AND value_number BETWEEN min_value AND max_value)
);

INSERT INTO platform_settings(setting_key,value_number,min_value,max_value,description) VALUES
 ('booking.min_lead_minutes',120,0,10080,'Délai minimum entre la publication et l''heure de prise en charge (DEC-09)'),
 ('booking.max_offer_window_hours',24,1,720,'Durée maximale de la fenêtre d''offres'),
 ('booking.normal_close_before_minutes',120,0,1440,'Clôture des offres avant la prise en charge (réservation ≥ 4 h à l''avance)'),
 ('booking.short_close_before_minutes',30,0,240,'Clôture des offres avant la prise en charge (réservation < 4 h à l''avance)'),
 ('ride.pickup_radius_meters',200,20,2000,'Distance maximale au point de prise en charge pour « Arrivé » et « Démarrer » (DEC-10)'),
 ('ride.location_max_age_seconds',120,10,900,'Âge maximal de la dernière position suivie utilisée à défaut de position transmise')
ON CONFLICT (setting_key) DO NOTHING;
