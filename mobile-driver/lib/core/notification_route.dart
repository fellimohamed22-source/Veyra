String? notificationRoute(Map<String,dynamic> data) {
  final id=(data['bookingId']??data['booking_id'])?.toString();
  if(id==null||id.trim().isEmpty)return null;
  final safeId=Uri.encodeComponent(id);
  final template=(data['templateCode']??data['template_code']??'').toString();
  return template=='NEW_BOOKING'?'/request/$safeId':'/ride/$safeId';
}
