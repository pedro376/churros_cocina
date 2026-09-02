import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'server/server.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CocinaServer.start();
  runApp(const MyApp());
}

Future<void> guardarVentaExcel(Map<String, dynamic> orden) async {
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
        TextCellValue('Fecha'),
        TextCellValue('Hora'),
        TextCellValue('Productos'),
        TextCellValue('Nota'),
        TextCellValue('Estado'),
      ]);
    }

    final now = DateTime.now();
    final fecha = DateFormat('yyyy-MM-dd').format(now);
    final hora = DateFormat('HH:mm:ss').format(now);

    final productos = (orden['productos'] as List).join(' | ');
    final nota = orden['nota'] ?? '';

    sheet.appendRow([
      TextCellValue(fecha),
      TextCellValue(hora),
      TextCellValue(productos),
      TextCellValue(nota),
      TextCellValue('COMPRADO'),
    ]);

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

  void _cancelarOrden() {
    if (ordenes.isEmpty) return;

    setState(() {
      ordenes.removeAt(0);
    });
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
            : Column(
                children: [
                  const SizedBox(height: 20),
                  Card(
                    color: Colors.orange.shade100,
                    margin: const EdgeInsets.all(12),
                    elevation: 6,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Builder(
                        builder: (context) {
                          final orden = ordenes.first;
                          final nota = orden['nota'] ?? '';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ORDEN ACTIVA',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                (orden['productos'] as List).join(', '),
                                style: const TextStyle(fontSize: 16),
                              ),
                              if (nota.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Nota: $nota',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () async {
                                        final orden = ordenes.first;

                                        await guardarVentaExcel(orden);

                                        setState(() {
                                          ordenes.removeAt(0);
                                        });

                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  '✅ Orden completada y guardada'),
                                              backgroundColor: Colors.green,
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      },
                                      child: const Text('COMPLETAR'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                      ),
                                      onPressed: _cancelarOrden,
                                      child: const Text('CANCELAR'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: ordenes.length - 1,
                      itemBuilder: (context, index) {
                        final orden = ordenes[index + 1];
                        final nota = orden['nota'] ?? '';

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: ListTile(
                            title: Text(
                              (orden['productos'] as List).join(', '),
                            ),
                            subtitle:
                                nota.isNotEmpty ? Text('Nota: $nota') : null,
                            trailing: const Text('Pendiente'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
