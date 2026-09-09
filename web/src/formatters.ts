// Formatters partagés -- même principe que le design system Flutter
// (mobile-client/mobile-driver core/formatters/) : aucun enum backend,
// aucune date ISO, aucun montant calculé manuellement affiché brut à
// l'écran (CLAUDE_GUARDRAILS.md).

const BOOKING_STATUS_FR: Record<string,string> = {
  OPEN_FOR_OFFERS: 'Demande publiée',
  OFFERS_RECEIVED: 'Offres reçues',
  CONFIRMED: 'Réservation confirmée',
  DRIVER_EN_ROUTE: 'Chauffeur en route',
  DRIVER_ARRIVED: 'Chauffeur arrivé',
  IN_PROGRESS: 'Course en cours',
  COMPLETED: 'Terminée',
  CLOSED: 'Terminée',
  CANCELLED: 'Annulée',
  CANCELLED_BY_CLIENT: 'Annulée',
  CANCELLED_BY_DRIVER: 'Annulée par le chauffeur',
  CUSTOMER_NO_SHOW: 'Client absent',
  EXPIRED: 'Demande expirée',
  NO_OFFER: 'Aucune offre reçue',
  NO_DRIVER: 'Aucune offre reçue',
};

const PAYMENT_METHOD_FR: Record<string,string> = {
  CASH: 'Espèces',
  ONLINE: 'Paiement en ligne',
  PARTNER_INVOICE: 'Facturation partenaire',
};

const PARTNER_ORG_STATUS_FR: Record<string,string> = {
  PENDING: 'En attente de validation',
  ACTIVE: 'Actif',
  SUSPENDED: 'Suspendu',
  REJECTED: 'Refusé',
};

const KYC_STATUS_FR: Record<string,string> = {
  DRAFT: 'Dossier à compléter',
  SUBMITTED: 'Vérification en cours',
  APPROVED: 'Dossier approuvé',
  REJECTED: 'Dossier refusé',
};

// Seules deux valeurs sont réellement posées dans le code
// (PartnerInvoiceController) : DRAFT (défaut schéma) et ISSUED (à la
// génération). Pas de transition PAID/OVERDUE implémentée à ce jour --
// ne pas en inventer le libellé.
const INVOICE_STATUS_FR: Record<string,string> = {
  DRAFT: 'Brouillon',
  ISSUED: 'Émise',
};

// Mêmes 5 types et même wording que mobile-driver/lib/main.dart (écran
// KYC) -- vérifiés dans ce fichier avant d'écrire cette liste, pas
// devinés.
const DOCUMENT_TYPE_FR: Record<string,string> = {
  IDENTITY: "Pièce d'identité",
  VTC_CARD: 'Carte professionnelle VTC',
  DRIVING_LICENSE: 'Permis de conduire',
  INSURANCE: 'Assurance professionnelle / véhicule',
  VEHICLE_REGISTRATION: 'Carte grise du véhicule',
};

// 19 codes officiels de 10_ANTI_ERROR_PROTOCOL/ERROR_MAPPING.md, wording
// identique à celui utilisé côté Flutter (core/formatters/error_messages.dart),
// plus les codes réels rencontrés en pratique et vérifiés dans le backend.
const ERROR_MESSAGES_FR: Record<string,string> = {
  LEAD_TIME_TOO_SHORT: "Choisissez un départ au moins 2 heures à l'avance.",
  PICKUP_OUTSIDE_SERVICE_ZONE: "Cette adresse de départ est hors de la zone pilote actuelle (Sud de la France, Marseille - Menton).",
  OFFERS_CLOSED: "Cette demande n'accepte plus de nouvelles offres.",
  BOOKING_OFFERS_CLOSED: "Cette demande n'accepte plus de nouvelles offres.",
  ACTIVE_OFFER_EXISTS: 'Une offre active existe déjà pour cette demande.',
  BOOKING_CLOSED: 'Cette réservation a déjà été mise à jour.',
  OFFER_CLOSED: "Cette offre n'est plus disponible. Actualisez la liste.",
  PARTNER_CREDIT_LIMIT_EXCEEDED: 'Le plafond de facturation du partenaire est atteint.',
  PARTNER_SCOPE_FORBIDDEN: "Vous n'avez pas accès à ce compte partenaire.",
  PARTNER_INVOICE_NOT_ELIGIBLE: 'La facturation partenaire n’est pas disponible pour ce compte.',
  NOT_SELECTED_DRIVER: "Cette réservation n'est pas attribuée à ce compte.",
  INVALID_BOOKING_TRANSITION: "Cette action n'est plus disponible dans l'état actuel.",
  CANNOT_CANCEL: 'Cette réservation ne peut plus être annulée dans son état actuel.',
  EMAIL_ALREADY_USED: 'Un compte existe déjà avec cet email.',
  INVALID_CREDENTIALS: 'Email ou mot de passe incorrect.',
  ACCOUNT_LOCKED: 'Compte temporairement verrouillé. Réessayez plus tard.',
  ACCOUNT_NOT_ACTIVE: "Ce compte n'est pas actif. Contactez le support.",
};

export function statusLabel(code: string|null|undefined): string {
  if (!code) return '—';
  return BOOKING_STATUS_FR[code] ?? 'Mise à jour du statut';
}

export function paymentMethodLabel(code: string|null|undefined): string {
  if (!code) return '—';
  return PAYMENT_METHOD_FR[code] ?? code;
}

export function partnerOrgStatusLabel(code: string|null|undefined): string {
  if (!code) return '—';
  return PARTNER_ORG_STATUS_FR[code] ?? code;
}

export function kycStatusLabel(code: string|null|undefined): string {
  if (!code) return '—';
  return KYC_STATUS_FR[code] ?? code;
}

export function invoiceStatusLabel(code: string|null|undefined): string {
  if (!code) return '—';
  return INVOICE_STATUS_FR[code] ?? code;
}

export function documentTypeLabel(code: string|null|undefined): string {
  if (!code) return '—';
  return DOCUMENT_TYPE_FR[code] ?? code;
}

/** [minor] en centimes -> "195,00 €". Jamais de calcul, affichage seul. */
export function money(minor: number|null|undefined, currency = 'EUR'): string {
  if (minor === null || minor === undefined || isNaN(minor)) return '—';
  const euros = minor / 100;
  const symbol = currency === 'EUR' ? '€' : currency;
  return euros.toFixed(2).replace('.', ',') + ' ' + symbol;
}

/** Date ISO brute -> "23/09/2026 21:36" (format FR lisible). */
export function dateTime(raw: string|null|undefined): string {
  if (!raw) return '—';
  const d = new Date(raw);
  if (isNaN(d.getTime())) return '—';
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${pad(d.getDate())}/${pad(d.getMonth()+1)}/${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** Code d'erreur backend -> message humanisé. Ne jamais afficher le
 * code brut ou une exception (CLAUDE_GUARDRAILS.md). */
export function errorMessage(code: string|null|undefined): string {
  if (!code) return 'Une erreur est survenue. Veuillez réessayer.';
  return ERROR_MESSAGES_FR[code] ?? 'Une erreur est survenue. Veuillez réessayer.';
}
