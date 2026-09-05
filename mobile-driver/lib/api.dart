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

  Future<void> registerDevice(String token,{String platform='mobile'}) async {
    await dio.post('/api/v1/devices',data:{
      'platform':platform,
      'pushToken':token,
      'deviceName':'Veyra mobile',
    });
  }

  Future<void> login(String email,String password) async {
    final r=await dio.post('/api/v1/auth/login',data:{
      'email':email.trim(),'password':password,'deviceName':'driver-mobile'
    });
    await storage.write(key:'accessToken',value:r.data['accessToken']);
    await storage.write(key:'refreshToken',value:r.data['refreshToken']);
  }

  Future<List<dynamic>> opportunities({
    String sort='date',
    String? categoryId,
    DateTime? from,
    DateTime? to,
    int? minPassengers,
    String? pickupQuery,
    String? destinationQuery,
  }) async {
    final query=<String,dynamic>{'sort':sort};
    if(categoryId!=null&&categoryId.isNotEmpty)query['categoryId']=categoryId;
    if(from!=null)query['from']=from.toUtc().toIso8601String();
    if(to!=null)query['to']=to.toUtc().toIso8601String();
    if(minPassengers!=null)query['minPassengers']=minPassengers;
    if(pickupQuery!=null&&pickupQuery.trim().isNotEmpty)query['pickupQuery']=pickupQuery.trim();
    if(destinationQuery!=null&&destinationQuery.trim().isNotEmpty)query['destinationQuery']=destinationQuery.trim();
    return List<dynamic>.from((await dio.get('/api/v1/driver/opportunities',queryParameters:query)).data);
  }

  Future<Map<String,dynamic>> opportunityDetail(String bookingId) async =>
      Map<String,dynamic>.from((await dio.get('/api/v1/driver/opportunities/$bookingId')).data);

  Future<void> offer(String bookingId,int amountMinor) async {
    await dio.post('/api/v1/driver/opportunities/$bookingId/offers',
      data:{'amountMinor':amountMinor,'currency':'EUR'});
  }

  Future<List<dynamic>> bookings({String scope='upcoming'}) async =>
      List<dynamic>.from((await dio.get('/api/v1/driver/bookings',queryParameters:{'scope':scope})).data);

  Future<Map<String,dynamic>> bookingDetail(String id) async =>
      Map<String,dynamic>.from((await dio.get('/api/v1/driver/bookings/$id')).data);

  Future<Map<String,dynamic>> wallet() async =>
      Map<String,dynamic>.from((await dio.get('/api/v1/driver/wallet')).data);

  Future<Map<String,dynamic>> createProfile() async =>
      Map<String,dynamic>.from((await dio.post('/api/v1/driver/profile')).data);

  Future<void> uploadDocument(String type,String filePath) async {
    final form=FormData.fromMap({
      'type':type,
      'file':await MultipartFile.fromFile(filePath),
    });
    await dio.post('/api/v1/driver/documents',data:form);
  }

  Future<void> saveCompany({
    String? siren,String? siret,required String legalName
  }) async {
    await dio.put('/api/v1/driver/onboarding/company',data:{
      'siren':siren,'siret':siret,'legalName':legalName
    });
  }

  Future<void> saveVtc({
    required String registrationNumber,
    required String cardNumber,
    String? issuedAt,
    String? expiresAt,
  }) async {
    await dio.put('/api/v1/driver/onboarding/vtc',data:{
      'registrationNumber':registrationNumber,
      'cardNumber':cardNumber,
      'issuedAt':issuedAt,
      'expiresAt':expiresAt,
    });
  }

  Future<List<dynamic>> vehicleCategories() async =>
      List<dynamic>.from((await dio.get('/api/v1/reference/vehicle-categories')).data);

  Future<void> addVehicle({
    required String categoryId,
    required String brand,
    required String model,
    required int year,
    required String plateNumber,
    String? color,
  }) async {
    await dio.post('/api/v1/driver/onboarding/vehicles',data:{
      'categoryId':categoryId,
      'brand':brand,
      'model':model,
      'year':year,
      'plateNumber':plateNumber,
      'color':color,
    });
  }

  Future<Map<String,dynamic>> onboardingStatus() async =>
      Map<String,dynamic>.from((await dio.get('/api/v1/driver/onboarding/status')).data);

  Future<void> enRoute(String id) async => dio.post('/api/v1/bookings/$id/en-route');
  Future<void> arrived(String id) async => dio.post('/api/v1/bookings/$id/arrived');
  Future<void> start(String id,String pin) async =>
      dio.post('/api/v1/bookings/$id/start',data:{'pin':pin});
  Future<void> complete(String id) async => dio.post('/api/v1/bookings/$id/complete');

  Future<void> noShow(String id) async => dio.post('/api/v1/bookings/$id/no-show');

  Future<void> updateLocation({
    required String bookingId,
    required double lat,
    required double lng,
    required int sequenceNo,
    double? accuracyM,
    double? heading,
    double? speedMps,
  }) async {
    await dio.post('/api/v1/driver/location',data:{
      'bookingId':bookingId,
      'lat':lat,
      'lng':lng,
      'accuracyM':accuracyM,
      'heading':heading,
      'speedMps':speedMps,
      'sequenceNo':sequenceNo,
      'recordedAt':DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<dynamic>> chatMessages(String bookingId) async =>
      List<dynamic>.from((await dio.get('/api/v1/bookings/$bookingId/chat/messages')).data);

  Future<void> sendMessage(String bookingId,String body) async {
    await dio.post('/api/v1/bookings/$bookingId/chat/messages',data:{'body':body});
  }
}
