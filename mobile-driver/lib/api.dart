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
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h)async{
      final t=await storage.read(key:'accessToken');
      if(t!=null)o.headers['Authorization']='Bearer $t';
      h.next(o);
    }));
  }

  Future<void> login(String email,String password) async {
    final r=await dio.post('/api/v1/auth/login',data:{
      'email':email.trim(),'password':password,'deviceName':'driver-mobile'
    });
    await storage.write(key:'accessToken',value:r.data['accessToken']);
    await storage.write(key:'refreshToken',value:r.data['refreshToken']);
  }

  Future<List<dynamic>> opportunities({String sort='date'}) async =>
      List<dynamic>.from((await dio.get('/api/v1/driver/opportunities',queryParameters:{'sort':sort})).data);

  Future<void> offer(String bookingId,int amountMinor) async {
    await dio.post('/api/v1/driver/opportunities/$bookingId/offers',
      data:{'amountMinor':amountMinor,'currency':'EUR'});
  }

  Future<Map<String,dynamic>> wallet() async =>
      Map<String,dynamic>.from((await dio.get('/api/v1/driver/wallet')).data);

  Future<Map<String,dynamic>> onboardingStatus() async =>
      Map<String,dynamic>.from((await dio.get('/api/v1/driver/onboarding/status')).data);

  Future<void> enRoute(String id) async => dio.post('/api/v1/bookings/$id/en-route');
  Future<void> arrived(String id) async => dio.post('/api/v1/bookings/$id/arrived');
  Future<void> start(String id,String pin) async =>
      dio.post('/api/v1/bookings/$id/start',data:{'pin':pin});
  Future<void> complete(String id) async => dio.post('/api/v1/bookings/$id/complete');

  Future<List<dynamic>> chatMessages(String bookingId) async =>
      List<dynamic>.from((await dio.get('/api/v1/bookings/$bookingId/chat/messages')).data);

  Future<void> sendMessage(String bookingId,String body) async {
    await dio.post('/api/v1/bookings/$bookingId/chat/messages',data:{'body':body});
  }
}
