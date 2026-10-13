import 'package:flutter/material.dart';
import 'package:ymapper/theme/origen_theme.dart';

/// Tarjeta pequeña con un dato: etiqueta arriba, valor grande abajo.
class StatTile extends StatelessWidget {
  const StatTile(
      {super.key,
      required this.label,
      required this.value,
      this.unit,
      this.valueColor,
      this.hint});

  final String label;
  final String value;
  final String? unit;
  final Color? valueColor;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: OrigenColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, color: OrigenColors.textMuted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: value,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: valueColor ?? OrigenColors.text)),
              if (unit != null)
                TextSpan(
                    text: " $unit",
                    style: const TextStyle(
                        fontSize: 12, color: OrigenColors.textMuted)),
            ])),
          ),
          if (hint != null)
            Text(hint!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, color: OrigenColors.textMuted)),
        ],
      ),
    );
  }
}

/// Rejilla de [StatTile] con el número de columnas indicado.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.columns = 3});
  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < children.length; i += columns) {
      final rowChildren = <Widget>[];
      for (int j = 0; j < columns; j++) {
        if (j > 0) rowChildren.add(const SizedBox(width: 8));
        rowChildren.add(Expanded(
            child: i + j < children.length
                ? children[i + j]
                : const SizedBox.shrink()));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(IntrinsicHeight(
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rowChildren)));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// Bloque con fondo de superficie y título opcional.
class PanelSection extends StatelessWidget {
  const PanelSection({super.key, this.title, required this.child, this.trailing});
  final String? title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: OrigenColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title!,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// Deslizador con etiqueta a la izquierda y valor a la derecha.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.unit = "",
    this.decimals = 0,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String unit;
  final int decimals;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(label, style: const TextStyle(fontSize: 14))),
            Text(
                "${v.toStringAsFixed(decimals).replaceAll('.', ',')}$unit",
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ),
        SizedBox(
          height: 36,
          child: Slider(
            value: v,
            min: min,
            max: max,
            divisions: divisions,
            label: "${v.toStringAsFixed(decimals).replaceAll('.', ',')}$unit",
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Selector de opciones en forma de pastilla, para pocas opciones.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice(
      {super.key,
      required this.options,
      required this.selected,
      required this.onSelected});

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: OrigenColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final (value, label) in options)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: value == selected
                      ? OrigenColors.accent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => onSelected(value),
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Text(label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: value == selected
                                    ? OrigenColors.onAccent
                                    : OrigenColors.textMuted)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Botón cuadrado de herramienta con ícono y texto.
class ToolButton extends StatelessWidget {
  const ToolButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap,
      this.active = false,
      this.iconColor});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: active ? const Color(0xFF2A2A1C) : OrigenColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: active ? OrigenColors.accent : OrigenColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 22,
                  color: enabled
                      ? (iconColor ?? OrigenColors.text)
                      : OrigenColors.border),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: enabled
                          ? OrigenColors.text
                          : OrigenColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mensaje de estado (correcto / advertencia / error) con ícono.
class StatusLine extends StatelessWidget {
  const StatusLine({super.key, required this.ok, required this.text, this.warn = false});
  final bool ok;
  final bool warn;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = ok
        ? OrigenColors.ok
        : (warn ? OrigenColors.accent : OrigenColors.danger);
    final icon = ok
        ? Icons.check_circle_outline
        : (warn ? Icons.info_outline : Icons.error_outline);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, height: 1.35))),
        ],
      ),
    );
  }
}
