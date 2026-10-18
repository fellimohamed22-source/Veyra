-- V4 DR-01 (planche 13 P1, bouton « Disponible ») : le chauffeur choisit
-- de recevoir ou non les nouvelles demandes. Hors ligne, il ne reçoit
-- plus de demandes ni de notifications de nouvelle demande, mais garde
-- l'accès à ses courses confirmées.
ALTER TABLE drivers ADD COLUMN IF NOT EXISTS accepting_requests BOOLEAN NOT NULL DEFAULT TRUE;
