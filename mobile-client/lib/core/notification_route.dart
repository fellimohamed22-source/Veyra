String? notificationRoute(Map<String,dynamic> data) {
  final id=(data['bookingId']??data['booking_id'])?.toString();
  if(id==null||id.trim().isEmpty)return null;
  final safeId=Uri.encodeComponent(id);
  final template=(data['templateCode']??data['template_code']??'').toString();
  final event=(data['event']??data['event_type']??'').toString();
  if(template=='NEW_OFFER')return '/offers/$safeId';
  if(event=='payment.failed'||event=='payment.required')return '/payment/$safeId';
  return '/booking/$safeId';
}
