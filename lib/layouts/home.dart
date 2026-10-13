import 'dart:async';

import 'package:dio/dio.dart';
import 'package:ymapper/components/app_bar.dart';
import 'package:ymapper/core/drone_mapping_engine.dart';
import 'package:ymapper/core/mission_tools.dart';
import 'package:ymapper/github/update_checker.dart';
import 'package:ymapper/layouts/export.dart';
import 'package:ymapper/layouts/gcp.dart';
import 'package:ymapper/layouts/steps/step_area.dart';
import 'package:ymapper/layouts/steps/step_mission.dart';
import 'package:ymapper/layouts/steps/step_params.dart';
import 'package:ymapper/theme/origen_theme.dart';
import 'package:ymapper/main.dart';
import 'package:ymapper/presets/preset_manager.dart';
import 'package:ymapper/shared/map_provider.dart';
import 'package:ymapper/shared/value_listeneables.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared/aircraft_settings.dart';

enum MapLayer { streets, satellite }

class HomeLayout extends StatefulWidget {
  const HomeLayout({super.key});

  @override
  State<HomeLayout> createState() => _HomeLayoutState();
}

class _HomeLayoutState extends State<HomeLayout> {
  /// Paso actual del asistente (0 = Área ... 4 = Exportar)
  int _step = 0;

  String? _lastRouteSignature;

  String _routeSignature(ValueListenables l) => [
        l.polygon.map((p) => "${p.latitude},${p.longitude}").join(";"),
        l.homePoint?.toString() ?? "-",
        l.altitude,
        l.groundOffset,
        l.forwardOverlap,
        l.sideOverlap,
        l.rotation,
        l.sensorWidth,
        l.sensorHeight,
        l.focalLength,
        l.imageWidth,
        l.imageHeight,
        l.fillGrid,
        l.createCameraPoints,
        l.lineExtension,
        l.showPoints,
        l.turnMode,
      ].join("|");

  late MapLayer _selectedMapLayer;

  final List<Marker> _photoMarkers = [];

  final _debounce = const Duration(milliseconds: 800);
  Timer? _debounceTimer;
  List<MapSearchLocation> _searchLocations = [];

  final List<Marker> _flightLineArrowMarkers = [];
  final List<Marker> _takeoffLineArrowMarkers = [];
  final List<Marker> _returnLineArrowMarkers = [];

  /// Tramos de la ruta: líneas de captura (amarillo) y giros (punteado)
  final List<Polyline> _routePolylines = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _getLocationAndMoveMap());

    // Satélite por defecto: es lo útil para ubicar el lote
    _selectedMapLayer =
        prefs.getInt("mapLayer") == 0 ? MapLayer.streets : MapLayer.satellite;

    final listenables = Provider.of<ValueListenables>(context, listen: false);

    // Preload aircraft settings
    final aircraftSettings = AircraftSettings.getAircraftSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      listenables.altitude = aircraftSettings.altitude;
      listenables.speed = aircraftSettings.speed;
      listenables.forwardOverlap = aircraftSettings.forwardOverlap;
      listenables.sideOverlap = aircraftSettings.sideOverlap;
      listenables.rotation = aircraftSettings.rotation;
      listenables.delayAtWaypoint = aircraftSettings.delay;
      listenables.cameraAngle = aircraftSettings.cameraAngle;
      listenables.onFinished = aircraftSettings.finishAction;
      listenables.rcLostAction = aircraftSettings.rcLostAction;
      listenables.groundOffset = aircraftSettings.groundOffset;
      listenables.lineExtension = aircraftSettings.lineExtension;
      listenables.batteryMinutes = aircraftSettings.batteryMinutes;
      listenables.turnMode = aircraftSettings.turnMode;
    });

    var cameraPresets = PresetManager.getPresets();

    // Load the latest camera preset
    var latestPresetName = prefs.getString("latestPreset");
    if (latestPresetName == null) {
      latestPresetName = cameraPresets[0].name;
      prefs.setString("latestPreset", latestPresetName);
    }

    // Select the latest camera preset
    listenables.selectedCameraPreset = cameraPresets.firstWhere(
        (element) => element.name == latestPresetName,
        orElse: () => cameraPresets[0]);

    // Load camera settings into the provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      listenables.sensorWidth = listenables.selectedCameraPreset!.sensorWidth;
      listenables.sensorHeight = listenables.selectedCameraPreset!.sensorHeight;
      listenables.focalLength = listenables.selectedCameraPreset!.focalLength;
      listenables.imageWidth = listenables.selectedCameraPreset!.imageWidth;
      listenables.imageHeight = listenables.selectedCameraPreset!.imageHeight;
    });

    // Check for updates
    if (!kIsWeb) {
      UpdateChecker.checkForUpdate().then((latestVersion) => {
            if (latestVersion != null && mounted)
              {
                showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                          title: const Text('Actualización disponible'),
                          content: Text('La versión $latestVersion está disponible. '
                              '¿Quieres descargarla?'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Más tarde')),
                            TextButton(
                                onPressed: () {
                                  prefs.setString(
                                      "ignoreVersion", latestVersion);
                                  Navigator.pop(context);
                                },
                                child: const Text("Ignorar esta versión")),
                            ElevatedButton(
                                child: const Text('Descargar'),
                                onPressed: () {
                                  launchUrl(Uri.https("github.com",
                                      "YLabs-FPV/YMapper/releases/latest"));
                                  Navigator.pop(context);
                                })
                          ],
                        ))
              }
          });
    }
  }

  Future<void> _search(String query) async {
    try {
      var response = await Dio().get(
        "https://nominatim.openstreetmap.org/search",
        queryParameters: {
          "q": query,
          "format": "jsonv2",
          "accept-language": "es",
        },
        options: Options(
          headers: {
            "User-Agent": "OrigenLabs Mapper (https://github.com/Semonce1/YMapper)",
          },
        ),
      );

      List<MapSearchLocation> locations = [];
      for (var location in response.data) {
        locations.add(MapSearchLocation(
          name: location["display_name"],
          type: location["type"],
          location: LatLng(
              double.parse(location["lat"]), double.parse(location["lon"])),
        ));
      }

      setState(() {
        _searchLocations = locations;
      });
    } catch (e) {
      // Silently fail on search errors - network issues or API rate limits
      setState(() {
        _searchLocations = [];
      });
    }
  }

  void _onSearchChanged(
      String query, Function(List<MapSearchLocation>) callback) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(_debounce, () async {
      await _search(query);

      callback(_searchLocations);
    });
  }

  void _getLocationAndMoveMap({bool userRequested = false}) async {
    void tell(String text) {
      if (!userRequested || !mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(text)));
    }

    try {
      if (await Geolocator.isLocationServiceEnabled() == false) {
        tell("La ubicación del dispositivo está desactivada");
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        tell("Permite el acceso a la ubicación en el navegador para usar esta opción");
        return;
      }
      final location = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
              accuracy: userRequested
                  ? LocationAccuracy.high
                  : LocationAccuracy.low));
      if (!mounted) return;
      Provider.of<MapProvider>(context, listen: false)
          .mapController
          .move(LatLng(location.latitude, location.longitude), 18);
    } catch (e) {
      // Sin servicios de ubicación: es una función opcional
      tell("No se pudo obtener tu ubicación");
    }
  }

  void _buildMarkers(ValueListenables listenables) {
    var droneMapping = DroneMappingEngine(
      altitude: listenables.altitude.toDouble(),
      forwardOverlap: listenables.forwardOverlap / 100,
      sideOverlap: listenables.sideOverlap / 100,
      sensorWidth: listenables.sensorWidth,
      sensorHeight: listenables.sensorHeight,
      focalLength: listenables.focalLength,
      imageWidth: listenables.imageWidth,
      imageHeight: listenables.imageHeight,
      angle: listenables.rotation.toDouble(),
      groundOffset: listenables.groundOffset.toDouble(),
      lineExtension: listenables.lineExtension.toDouble(),
    );

    var waypoints = droneMapping.generateWaypoints(
        listenables.polygon,
        listenables.createCameraPoints,
        listenables.fillGrid,
        listenables.homePoint);
    listenables.photoFlags = droneMapping.photoFlags;
    listenables.photoLocations = waypoints;
    if (waypoints.isEmpty) return;

    _photoMarkers.clear();

    for (int i = 0; i < waypoints.length; i++) {
      var photoLocation = waypoints[i];
      final isTurnPoint = i < listenables.photoFlags.length &&
          !listenables.photoFlags[i];
      _photoMarkers.add(Marker(
        point: photoLocation,
        height: 40, // Increased height to fit number
        alignment: Alignment.center,
        rotate: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isTurnPoint)
              Icon(Icons.u_turn_left,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline)
            else if (listenables.createCameraPoints)
              Icon(Icons.photo_camera,
                  size: 20, // Reduced size for better fit
                  color: Theme.of(context).colorScheme.onPrimaryContainer)
            else
              Icon(Icons.place_sharp,
                  size: 20, // Reduced size for better fit
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
            Text(
              // Waypoint number text
              "${i + 1}",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ));
    }
    listenables.flightLine = Polyline(
        points: waypoints,
        strokeWidth: 3,
        color: Theme.of(context).colorScheme.tertiary);

    // Separar la ruta en líneas de captura y tramos de giro: un tramo es de
    // giro cuando une dos puntos de giro (sin foto).
    _routePolylines.clear();
    for (final piece in TurnTools.previewPieces(
        waypoints, listenables.photoFlags, listenables.turnMode)) {
      _routePolylines.add(piece.isTurn
          ? Polyline(
              points: piece.points,
              strokeWidth: 2,
              color: Colors.white.withAlpha(200),
              pattern: StrokePattern.dashed(segments: const [6, 5]))
          : Polyline(
              points: piece.points,
              strokeWidth: 3.5,
              color: OrigenColors.accent,
              borderStrokeWidth: 1,
              borderColor: Colors.black54));
    }
        current = [waypoints[i - 1]];
        currentIsTurn = segIsTurn;
      }
      current.add(waypoints[i]);
    }
    flush();

    // Draw directional arrow markers
    _flightLineArrowMarkers.clear();
    _takeoffLineArrowMarkers.clear();
    _returnLineArrowMarkers.clear();

    if (waypoints.length > 1 && listenables.homePoint != null) {
      const double arrowSpacing = 40.0; // Metres between arrows
      LatLng lastPoint = waypoints[0];
      const distance = Distance();
      double cumulativeDistance = 0.0;

      for (int i = 1; i < waypoints.length; i++) {
        final flagsList = listenables.photoFlags;
        final turnSegment = i < flagsList.length &&
            !flagsList[i - 1] &&
            !flagsList[i];
        if (turnSegment) {
          lastPoint = waypoints[i];
          cumulativeDistance = 0;
          continue;
        }
        cumulativeDistance = _placeArrowMarkers(
            lastPoint,
            waypoints[i],
            arrowSpacing,
            distance,
            cumulativeDistance,
            _flightLineArrowMarkers,
            Theme.of(context).colorScheme.tertiary,
            15);
        lastPoint = waypoints[i];
      }

      // Add dashed takeoff line from home to first waypoint to designate 'Start'
      final home = listenables.homePoint!;
      final first = waypoints.first;
      final last = waypoints.last;
      //final bearing = distance.bearing(home, first);
      //final offsetDistance = 2.0; // metres offset from home
      //final offsetPoint = distance.offset(home, offsetDistance, bearing);

      listenables.takeoffLine = Polyline(
        points: [home, first],
        strokeWidth: 1,
        color: Theme.of(context).colorScheme.primary,
        pattern: StrokePattern.dotted(),
      );

      listenables.returnLine = Polyline(
        points: [home, last],
        strokeWidth: 1,
        color: Theme.of(context).colorScheme.primary,
        pattern: StrokePattern.dotted(),
      );

      _placeArrowMarkers(home, first, arrowSpacing, distance, 0.0,
          _takeoffLineArrowMarkers, Theme.of(context).colorScheme.primary, 10);
      _placeArrowMarkers(last, home, arrowSpacing, distance, 0.0,
          _returnLineArrowMarkers, Theme.of(context).colorScheme.primary, 10);
    } else {
      listenables.takeoffLine = null;
      listenables.returnLine = null;
      _flightLineArrowMarkers.clear();
      _takeoffLineArrowMarkers.clear();
      _returnLineArrowMarkers.clear();
    }
  }

  // Add directional arrows along a given segment of fromPoint to toPoint facing the arrows to the toPoint
  double _placeArrowMarkers(
      LatLng fromPoint,
      LatLng toPoint,
      double arrowSpacing,
      var distance,
      double cumulativeDistance,
      List<Marker> targetArrowMarkers,
      Color arrowColour,
      double arrowSize) {
    double segmentDistance = distance.as(LengthUnit.Meter, fromPoint, toPoint);
    double distAlong = arrowSpacing - (cumulativeDistance % arrowSpacing);

    while (distAlong < segmentDistance) {
      double fraction = distAlong / segmentDistance;
      double bearing = distance.bearing(fromPoint, toPoint);

      // Interpolate position along the segment
      LatLng arrowPos = LatLng(
        fromPoint.latitude + fraction * (toPoint.latitude - fromPoint.latitude),
        fromPoint.longitude +
            fraction * (toPoint.longitude - fromPoint.longitude),
      );

      targetArrowMarkers.add(Marker(
        point: arrowPos,
        width: arrowSize + 5,
        height: arrowSize + 5,
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: ((bearing - 90) * pi / 180),
          child: Icon(
            Icons.arrow_forward,
            size: arrowSize,
            color: arrowColour,
          ),
        ),
      ));

      distAlong += arrowSpacing;
    }

    cumulativeDistance += segmentDistance;

    return cumulativeDistance;
  }

  static const _stepTitles = [
    "Área de vuelo",
    "Parámetros",
    "Misión",
    "Puntos de control",
    "Exportar a DJI Fly",
  ];
  static const _nextLabels = [
    "Siguiente: parámetros",
    "Generar misión",
    "Siguiente: puntos de control",
    "Siguiente: exportar",
  ];

  void _goTo(int step, ValueListenables listenables) {
    if (step > 0 && listenables.polygon.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Primero marca el despegue y al menos 3 vértices")));
      return;
    }
    setState(() => _step = step);
    if (step == 2 && listenables.polygon.isNotEmpty) {
      // Encuadrar el área completa para revisar la ruta
      final mapController =
          Provider.of<MapProvider>(context, listen: false).mapController;
      mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([
            ...listenables.polygon,
            if (listenables.homePoint != null) listenables.homePoint!,
          ]),
          padding: const EdgeInsets.all(48)));
    }
  }

  Widget _stepBody(ValueListenables listenables) {
    switch (_step) {
      case 0:
        return StepArea(
          onLocate: () => _getLocationAndMoveMap(userRequested: true),
          onChanged: () => setState(() {}),
        );
      case 1:
        return const StepParams();
      case 2:
        return const StepMission();
      case 3:
        return const GcpBar();
      default:
        return const ExportBar();
    }
  }

  Widget _header(ValueListenables listenables) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF212161B), Color(0xCC12161B), Color(0x0012161B)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 18),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("OrigenLabs Mapper · Paso ${_step + 1} de 5",
                          style: const TextStyle(
                              fontSize: 12,
                              letterSpacing: 0.4,
                              color: OrigenColors.textMuted)),
                      Text(_stepTitles[_step],
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const MappingAppBarMenu(),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  for (int i = 0; i < 5; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: "Ir a ${_stepTitles[i]}",
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _goTo(i, listenables),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: i <= _step
                                    ? OrigenColors.accent
                                    : OrigenColors.border,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBox(MapProvider mapProvider) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Autocomplete<MapSearchLocation>(
        optionsBuilder: (textEditingValue) {
          return Future.delayed(_debounce, () async {
            _onSearchChanged(textEditingValue.text, (locations) => locations);
            return _searchLocations;
          });
        },
        onSelected: (option) {
          FocusManager.instance.primaryFocus?.unfocus();
          mapProvider.mapController.move(option.location, 17);
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: OrigenColors.surface,
              elevation: 4.0,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxHeight: 240, maxWidth: 420),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(option.name,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => onSelected(option),
                    );
                  },
                ),
              ),
            ),
          );
        },
        displayStringForOption: (option) => option.name,
        fieldViewBuilder:
            (context, textEditingController, focusNode, onFieldSubmitted) =>
                TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onFieldSubmitted: (value) async {
            await _search(textEditingController.text);
            if (_searchLocations.isNotEmpty) {
              mapProvider.mapController
                  .move(_searchLocations.first.location, 17);
            }
          },
          decoration: InputDecoration(
            hintText: 'Buscar lugar o dirección',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            fillColor: const Color(0xEB12161B),
            suffixIcon: IconButton(
              tooltip: "Limpiar búsqueda",
              icon: const Icon(Icons.close),
              onPressed: () => textEditingController.clear(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mapButton(
      {required IconData icon,
      required String tooltip,
      required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xEB12161B),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OrigenColors.border),
            ),
            child: Icon(icon, size: 20, color: OrigenColors.text),
          ),
        ),
      ),
    );
  }

  Widget _vertexDot(int index) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: OrigenColors.background, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
      ),
      child: Text("${index + 1}",
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: OrigenColors.background)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ValueListenables, MapProvider>(
      builder: (context, listenables, mapProvider, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Recalcular solo si cambió algún dato de la ruta
          final signature = _routeSignature(listenables);
          if (signature == _lastRouteSignature) return;
          _lastRouteSignature = signature;
          if (listenables.polygon.length > 2 && listenables.altitude >= 5) {
            _buildMarkers(listenables);
          } else {
            listenables.photoLocations.clear();
            listenables.photoFlags = [];
            _photoMarkers.clear();
            _routePolylines.clear();
            listenables.flightLine = null;
            listenables.takeoffLine = null;
            listenables.returnLine = null;
            _takeoffLineArrowMarkers.clear();
            _returnLineArrowMarkers.clear();
            _flightLineArrowMarkers.clear();
          }
        });

        final size = MediaQuery.of(context).size;
        final wide = size.width >= 900;

        final map = FlutterMap(
          mapController: mapProvider.mapController,
          options: MapOptions(
            initialCenter: const LatLng(6.2442, -75.5812),
            initialZoom: 15,
            backgroundColor: OrigenColors.background,
            onTap: (tapPosition, point) {
              FocusManager.instance.primaryFocus?.unfocus();
              if (_step != 0) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text("Para editar el área vuelve al paso 1"),
                  action: SnackBarAction(
                      label: "Ir",
                      onPressed: () => _goTo(0, listenables)),
                ));
                return;
              }
              setState(() {
                if (listenables.homePoint == null) {
                  listenables.homePoint = point;
                } else {
                  listenables.polygon = [...listenables.polygon, point];
                }
              });
            },
          ),
          children: [
            TileLayer(
                tileProvider: CancellableNetworkTileProvider(),
                tileBuilder: _selectedMapLayer == MapLayer.streets
                    ? (context, tileWidget, tile) =>
                        darkModeTileBuilder(context, tileWidget, tile)
                    : null,
                urlTemplate: _selectedMapLayer == MapLayer.streets
                    ? 'https://{s}.google.com/vt/lyrs=m&hl=es&x={x}&y={y}&z={z}'
                    : 'https://{s}.google.com/vt/lyrs=y&hl=es&x={x}&y={y}&z={z}',
                userAgentPackageName: 'com.origenlabs.mapper',
                subdomains: const ['mt0', 'mt1', 'mt2', 'mt3']),
            PolygonLayer(polygons: [
              if (listenables.polygon.length > 1)
                Polygon(
                    points: listenables.polygon,
                    color: OrigenColors.accent.withAlpha(36),
                    borderColor: OrigenColors.accent,
                    borderStrokeWidth: 2.5),
            ]),
            if (listenables.homePoint != null)
              PolylineLayer(
                polylines: [
                  ..._routePolylines,
                  if (listenables.takeoffLine != null)
                    listenables.takeoffLine!,
                  if (listenables.returnLine != null) listenables.returnLine!,
                ],
              ),
            MarkerLayer(markers: _flightLineArrowMarkers),
            MarkerLayer(markers: _takeoffLineArrowMarkers),
            MarkerLayer(markers: _returnLineArrowMarkers),
            if (listenables.showPoints) MarkerLayer(markers: _photoMarkers),
            if (listenables.gcps.isNotEmpty)
              MarkerLayer(markers: [
                for (final gcp in listenables.gcps)
                  Marker(
                    point: gcp.position,
                    width: 80,
                    height: 44,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.change_history,
                            size: 22,
                            color: gcp.isCheck
                                ? OrigenColors.check
                                : OrigenColors.gcp),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                              color: Colors.black.withAlpha(170),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(gcp.name,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10)),
                        ),
                      ],
                    ),
                  ),
              ]),
            DragMarkers(markers: [
              for (int i = 0; i < listenables.polygon.length; i++)
                DragMarker(
                  size: const Size(34, 34),
                  point: listenables.polygon[i],
                  alignment: Alignment.center,
                  disableDrag: _step != 0,
                  builder: (_, coords, dragging) =>
                      Center(child: _vertexDot(i)),
                  onLongPress: (_) {
                    if (_step != 0) return;
                    setState(() {
                      listenables.polygon = List.of(listenables.polygon)
                        ..removeAt(i);
                    });
                  },
                  onDragUpdate: (details, latLng) {
                    if (i < listenables.polygon.length) {
                      final updated = List.of(listenables.polygon);
                      updated[i] = latLng;
                      listenables.polygon = updated;
                    }
                  },
                ),
            ]),
            if (listenables.homePoint != null)
              DragMarkers(
                markers: [
                  DragMarker(
                    point: listenables.homePoint!,
                    size: const Size(44, 44),
                    alignment: Alignment.center,
                    disableDrag: _step != 0,
                    onDragUpdate: (details, latLng) {
                      listenables.homePoint = latLng;
                    },
                    builder: (context, coords, isDragging) => Center(
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: OrigenColors.background,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: OrigenColors.accent, width: 2),
                        ),
                        child: const Center(
                          child: Text("H",
                              style: TextStyle(
                                  color: OrigenColors.accent,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        );

        final mapStack = Stack(
          children: [
            Positioned.fill(child: map),
            Positioned(
                top: 0, left: 0, right: 0, child: _header(listenables)),
            if (_step == 0)
              Positioned(
                top: 112 + MediaQuery.of(context).padding.top,
                left: 12,
                right: 64,
                child: _searchBox(mapProvider),
              ),
            Positioned(
              right: 12,
              top: 112 + MediaQuery.of(context).padding.top,
              child: Column(
                children: [
                  _mapButton(
                      icon: _selectedMapLayer == MapLayer.satellite
                          ? Icons.map_outlined
                          : Icons.satellite_alt_outlined,
                      tooltip: _selectedMapLayer == MapLayer.satellite
                          ? "Ver mapa de calles"
                          : "Ver satélite",
                      onTap: () => setState(() {
                            _selectedMapLayer =
                                _selectedMapLayer == MapLayer.streets
                                    ? MapLayer.satellite
                                    : MapLayer.streets;
                            prefs.setInt("mapLayer",
                                _selectedMapLayer == MapLayer.streets ? 0 : 1);
                          })),
                  const SizedBox(height: 8),
                  _mapButton(
                      icon: Icons.my_location,
                      tooltip: "Mi ubicación",
                      onTap: () =>
                          _getLocationAndMoveMap(userRequested: true)),
                  if (listenables.polygon.length > 2) ...[
                    const SizedBox(height: 8),
                    _mapButton(
                        icon: Icons.fit_screen_outlined,
                        tooltip: "Encuadrar el área",
                        onTap: () => mapProvider.mapController.fitCamera(
                            CameraFit.bounds(
                                bounds: LatLngBounds.fromPoints(
                                    listenables.polygon),
                                padding: const EdgeInsets.all(48)))),
                  ],
                ],
              ),
            ),
          ],
        );

        final panel = Container(
          decoration: BoxDecoration(
            color: OrigenColors.surface,
            borderRadius: wide
                ? BorderRadius.zero
                : const BorderRadius.vertical(top: Radius.circular(20)),
            border: const Border(top: BorderSide(color: OrigenColors.border)),
          ),
          child: SafeArea(
            top: wide,
            child: Column(
              children: [
                if (!wide)
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 6),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: OrigenColors.border,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                if (wide) const SizedBox(height: 12),
                Expanded(child: _stepBody(listenables)),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  decoration: const BoxDecoration(
                      border: Border(
                          top: BorderSide(color: OrigenColors.border))),
                  child: Row(
                    children: [
                      if (_step > 0) ...[
                        SizedBox(
                          height: 52,
                          width: 52,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero),
                            onPressed: () => _goTo(_step - 1, listenables),
                            child: const Icon(Icons.arrow_back,
                                semanticLabel: "Atrás"),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: _step < 4
                              ? FilledButton(
                                  onPressed: (_step == 0 &&
                                          listenables.polygon.length < 3)
                                      ? null
                                      : () => _goTo(_step + 1, listenables),
                                  child: Text(_nextLabels[_step]),
                                )
                              : OutlinedButton.icon(
                                  onPressed: () => _goTo(0, listenables),
                                  icon: const Icon(Icons.edit_location_alt),
                                  label: const Text("Editar el área"),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                Expanded(child: mapStack),
                SizedBox(width: 440, child: panel),
              ],
            ),
          );
        }

        final panelFraction = _step == 0 ? 0.42 : 0.56;
        return Scaffold(
          resizeToAvoidBottomInset: false,
          body: Column(
            children: [
              Expanded(child: mapStack),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                height: (size.height * panelFraction).clamp(300.0, 560.0),
                child: panel,
              ),
            ],
          ),
        );
      },
    );
  }
}

class MapSearchLocation {
  final String name;
  final String type;
  final LatLng location;

  MapSearchLocation(
      {required this.name, required this.type, required this.location});
}
