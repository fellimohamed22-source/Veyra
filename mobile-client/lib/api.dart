import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Api {
  final Dio dio;
  final FlutterSecureStorage storage=const FlutterSecureStorage();

  Api(String base):dio=Dio(BaseOptions(
    baseUrl:base,
    connectTimeout:const Duration(seconds:10),
    receiveTimeout:const Duration(seconds:15),
  )){
    dio.interceptors.add(InterceptorsWrapper(
      onRequest:(o,h)async{
        final t=await storage.read(key:'accessToken');
        if(t!=null)o.headers['Authorization']='Bearer $t';
        h.next(o);
      },
      onError:(e,h)=>h.next(e),
    ));
  }

  Future<void> login(String email,String password) async {
    final r=await dio.post('/api/v1/auth/login',data:{
      'email':email.trim(),
      'password':password,
      'deviceName':'client-mobile',
    });
    await storage.write(key:'accessToken',value:r.data['accessToken']);
    await storage.write(key:'refreshToken',value:r.data['refreshToken']);
  }

  Future<void> logout() async {
    final refresh=await storage.read(key:'refreshToken');
    if(refresh!=null){
      try{await dio.post('/api/v1/auth/logout',data:{'refreshToken':refresh,'deviceName':'client-mobile'});}catch(_){}
    }
    await storage.deleteAll();
  }

  Future<List<dynamic>> bookings() async =>
      List<dynamic>.from((await dio.get('/api/v1/scheduled-bookings')).data);

  Future<Map<String,dynamic>> bookingDetail(String id) async =>
      Map<String,dynamic>.from((await dio.get('/api/v1/scheduled-bookings/$id')).data);

  Future<Map<String,dynamic>> createBooking(Map<String,dynamic> body) async =>
      Map<String,dynamic>.from((await dio.post('/api/v1/scheduled-bookings',data:body)).data);

  Future<List<dynamic>> offers(String id) async =>
      List<dynamic>.from((await dio.get('/api/v1/scheduled-bookings/$id/offers')).data);

  Future<Map<String,dynamic>> accept(String bookingId,String offerId) async =>
      Map<String,dynamic>.from((await dio.post('/api/v1/scheduled-bookings/$bookingId/offers/$offerId/accept')).data);

  Future<Map<String,dynamic>> cancel(String bookingId) async =>
      Map<String,dynamic>.from((await dio.post('/api/v1/bookings/$bookingId/cancel')).data);

  Future<String> pin(String bookingId) async =>
      (await dio.get('/api/v1/bookings/$bookingId/pin')).data['pin'] as String;

  Future<List<dynamic>> autocomplete(String query) async {
    if(query.trim().length<3)return const [];
    return List<dynamic>.from((await dio.get('/api/v1/addresses/autocomplete',queryParameters:{'q':query.trim()})).data);
  }

  Future<List<dynamic>> vehicleCategories() async =>
      List<dynamic>.from((await dio.get('/api/v1/reference/vehicle-categories')).data);

  Future<Map<String,dynamic>> createPaymentIntent(String bookingId,String idempotencyKey) async =>
      Map<String,dynamic>.from((await dio.post('/api/v1/payments/bookings/$bookingId/intent',options:Options(headers:{'Idempotency-Key':idempotencyKey}))).data);

  Future<List<dynamic>> notifications() async =>
      List<dynamic>.from((await dio.get('/api/v1/notifications')).data);

  Future<List<dynamic>> chatMessages(String bookingId) async =>
      List<dynamic>.from((await dio.get('/api/v1/bookings/$bookingId/chat/messages')).data);

  Future<void> sendMessage(String bookingId,String body) async {
    await dio.post('/api/v1/bookings/$bookingId/chat/messages',data:{'body':body});
  }
}
