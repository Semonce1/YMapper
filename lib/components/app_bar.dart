import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ymapper/components/popups/dji_load_alert.dart';
import 'package:ymapper/components/popups/litchi_load_alert.dart';
import 'package:ymapper/theme/origen_theme.dart';

/// Menú del encabezado: ayuda para cargar misiones, código y créditos.
class MappingAppBarMenu extends StatelessWidget {
  const MappingAppBarMenu({super.key});

  Future<void> _about(BuildContext context) async {
    String version = "";
    try {
      final info = await PackageInfo.fromPlatform();
      version = "Versión ${info.version} (${info.buildNumber})";
    } catch (_) {}
    if (!context.mounted) return;
    showAboutDialog(
      context: context,
      applicationName: "OrigenLabs Mapper",
      applicationVersion: version,
      applicationIcon: Image.asset("assets/logo.png", width: 56),
      applicationLegalese:
          "© OrigenLabs. Basado en YMapper © 2024 Yaroslav Syubayev, licencia MIT.",
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: "Menú",
      color: OrigenColors.surface,
      icon: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xEB12161B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OrigenColors.border),
        ),
        child: const Icon(Icons.menu, color: OrigenColors.text, size: 20),
      ),
      padding: EdgeInsets.zero,
      onSelected: (value) {
        switch (value) {
          case "dji":
            showDialog(
                context: context,
                builder: (_) => const DjiLoadAlert(showCheckbox: false));
          case "litchi":
            showDialog(
                context: context,
                builder: (_) => const LitchiLoadAlert(showCheckbox: false));
          case "github":
            launchUrl(Uri.https("github.com", "Semonce1/YMapper"));
          case "about":
            _about(context);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
            value: "dji",
            child: ListTile(
                leading: Icon(Icons.help_outline),
                title: Text("Cargar en DJI Fly"))),
        PopupMenuItem(
            value: "litchi",
            child: ListTile(
                leading: Icon(Icons.help_outline),
                title: Text("Cargar en Litchi"))),
        PopupMenuItem(
            value: "github",
            child: ListTile(
                leading: Icon(Icons.code), title: Text("Código fuente"))),
        PopupMenuItem(
            value: "about",
            child: ListTile(
                leading: Icon(Icons.info_outline), title: Text("Acerca de"))),
      ],
    );
  }
}
