import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'server/server.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _solicitarPermisos();

  CocinaServer.start();
  runApp(const MyApp());
}

Future<void> _solicitarPermisos() async {
  if (Platform.isAndroid) {
    await Permission.storage.request();
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
  }
}

// Cola de guardados: evita que dos completados casi simultáneos
// lean el archivo viejo y se sobre-escriban uno a otro.
Future<void> _colaGuardadoExcel = Future.value();

Future<void> guardarVentaExcel(Map<String, dynamic> orden) {
  _colaGuardadoExcel =
      _colaGuardadoExcel.then((_) => _guardarVentaExcelInterno(orden));
  return _colaGuardadoExcel;
}

Future<void> _guardarVentaExcelInterno(Map<String, dynamic> orden) async {
  try {
    final directory = Directory('/storage/emulated/0/Download');

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File('${directory.path}/Ventass_churros.xlsx');

    Excel excel;
    Sheet sheet;

    if (await file.exists()) {
      final bytes = file.readAsBytesSync();
      excel = Excel.decodeBytes(bytes);
      sheet = excel['Ventas'];
    } else {
      excel = Excel.createExcel();
      sheet = excel['Ventas'];

      sheet.appendRow([
        TextCellValue('nombre'),
        TextCellValue('tipo'),
        TextCellValue('info'),
        TextCellValue('cantidad'),
        TextCellValue('precio'),
        TextCellValue('fecha'),
        TextCellValue('precio total'),
      ]);
    }

    final now = DateTime.now();
    final fecha = DateFormat('d/M/yyyy H:mm:s').format(now);

    final items = (orden['items'] as List).cast<Map<String, dynamic>>();
    final total = (orden['total'] as num?)?.toDouble() ?? 0;

    for (final item in items) {
      final producto = (item['producto'] as String? ?? '');
      final tipo = producto.replaceFirst('Churro ', '').trim().toLowerCase();
      final info = item['nota'] as String? ?? '';
      final cantidad = (item['cantidad'] as num?)?.toInt() ?? 1;
      final precioUnitario = (item['precioUnitario'] as num?)?.toDouble() ?? 0;

      sheet.appendRow([
        TextCellValue('churro'),
        TextCellValue(tipo),
        TextCellValue(info),
        IntCellValue(cantidad),
        DoubleCellValue(precioUnitario),
        TextCellValue(fecha),
        DoubleCellValue(total),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) {
      debugPrint('❌ Error: No se pudo codificar el Excel');
      return;
    }

    await file.writeAsBytes(bytes, flush: true);

    debugPrint('✅ Excel guardado en DOWNLOAD: ${file.path}');
  } catch (e) {
    debugPrint('❌ Error guardando Excel: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cocina Churros',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
      ),
      home: const CocinaPage(),
    );
  }
}

class CocinaPage extends StatefulWidget {
  const CocinaPage({super.key});

  @override
  State<CocinaPage> createState() => _CocinaPageState();
}

class _CocinaPageState extends State<CocinaPage> {
  final List<Map<String, dynamic>> ordenes = [];
  String? ipServidor;

  @override
  void initState() {
    super.initState();
    _cargarIP();

    CocinaServer.addListener((orden) {
      setState(() {
        ordenes.add(orden);
      });
      FlutterRingtonePlayer().playNotification();
      HapticFeedback.vibrate();
    });
  }

  void _cargarIP() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          ipServidor = CocinaServer.serverIP;
        });
      }
    });
  }

  void _copiarIP() {
    if (ipServidor != null) {
      Clipboard.setData(ClipboardData(text: 'http://$ipServidor:8080'));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ URL copiada al portapapeles'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _mostrarIP() {
    if (ipServidor == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.wifi, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            const Text('Configuración'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configura esta URL en el mesero:',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                'http://$ipServidor:8080',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CERRAR'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              _copiarIP();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.copy),
            label: const Text('COPIAR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _cancelarOrden(int index) {
    setState(() {
      ordenes.removeAt(index);
    });
  }

  Future<void> _completarOrden(int index) async {
    final orden = ordenes[index];

    await guardarVentaExcel(orden);

    setState(() {
      ordenes.removeAt(index);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Orden completada y guardada'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cocina Churros'),
        backgroundColor: Colors.brown,
        actions: [
          if (ipServidor != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: _mostrarIP,
              tooltip: 'Ver IP del servidor',
            ),
        ],
      ),
      body: SafeArea(
        child: ordenes.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.restaurant,
                      size: 80,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'No hay órdenes aún',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Esperando pedidos de meseros...',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: ordenes.length,
                itemBuilder: (context, index) {
                  final orden = ordenes[index];
                  final items =
                      (orden['items'] as List).cast<Map<String, dynamic>>();
                  final nota = orden['nota'] ?? '';
                  final total = (orden['total'] as num?)?.toDouble() ?? 0;
                  final esActiva = index == 0;

                  return Card(
                    color: esActiva ? Colors.orange.shade100 : null,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    elevation: esActiva ? 6 : 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            esActiva ? 'ORDEN ACTIVA' : 'PENDIENTE',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...items.map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '${item['cantidad']}x ${item['producto']} (${item['nota']})',
                                  style: const TextStyle(fontSize: 15),
                                ),
                              )),
                          if (nota.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Nota general: $nota',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Text(
                            'Total: \$${total.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => _completarOrden(index),
                                  child: const Text('COMPLETAR'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  onPressed: () => _cancelarOrden(index),
                                  child: const Text('CANCELAR'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
