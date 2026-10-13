import 'package:ymapper/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LitchiLoadAlert extends StatefulWidget {
  const LitchiLoadAlert({super.key, this.showCheckbox = true});

  /// Whether to show the "Do not show again" checkbox.
  ///
  /// Defaults to `true`.
  final bool showCheckbox;

  @override
  State<LitchiLoadAlert> createState() => _LitchiLoadAlertState();
}

class _LitchiLoadAlertState extends State<LitchiLoadAlert> {
  bool _doNotShowAgain = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cargar la misión en Litchi'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Paso 1", style: TextStyle(fontWeight: FontWeight.bold)),
            RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: <TextSpan>[
                  const TextSpan(text: '• Entra a '),
                  TextSpan(
                    text: 'Litchi Mission Hub',
                    style: const TextStyle(
                      color: Colors.blue,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap =
                          () => launchUrl(Uri.https('flylitchi.com', '/hub')),
                  ),
                  const TextSpan(text: ' e inicia sesión.'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text("Paso 2", style: TextStyle(fontWeight: FontWeight.bold)),
            const Text(
                "• Configura los ajustes; los importantes están resaltados en azul."),
            const SizedBox(height: 4),
            Image.asset(
              'assets/litchi_alert/settings.jpg',
              width: 400,
            ),
            const SizedBox(height: 4),
            const Text(
              "La acción al terminar debe ser la misma que elegiste en OrigenLabs Mapper",
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 10),
            const Text("Paso 3", style: TextStyle(fontWeight: FontWeight.bold)),
            const Text(
                "• Haz clic en 'Missions -> Import' y elige el archivo de la misión."),
            const SizedBox(height: 4),
            Image.asset('assets/litchi_alert/import.jpg', width: 150),
            const SizedBox(height: 10),
            const Text("Paso 4", style: TextStyle(fontWeight: FontWeight.bold)),
            const Text(
                "• Guarda la misión con un nombre y se sincronizará con tu dispositivo."),
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
                prefs.setBool("litchiWarningDoNotShow", _doNotShowAgain);
              },
              child: const Text('Entendido'),
            ),
          ],
        ),
      ],
    );
  }
}
