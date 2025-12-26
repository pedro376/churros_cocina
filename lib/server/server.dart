import 'dart:convert';
import 'dart:io';

class CocinaServer {
  static final List<Function(Map<String, dynamic>)> _listeners = [];

  static void addListener(Function(Map<String, dynamic>) listener) {
    _listeners.add(listener);
  }

  static Future<void> start() async {
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      8080,
    );

    print(' Servidor cocina activo en puerto 8080');

    await for (HttpRequest request in server) {
      if (request.method == 'POST' && request.uri.path == '/orden') {
        final content = await utf8.decoder.bind(request).join();
        final data = jsonDecode(content);

        for (var l in _listeners) {
          l(data);
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..write('Orden recibida')
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    }
  }
}
