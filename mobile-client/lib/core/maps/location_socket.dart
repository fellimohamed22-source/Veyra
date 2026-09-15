import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../api.dart';

typedef LocationMessageHandler=void Function(Map<String,dynamic> location);

class BookingLocationSocket {
  final Api api;
  final String bookingId;
  final LocationMessageHandler onLocation;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  final StringBuffer _buffer=StringBuffer();
  bool _disposed=false;
  int _subscriptionSeq=0;

  BookingLocationSocket({
    required this.api,
    required this.bookingId,
    required this.onLocation,
  });

  Future<void> connect() async {
    if(_disposed)return;
    final token=await api.storage.read(key:'accessToken');
    if(token==null||_disposed)return;

    final httpBase=api.dio.options.baseUrl;
    final wsBase=httpBase
        .replaceFirst('https://','wss://')
        .replaceFirst('http://','ws://');

    try{
      final channel=WebSocketChannel.connect(Uri.parse('$wsBase/ws'));
      _channel=channel;
      _subscription=channel.stream.listen(
        _onData,
        onDone:_scheduleReconnect,
        onError:(_)=>_scheduleReconnect(),
        cancelOnError:true,
      );
      _sendFrame('CONNECT',{
        'accept-version':'1.2',
        'heart-beat':'10000,10000',
        'Authorization':'Bearer $token',
      });
    }catch(_){
      _scheduleReconnect();
    }
  }

  void _onData(dynamic data){
    _buffer.write(data.toString());
    final raw=_buffer.toString();
    final parts=raw.split('\u0000');
    if(parts.length<=1)return;
    for(var i=0;i<parts.length-1;i++){
      _handleFrame(parts[i]);
    }
    _buffer
      ..clear()
      ..write(parts.last);
  }

  void _handleFrame(String rawFrame){
    final frame=rawFrame.replaceAll('\r\n','\n');
    if(frame.trim().isEmpty)return;
    final split=frame.indexOf('\n\n');
    final head=split==-1?frame:frame.substring(0,split);
    final body=split==-1?'':frame.substring(split+2);
    final lines=head.split('\n');
    if(lines.isEmpty)return;
    final command=lines.first.trim();

    if(command=='CONNECTED'){
      _sendFrame('SUBSCRIBE',{
        'id':'location-${_subscriptionSeq++}',
        'destination':'/topic/bookings/$bookingId/location',
      });
      return;
    }

    if(command=='MESSAGE'&&body.trim().isNotEmpty){
      try{
        final parsed=jsonDecode(body);
        if(parsed is Map<String,dynamic>){
          onLocation(parsed);
        }else if(parsed is Map){
          onLocation(Map<String,dynamic>.from(parsed));
        }
      }catch(_){}
      return;
    }

    if(command=='ERROR'){
      _scheduleReconnect();
    }
  }

  void _sendFrame(String command,Map<String,String> headers,[String body='']){
    final frame=StringBuffer()..write('$command\n');
    headers.forEach((key,value)=>frame.write('$key:$value\n'));
    frame
      ..write('\n')
      ..write(body)
      ..write('\u0000');
    try{
      _channel?.sink.add(frame.toString());
    }catch(_){}
  }

  void _scheduleReconnect(){
    if(_disposed)return;
    _subscription?.cancel();
    _subscription=null;
    try{_channel?.sink.close();}catch(_){}
    _channel=null;
    _buffer.clear();
    _reconnectTimer?.cancel();
    _reconnectTimer=Timer(const Duration(seconds:3),(){
      if(!_disposed)connect();
    });
  }

  void dispose(){
    _disposed=true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    try{_channel?.sink.close();}catch(_){}
    _channel=null;
  }
}
