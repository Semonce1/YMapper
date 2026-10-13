import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ymapper/core/mission_store.dart';
import 'package:ymapper/shared/mission_summary.dart';
import 'package:ymapper/shared/value_listeneables.dart';
import 'package:ymapper/theme/origen_theme.dart';

String _fmtDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return "${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}";
}

/// Acciones de guardado usadas desde el encabezado y el menú.
class MissionActions {
  static Future<String?> askName(BuildContext context,
      {String? initial, String title = "Nombre de la misión"}) async {
    final controller = TextEditingController(text: initial ?? "");
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              hintText: "Ej.: Lote 3 Paraíso · topografía inicial"),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar")),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text("Guardar")),
        ],
      ),
    );
  }

  /// Guarda la misión abierta. Si es nueva (o [saveAs]), pide el nombre.
  static Future<void> save(BuildContext context, ValueListenables l,
      {bool saveAs = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    if (l.polygon.length < 3) {
      messenger.showSnackBar(const SnackBar(
          content: Text("Dibuja primero el área para poder guardar")));
      return;
    }
    final data = MissionDoc.fromState(l);
    try {
      if (l.currentMissionId == null || saveAs) {
        final now = DateTime.now();
        final suggestion = saveAs && l.currentMissionName != null
            ? "${l.currentMissionName} (copia)"
            : "Misión ${now.day}/${now.month}/${now.year}";
        final name = await askName(context, initial: suggestion);
        if (name == null || name.isEmpty) return;
        final id = await MissionApi.create(name, data);
        l.currentMissionId = id;
        l.currentMissionName = name;
      } else {
        await MissionApi.update(l.currentMissionId!, data: data);
      }
      messenger.showSnackBar(SnackBar(
          content: Text("Misión \"${l.currentMissionName}\" guardada")));
    } on MissionApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Lista de misiones guardadas, sincronizadas entre dispositivos.
class MissionsPage extends StatefulWidget {
  const MissionsPage({super.key});

  @override
  State<MissionsPage> createState() => _MissionsPageState();
}

class _MissionsPageState extends State<MissionsPage> {
  late Future<List<SavedMission>> _future;
  String? _key;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = MissionApi.list();
    SyncKey.ensure().then((k) {
      if (mounted) setState(() => _key = k);
    });
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> _open(SavedMission m) async {
    final l = Provider.of<ValueListenables>(context, listen: false);
    try {
      final full = await MissionApi.get(m.id);
      final data = (full["data"] as Map).cast<String, dynamic>();
      MissionDoc.applyTo(l, data);
      l.currentMissionId = m.id;
      l.currentMissionName = m.name;
      if (mounted) Navigator.pop(context, true);
    } on MissionApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _rename(SavedMission m) async {
    final name = await MissionActions.askName(context,
        initial: m.name, title: "Cambiar nombre");
    if (name == null || name.isEmpty || name == m.name) return;
    try {
      await MissionApi.update(m.id, name: name);
      if (!mounted) return;
      final l = Provider.of<ValueListenables>(context, listen: false);
      if (l.currentMissionId == m.id) l.currentMissionName = name;
      setState(_reload);
    } on MissionApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _delete(SavedMission m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Borrar la misión?"),
        content: Text("Se borra \"${m.name}\" de todos tus dispositivos."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancelar")),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: OrigenColors.danger,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Borrar")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MissionApi.delete(m.id);
      if (!mounted) return;
      final l = Provider.of<ValueListenables>(context, listen: false);
      if (l.currentMissionId == m.id) {
        l.currentMissionId = null;
        l.currentMissionName = null;
      }
      setState(_reload);
    } on MissionApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _newMission() async {
    final l = Provider.of<ValueListenables>(context, listen: false);
    l.currentMissionId = null;
    l.currentMissionName = null;
    l.polygon = [];
    l.homePoint = null;
    l.gcps = [];
    Navigator.pop(context, true);
  }

  Future<void> _enterKey() async {
    final controller = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Usar el código de otro dispositivo"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                "Escribe el código que aparece en tu otro dispositivo, en Mis misiones. Verás las mismas misiones en ambos.",
                style: TextStyle(fontSize: 13, color: OrigenColors.textMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                  fontFamily: 'monospace', letterSpacing: 1.2),
              decoration:
                  const InputDecoration(hintText: "XXXX-XXXX-XXXX-XXXX-XXXX"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar")),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text("Usar código")),
        ],
      ),
    );
    if (key == null) return;
    final normalized = SyncKey.normalize(key);
    if (normalized == null) {
      _snack("El código debe tener 20 letras y números (A–Z, 2–7)");
      return;
    }
    await SyncKey.save(normalized);
    if (mounted) setState(_reload);
    _snack("Código actualizado");
  }

  @override
  Widget build(BuildContext context) {
    final current =
        Provider.of<ValueListenables>(context).currentMissionId;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: OrigenColors.background,
        title: const Text("Mis misiones"),
        actions: [
          IconButton(
              tooltip: "Actualizar",
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: OrigenColors.accent,
        foregroundColor: OrigenColors.onAccent,
        onPressed: _newMission,
        icon: const Icon(Icons.add),
        label: const Text("Nueva misión"),
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<SavedMission>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("${snap.error}",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: OrigenColors.textMuted)),
                          const SizedBox(height: 12),
                          OutlinedButton(
                              onPressed: () => setState(_reload),
                              child: const Text("Reintentar")),
                        ],
                      ),
                    ),
                  );
                }
                final missions = snap.data ?? [];
                if (missions.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                          "Todavía no tienes misiones guardadas.\nDibuja un área y toca el ícono de guardar arriba.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: OrigenColors.textMuted)),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: missions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final m = missions[i];
                    final s = m.summary;
                    final parts = <String>[
                      _fmtDate(m.updatedAt),
                      if (s["areaHa"] is num)
                        "${fmtNum((s["areaHa"] as num).toDouble(), 2)} ha",
                      if (s["photos"] is num && s["photos"] > 0)
                        "${s["photos"]} fotos",
                      if (s["altitude"] is num) "${s["altitude"]} m",
                    ];
                    final isOpen = m.id == current;
                    return Material(
                      color: OrigenColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _open(m),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: isOpen
                                    ? OrigenColors.accent
                                    : OrigenColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.map_outlined,
                                  color: OrigenColors.accent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(m.name,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(parts.join(" · "),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: OrigenColors.textMuted)),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: "Opciones",
                                color: OrigenColors.surface,
                                onSelected: (v) =>
                                    v == "rename" ? _rename(m) : _delete(m),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: "rename",
                                      child: Text("Cambiar nombre")),
                                  PopupMenuItem(
                                      value: "delete", child: Text("Borrar")),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: BoxDecoration(
                  color: OrigenColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Código de sincronización",
                            style: TextStyle(
                                fontSize: 12,
                                color: OrigenColors.textMuted)),
                        SelectableText(_key ?? "…",
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 15,
                                letterSpacing: 1.1,
                                fontWeight: FontWeight.w600)),
                        const Text(
                            "Ingrésalo en tu otro dispositivo para ver las mismas misiones. No lo compartas.",
                            style: TextStyle(
                                fontSize: 11,
                                color: OrigenColors.textMuted)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: "Copiar código",
                    onPressed: _key == null
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: _key!));
                            _snack("Código copiado");
                          },
                    icon: const Icon(Icons.copy),
                  ),
                  IconButton(
                    tooltip: "Usar otro código",
                    onPressed: _enterKey,
                    icon: const Icon(Icons.vpn_key_outlined),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
