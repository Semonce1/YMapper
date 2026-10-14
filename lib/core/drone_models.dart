/// Drones que la app conoce y cómo se cargan sus misiones.
///
/// DJI Fly usa el mismo formato de misión (KMZ/WPML) y el mismo código de
/// modelo (`droneEnumValue` 68) en todos sus drones con waypoints: así lo
/// escribe DJI Fly en el Air 3 y así lo exportan otros planificadores para
/// Air 3S, Mini 4 Pro, Mini 5 Pro y Mavic 3.
enum DroneSupport {
  /// Probado con un archivo real de DJI Fly de ese dron.
  verified,

  /// Waypoints de DJI Fly con el mismo formato, sin prueba de campo propia.
  compatible,

  /// Sin waypoints en DJI Fly: solo se puede volar con Litchi (CSV).
  litchiOnly,
}

class DroneModel {
  const DroneModel({
    required this.id,
    required this.name,
    required this.support,
    required this.presets,
  });

  final String id;
  final String name;
  final DroneSupport support;

  /// Nombres de los perfiles de cámara (PresetManager). El primero es el
  /// recomendado para fotogrametría.
  final List<String> presets;

  bool get hasDjiFlyWaypoints => support != DroneSupport.litchiOnly;

  String get supportText => switch (support) {
        DroneSupport.verified =>
          "Verificado con un archivo real de DJI Fly de este dron.",
        DroneSupport.compatible =>
          "Usa los waypoints de DJI Fly con el mismo formato. Aún sin prueba de campo propia: revisa la ruta en DJI Fly antes de volar.",
        DroneSupport.litchiOnly =>
          "Este dron no tiene waypoints en DJI Fly. Exporta el CSV y vuela con Litchi.",
      };
}

class DroneModels {
  static const String defaultId = "air3";
  static const String customId = "custom";

  static const List<DroneModel> all = [
    DroneModel(
      id: "air3",
      name: "DJI Air 3",
      support: DroneSupport.verified,
      presets: ["DJI Air 3 (12 MP)", "DJI Air 3 (48 MP)"],
    ),
    DroneModel(
      id: "air3s",
      name: "DJI Air 3S",
      support: DroneSupport.compatible,
      presets: ["DJI Air 3S (12 MP)", "DJI Air 3S (48 MP)"],
    ),
    DroneModel(
      id: "mini4pro",
      name: "DJI Mini 4 Pro",
      support: DroneSupport.compatible,
      presets: ["DJI Mini 4 Pro (12 MP)", "DJI Mini 4 Pro (48 MP)"],
    ),
    DroneModel(
      id: "mini5pro",
      name: "DJI Mini 5 Pro",
      support: DroneSupport.compatible,
      presets: ["DJI Mini 5 Pro (12MP)", "DJI Mini 5 Pro (48 MP)"],
    ),
    DroneModel(
      id: "mavic3",
      name: "DJI Mavic 3 Classic / 3 Pro",
      support: DroneSupport.compatible,
      presets: ["DJI Mavic 3 (20 MP)"],
    ),
    DroneModel(
      id: "mini3pro",
      name: "DJI Mini 3 Pro",
      support: DroneSupport.litchiOnly,
      presets: ["DJI Mini 3 Pro (12 MP)", "DJI Mini 3 Pro (48 MP)"],
    ),
    DroneModel(
      id: "air2s",
      name: "DJI Air 2S",
      support: DroneSupport.litchiOnly,
      presets: ["Mavic Air 2S (3:4)"],
    ),
    DroneModel(
      id: "mavicair2",
      name: "DJI Mavic Air 2",
      support: DroneSupport.litchiOnly,
      presets: ["Mavic Air 2 (12 MP)"],
    ),
    DroneModel(
      id: "mini2",
      name: "DJI Mini 2",
      support: DroneSupport.litchiOnly,
      presets: ["DJI Mini 2 (12 MP)"],
    ),
    DroneModel(
      id: "mavic2pro",
      name: "DJI Mavic 2 Pro",
      support: DroneSupport.litchiOnly,
      presets: ["DJI Mavic 2 Pro"],
    ),
    DroneModel(
      id: customId,
      name: "Otro (cámara personalizada)",
      support: DroneSupport.compatible,
      presets: [],
    ),
  ];

  static DroneModel byId(String? id) =>
      all.firstWhere((d) => d.id == id, orElse: () => all.first);

  /// Dron al que pertenece un perfil de cámara (para misiones antiguas).
  static DroneModel? forPreset(String? presetName) {
    if (presetName == null) return null;
    for (final d in all) {
      if (d.presets.contains(presetName)) return d;
    }
    return null;
  }

  /// Etiqueta corta del perfil: "12 MP", "48 MP"...
  static String presetLabel(String presetName) {
    final m = RegExp(r'\(([^)]+)\)').firstMatch(presetName);
    return (m?.group(1) ?? presetName).replaceAll("MP", " MP").replaceAll("  ", " ");
  }
}
