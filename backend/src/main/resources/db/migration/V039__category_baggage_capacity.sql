-- V4 L3 : capacité bagages par catégorie de véhicule (CL-04, BOOK
-- "places/bagages insuffisants"). Aucune valeur n'est inventée ici : la
-- colonne reste NULL (= non contrôlée) tant que l'administration n'a pas
-- validé les capacités par catégorie. Les valeurs des maquettes sont
-- illustratives et ne font pas foi.
-- Rollback : ALTER TABLE vehicle_categories DROP COLUMN baggage_capacity;
ALTER TABLE vehicle_categories
  ADD COLUMN IF NOT EXISTS baggage_capacity SMALLINT CHECK (baggage_capacity BETWEEN 0 AND 12);
