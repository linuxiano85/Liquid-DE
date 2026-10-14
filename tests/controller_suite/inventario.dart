import 'dart:convert';
import 'package:minervad/services/controller_service.dart';

Future<void> main() async {
  final c = ControllerService(
    automatico: () => false,
    tipo: () => 'xbox-series',
    perPad: () => {},
  );
  final p = await c.inventario();
  print(
    jsonEncode({
      'pad': [
        for (final v in p)
          {
            'nome': v['nome'],
            'famiglia': v['famiglia'],
            'collegamento': v['collegamento'],
            'id': v['id'],
          },
      ],
    }),
  );
  await c.close();
}
