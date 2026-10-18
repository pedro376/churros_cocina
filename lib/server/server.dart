import 'dart:convert';
import 'dart:io';

class CocinaServer {
  static final List<Function(Map<String, dynamic>)> _listeners = [];
  static String? serverIP;

  static void addListener(Function(Map<String, dynamic>) listener) {
    _listeners.add(listener);
  }

  static Future<void> start() async {
    HttpServer? server;

    try {
      server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        8080,
        shared: true,
      );
      print('✅ Servidor iniciado con anyIPv4');
    } catch (e) {
      print('⚠️ No se pudo bind con anyIPv4, intentando con 0.0.0.0...');
      try {
        server = await HttpServer.bind(
          '0.0.0.0',
          8080,
          shared: true,
        );
        print('✅ Servidor iniciado con 0.0.0.0');
      } catch (e2) {
        print('❌ Error iniciando servidor: $e2');
        return;
      }
    }

    await _obtenerIP();

    print('✅ Servidor cocina activo en puerto 8080');
    if (serverIP != null) {
      print('🌐 IP del servidor: $serverIP:8080');
      print('📱 Configura esta URL en el mesero: http://$serverIP:8080');
    }

    await _mostrarTodasLasIPs();

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

  static Future<void> _mostrarTodasLasIPs() async {
    try {
      print('\n🔍 ===== TODAS LAS IPs DEL DISPOSITIVO =====');

      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: true,
        includeLoopback: true,
      );

      for (var interface in interfaces) {
        print('\n📡 Interfaz: ${interface.name}');
        for (var addr in interface.addresses) {
          final tipo = addr.isLoopback
              ? '(localhost)'
              : interface.name.contains('wlan')
                  ? '(WiFi)'
                  : interface.name.contains('ap')
                      ? '(Hotspot) ⭐'
                      : interface.name.contains('rndis')
                          ? '(USB)'
                          : '';
          print('   └─ IP: ${addr.address} $tipo');
        }
      }

      print(
          '\n💡 IMPORTANTE: Si usas hotspot, la IP con (Hotspot) es la correcta');
      print('===========================================\n');
    } catch (e) {
      print('❌ Error listando interfaces: $e');
    }
  }

  static Future<void> _obtenerIP() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );

      for (var interface in interfaces) {
        if (interface.name.contains('ap') ||
            interface.name.contains('wlan1') ||
            interface.name.contains('softap')) {
          for (var addr in interface.addresses) {
            if (!addr.isLoopback) {
              serverIP = addr.address;
              print('✅ Hotspot detectado: $serverIP');
              return;
            }
          }
        }
      }

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168')) {
            serverIP = addr.address;
            return;
          }
        }
      }

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('172.')) {
            serverIP = addr.address;
            return;
          }
        }
      }

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            serverIP = addr.address;
            return;
          }
        }
      }
    } catch (e) {
      print('❌ Error obteniendo IP: $e');
    }
  }
}
