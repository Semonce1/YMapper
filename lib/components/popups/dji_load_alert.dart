import 'package:ymapper/main.dart';
import 'package:flutter/material.dart';

class DjiLoadAlert extends StatefulWidget {
  const DjiLoadAlert({super.key, this.showCheckbox = true});

  /// Whether to show the "Do not show again" checkbox.
  ///
  /// Defaults to `true`.
  final bool showCheckbox;

  @override
  State<DjiLoadAlert> createState() => _DjiLoadAlertState();
}

class _DjiLoadAlertState extends State<DjiLoadAlert> {
  bool _doNotShowAgain = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cargar la misión en DJI Fly'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Paso 1 · Misión vacía",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Text(
                "Abre DJI Fly, crea una misión de waypoints con 1 o 2 puntos, guárdala y cierra la app por completo."),
            const SizedBox(height: 8),
            const Text("Paso 2 · Ubica la carpeta",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Text("▪ iPhone: Archivos › DJI Fly › wayline_mission"),
            const Text(
                "▪ Android / DJI RC: Android/data/dji.go.v5/files/waypoint"),
            const Text(
                "Entra a la carpeta más reciente. Su nombre es un código como 6103D3C8-E79A-4B48-BBFE-50932D2E1306.",
                style: TextStyle(fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            const Text("Paso 3 · Reemplaza el archivo",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Text(
                "Renombra el KMZ descargado con el mismo nombre de esa carpeta (ej. 6103D3C8-....kmz) y reemplaza el KMZ que hay adentro."),
            const SizedBox(height: 8),
            const Text("Paso 4 · Vuela",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Text(
                "Abre DJI Fly, carga la misión (queda de primera en la lista) y revisa todos los puntos antes de despegar."),
            const SizedBox(height: 8),
            Text(
                "No modifiques ni guardes la misión dentro de DJI Fly: no admite trayectorias rectas y la dañaría.",
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: widget.showCheckbox
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.end,
          children: [
            if (widget.showCheckbox)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox.adaptive(
                      value: _doNotShowAgain,
                      onChanged: (value) =>
                          setState(() => _doNotShowAgain = value!)),
                  GestureDetector(
                      onTap: () => setState(() {
                            _doNotShowAgain = !_doNotShowAgain;
                          }),
                      child: const Text("No volver a mostrar")),
                ],
              ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                prefs.setBool("djiWarningDoNotShow", _doNotShowAgain);
              },
              child: const Text('Entendido'),
            ),
          ],
        ),
      ],
    );
  }
}
