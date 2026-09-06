import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api.dart';

// Minimal hand-rolled STOMP-over-WebSocket client.
//
// The backend registers a *raw* STOMP endpoint (`.addEndpoint("/ws")`
// without `.withSockJS()` -- see WebSocketConfig.java), and authenticates
// on the STOMP CONNECT frame's native "Authorization" header, not the
// HTTP upgrade request (see StompAuthConfig.java). That rules out using
// SockJS-flavoured packages or relying on WebSocket handshake headers --
// the auth has to travel inside the first STOMP frame's body, which is
// simple enough to hand-roll with the web_socket_channel dependency
// already declared in pubspec.yaml, without adding a new package whose
// version resolution can't be verified without pub.dev network access
// from this environment.
typedef ChatMessageHandler = void Function(Map<String, dynamic> message);

class ChatSocket {
  final Api api;
  final String bookingId;
  final ChatMessageHandler onMessage;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final StringBuffer _buffer = StringBuffer();
  bool _disposed = false;
  int _subSeq = 0;

  ChatSocket({required this.api, required this.bookingId, required this.onMessage});

  Future<void> connect() async {
    if (_disposed) return;
    final token = await api.storage.read(key: 'accessToken');
    if (token == null || _disposed) return;

    final httpBase = api.dio.options.baseUrl;
    final wsBase = httpBase
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    try {
      final channel = WebSocketChannel.connect(Uri.parse('$wsBase/ws'));
      _channel = channel;
      _sub = channel.stream.listen(
        _onData,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
      _sendFrame('CONNECT', {
        'accept-version': '1.2',
        'heart-beat': '0,0',
        'Authorization': 'Bearer $token',
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic data) {
    _buffer.write(data.toString());
    final raw = _buffer.toString();
    final parts = raw.split('\u0000');
    if (parts.length > 1) {
      for (var i = 0; i < parts.length - 1; i++) {
        _handleFrame(parts[i]);
      }
      _buffer
        ..clear()
        ..write(parts.last);
    }
  }

  void _handleFrame(String frame) {
    final trimmed = frame.replaceAll('\r\n', '\n');
    if (trimmed.trim().isEmpty) return; // heartbeat / newline keepalive
    final split = trimmed.indexOf('\n\n');
    final head = split == -1 ? trimmed : trimmed.substring(0, split);
    final body = split == -1 ? '' : trimmed.substring(split + 2);
    final lines = head.split('\n');
    if (lines.isEmpty) return;
    final command = lines.first.trim();

    if (command == 'CONNECTED') {
      _subscribe();
      return;
    }
    if (command == 'MESSAGE') {
      if (body.trim().isEmpty) return;
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        onMessage(json);
      } catch (_) {
        // malformed payload -- ignore rather than crash the chat screen
      }
      return;
    }
    if (command == 'ERROR') {
      _scheduleReconnect();
    }
  }

  void _subscribe() {
    _sendFrame('SUBSCRIBE', {
      'id': 'chat-${_subSeq++}',
      'destination': '/topic/bookings/$bookingId/chat',
    });
  }

  void _sendFrame(String command, Map<String, String> headers, [String body = '']) {
    final buffer = StringBuffer()..write('$command\n');
    headers.forEach((k, v) => buffer.write('$k:$v\n'));
    buffer.write('\n');
    buffer.write(body);
    buffer.write('\u0000');
    _channel?.sink.add(buffer.toString());
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _sub?.cancel();
    _channel = null;
    _buffer.clear();
    Future.delayed(const Duration(seconds: 3), () {
      if (!_disposed) connect();
    });
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
  }
}
