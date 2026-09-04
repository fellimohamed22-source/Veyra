import 'package:dio/dio.dart';import 'package:flutter_secure_storage/flutter_secure_storage.dart';
class Api{final Dio dio;final FlutterSecureStorage storage=const FlutterSecureStorage();Api(String base):dio=Dio(BaseOptions(baseUrl:base)){dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h)async{final t=await storage.read(key:'accessToken');if(t!=null)o.headers['Authorization']='Bearer $t';h.next(o);},onError:(e,h){h.next(e);}));}
 Future<void>login(String email,String password)async{final r=await dio.post('/api/v1/auth/login',data:{'email':email,'password':password,'deviceName':'client-mobile'});await storage.write(key:'accessToken',value:r.data['accessToken']);await storage.write(key:'refreshToken',value:r.data['refreshToken']);}
 Future<List<dynamic>>bookings()async=>(await dio.get('/api/v1/scheduled-bookings')).data;
 Future<Map<String,dynamic>>createBooking(Map<String,dynamic>x)async=>Map<String,dynamic>.from((await dio.post('/api/v1/scheduled-bookings',data:x)).data);
 Future<List<dynamic>>offers(String id)async=>(await dio.get('/api/v1/scheduled-bookings/$id/offers')).data;
 Future<void>accept(String b,String o)async{await dio.post('/api/v1/scheduled-bookings/$b/offers/$o/accept');}
 Future<String>pin(String id)async=>(await dio.get('/api/v1/bookings/$id/pin')).data['pin'];
}