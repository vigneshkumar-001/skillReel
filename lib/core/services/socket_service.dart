import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants/api_constants.dart';
import 'app_logger.dart';
import 'log.dart';
import 'storage_service.dart';

class SocketService {
  static SocketService? _instance;
  static SocketService get instance {
    _instance ??= SocketService._();
    return _instance!;
  }
  SocketService._();

  io.Socket? _socket;
  final _log = log.tag('SocketService');
  final Map<String, Map<void Function(dynamic), void Function(dynamic)>>
      _wrappedHandlers = {};

  bool get isConnected => _socket?.connected == true;

  Future<void> connect() async {
    final token = await StorageService.instance.getToken();
    final base = ApiConstants.baseUrl.replaceAll('/api/v1', '');

    if (_socket != null) {
      // Update auth token on existing socket (best-effort).
      _socket!.auth = {'token': token};
      if (!_socket!.connected) {
        _log.i(
          'reconnect base=$base token=${AppLogger.maskToken(token)}',
        );
        _socket!.connect();
      }
      return;
    }

    _log.i('connect base=$base token=${AppLogger.maskToken(token)}');

    _socket = io.io(
      base,
      io.OptionBuilder()
          .setTransports(['websocket'])
          // New spec: Socket.IO auth token.
          .setAuth({'token': token})
          // Back-compat: also send Authorization header.
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .build(),
    );

    _socket!.onConnect((_) {
      _log.i('connected id=${_socket?.id}');
    });
    _socket!.onDisconnect((reason) {
      _log.i('disconnected reason=$reason');
    });
    _socket!.onConnectError((err) {
      _log.w('connect_error ${AppLogger.safeJson(err)}');
    });
    _socket!.onError((err) {
      _log.w('error ${AppLogger.safeJson(err)}');
    });
  }

  Future<void> ensureConnected() async {
    if (isConnected) return;
    await connect();
    if (!isConnected) {
      _log.i('ensureConnected -> connect()');
      _socket?.connect();
    }
  }

  void interactionJoin({String? reelId, String? threadId}) {
    _log.d('emit interaction:join reelId=$reelId threadId=$threadId');
    _socket?.emit('interaction:join', {'reelId': reelId, 'threadId': threadId});
  }

  void interactionLeave({String? reelId, String? threadId}) {
    _log.d('emit interaction:leave reelId=$reelId threadId=$threadId');
    _socket?.emit(
      'interaction:leave',
      {'reelId': reelId, 'threadId': threadId},
    );
  }

  void on(String event, void Function(dynamic) handler) {
    void wrapped(dynamic data) {
      _log.d('on $event -> ${AppLogger.safeJson(data)}');
      handler(data);
    }

    (_wrappedHandlers[event] ??= {})[handler] = wrapped;
    _socket?.on(event, wrapped);
  }

  void off(String event, [void Function(dynamic)? handler]) {
    if (handler == null) {
      _socket?.off(event);
      _wrappedHandlers.remove(event);
    } else {
      final wrapped = _wrappedHandlers[event]?[handler];
      if (wrapped != null) {
        _socket?.off(event, wrapped);
        _wrappedHandlers[event]!.remove(handler);
      } else {
        // Fallback (if it was registered without wrapping).
        _socket?.off(event, handler);
      }
    }
  }

  void joinThread(String threadId) {
    // Legacy helper; server may map this internally.
    interactionJoin(threadId: threadId);
  }

  void sendMessage(String threadId, String text) {
    // Legacy helper; use new namespace if supported.
    _socket?.emit('send_message', {'threadId': threadId, 'text': text});
  }

  void onMessage(void Function(dynamic) handler) {
    // Legacy event.
    _socket?.on('new_message', handler);
  }

  void disconnect() => _socket?.disconnect();
}
