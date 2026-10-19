/** Booking status pill of the partner mock-ups. */
export function bookingPill(b: any): {text: string; css: string} {
  const s = String(b?.status || '');
  const offers = Number(b?.offer_count || 0);
  if ((s === 'OPEN_FOR_OFFERS' || s === 'OFFERS_RECEIVED') && offers > 0) return {text: `${offers} offre${offers > 1 ? 's' : ''} reçue${offers > 1 ? 's' : ''}`, css: 'p-warn'};
  if (s === 'OPEN_FOR_OFFERS' || s === 'OFFERS_RECEIVED') return {text: 'En attente d’offres', css: 'p-mute'};
  if (s === 'PENDING_PAYMENT') return {text: 'Paiement à finaliser', css: 'p-warn'};
  if (s === 'CONFIRMED') return {text: 'Chauffeur confirmé', css: 'p-ok'};
  if (s === 'DRIVER_EN_ROUTE') return {text: 'Chauffeur en route', css: 'p-info'};
  if (s === 'DRIVER_ARRIVED') return {text: 'Chauffeur arrivé', css: 'p-info'};
  if (s === 'IN_PROGRESS') return {text: 'En cours', css: 'p-info'};
  if (s === 'COMPLETED' || s === 'CLOSED') return {text: 'Terminée', css: 'p-mute'};
  if (s === 'EXPIRED' || s === 'NO_OFFER') return {text: 'Sans chauffeur', css: 'p-bad'};
  if (s.includes('CANCEL') || s === 'CUSTOMER_NO_SHOW') return {text: 'Annulée', css: 'p-bad'};
  return {text: s, css: 'p-mute'};
}
