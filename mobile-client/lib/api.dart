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
      onError:(e,h)async{
        final request=e.requestOptions;
        final isAuth=request.path.contains('/api/v1/auth/');
        if(e.response?.statusCode==401 && !isAuth && request.extra['retried']!=true){
          final refreshed=await _refreshToken();
          if(refreshed){
            final token=await storage.read(key:'accessToken');
            request.headers['Authorization']='Bearer $token';
            request.extra['retried']=true;
            try{
              final response=await dio.fetch(request);
              h.resolve(response);
              return;
            }catch(_){}
          }
        }
        h.next(e);
      },
    ));
  }

  Future<bool> _refreshToken() async {
    final refresh=await storage.read(key:'refreshToken');
    if(refresh==null||refresh.isEmpty)return false;
    try{
      final raw=Dio(BaseOptions(baseUrl:dio.options.baseUrl));
      final r=await raw.post('/api/v1/auth/refresh',data:{
        'refreshToken':refresh,
        'deviceName':'mobile',
      });
      await storage.write(key:'accessToken',value:r.data['accessToken']);
      await storage.write(key:'refreshToken',value:r.data['refreshToken']);
      return true;
    }catch(_){
      await storage.deleteAll();
      return false;
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String firstName,
    String? lastName,
    String? phone,
  }) async {
    final r=await dio.post('/api/v1/auth/register',data:{
      'email':email.trim(),
      'password':password,
      'firstName':firstName.trim(),
      'lastName':lastName?.trim(),
      'phone':phone?.trim(),
    });
    await storage.write(key:'accessToken',value:r.data['accessToken']);
    await storage.write(key:'refreshToken',value:r.data['refreshToken']);
  }

  Future<void> forgotPassword(String email) async {
    await dio.post('/api/v1/auth/forgot-password',data:{'email':email.trim()});
  }

  Future<void> registerDevice(String token,{String platform='mobile'}) async {
    await dio.post('/api/v1/devices',data:{
      'platform':platform,
      'pushToken':token,
      'deviceName':'Veyra mobile',
    });
  }

  Future<void> login(String email,String password) async {
    _me=null;
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
    _me=null;
    await storage.deleteAll();
  }

  Future<List<dynamic>> bookings() async =>
      List<dynamic>.from((await dio.get('/api/v1/scheduled-bookings')).data);

  Future<Map<String,dynamic>> bookingDetail(String id) async =>
      Map<String,dynamic>.from((await dio.get('/api/v1/scheduled-bookings/$id')).data);

  Future<Map<String,dynamic>> createBooking(Map<String,dynamic> body) async =>
      Map<String,dynamic>.from((await dio.post('/api/v1/scheduled-bookings',data:body)).data);

  Future<Map<String,dynamic>> updateBooking(String id,Map<String,dynamic> body) async =>
      Map<String,dynamic>.from((await dio.patch('/api/v1/scheduled-bookings/$id',data:body)).data);

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

  Future<Map<String,dynamic>?> reverseGeocode(double lat,double lng) async {
    final r=await dio.get('/api/v1/addresses/reverse',queryParameters:{'lat':lat,'lng':lng});
    final data=Map<String,dynamic>.from(r.data);
    return data['found']==true?data:null;
  }

  Future<List<dynamic>> vehicleCategories() async =>
      List<dynamic>.from((await dio.get('/api/v1/reference/vehicle-categories')).data);

  Future<Map<String,dynamic>> createPaymentIntent(String bookingId,String idempotencyKey) async =>
      Map<String,dynamic>.from((await dio.post('/api/v1/payments/bookings/$bookingId/intent',options:Options(headers:{'Idempotency-Key':idempotencyKey}))).data);

  Future<List<dynamic>> notifications() async =>
      List<dynamic>.from((await dio.get('/api/v1/notifications')).data);

  Future<Map<String,dynamic>> routeEstimate({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async => Map<String,dynamic>.from((await dio.get('/api/v1/routes/estimate',queryParameters:{
    'fromLat':fromLat,'fromLng':fromLng,'toLat':toLat,'toLng':toLng
  })).data);

  Future<Map<String,dynamic>> currentLocation(String bookingId) async =>
      Map<String,dynamic>.from((await dio.get('/api/v1/bookings/$bookingId/location')).data);

  Future<void> rate(String bookingId,int score,{String? comment}) async {
    await dio.post('/api/v1/bookings/$bookingId/ratings',data:{
      'score':score,'comment':comment
    });
  }

  Future<List<dynamic>> ratings(String bookingId) async =>
      List<dynamic>.from((await dio.get('/api/v1/bookings/$bookingId/ratings')).data);

  Future<List<dynamic>> chatMessages(String bookingId) async =>
      List<dynamic>.from((await dio.get('/api/v1/bookings/$bookingId/chat/messages')).data);

  Future<Map<String,dynamic>> sendMessage(String bookingId,String body) async {
    final r=await dio.post('/api/v1/bookings/$bookingId/chat/messages',data:{'body':body});
    return Map<String,dynamic>.from(r.data);
  }

  Map<String,dynamic>? _me;
  Future<Map<String,dynamic>> me() async {
    if(_me!=null)return _me!;
    final r=await dio.get('/api/v1/me');
    _me=Map<String,dynamic>.from(r.data);
    return _me!;
  }
}
