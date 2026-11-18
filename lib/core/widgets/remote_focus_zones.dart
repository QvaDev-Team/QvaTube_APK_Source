import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Navegación con el mando de la tele (o el teclado) entre las zonas de la
/// pantalla principal: barra superior, menú lateral, contenido y mini
/// reproductor.
///
/// Cada sección del contenido vive en su propio `Navigator`, y Flutter no
/// saca el foco de ese ámbito con las flechas: desde las carátulas nunca se
/// llegaba al menú ni a la barra. Aquí, cuando una flecha ya no tiene a
/// dónde ir dentro de una zona, el foco salta a la zona vecina:
/// - contenido ← → menú (a la sección activa) y → vuelve a la última
///   carátula enfocada;
/// - contenido ↑ → barra superior; barra ↓ → contenido;
/// - contenido/menú ↓ → mini reproductor; mini reproductor ↑ → contenido.
class RemoteFocusZones extends StatefulWidget {
  const RemoteFocusZones({
    super.key,
    required this.top,
    required this.menu,
    required this.content,
    required this.mini,
    required this.menuNodes,
    required this.menuIndex,
    required this.layout,
    this.focusMenuOnStart = false,
  });

  final Widget top;
  final Widget menu;
  final Widget content;
  final Widget mini;

  /// Foco de cada entrada del menú (mismo orden que las secciones).
  final List<FocusNode> menuNodes;

  /// Sección activa: al cambiarla se olvida el último foco del contenido.
  final int menuIndex;

  /// Coloca las cuatro zonas (ya envueltas) en pantalla.
  final Widget Function(Widget top, Widget menu, Widget content, Widget mini)
  layout;

  /// Si nada tiene el foco al abrir, empezar en la sección activa del menú
  /// (en la tele no hay ratón con el que empezar).
  final bool focusMenuOnStart;

  @override
  State<RemoteFocusZones> createState() => _RemoteFocusZonesState();
}

class _RemoteFocusZonesState extends State<RemoteFocusZones> {
  final FocusNode _topZone = _zone('zona-barra');
  final FocusNode _menuZone = _zone('zona-menu');
  final FocusNode _contentZone = _zone('zona-contenido');
  final FocusNode _miniZone = _zone('zona-mini-reproductor');

  /// Último elemento del contenido que tuvo el foco (para volver a él).
  FocusNode? _lastContent;

  static FocusNode _zone(String label) =>
      FocusNode(debugLabel: label, canRequestFocus: false, skipTraversal: true);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_trackContentFocus);
    if (widget.focusMenuOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (primary == null ||
            primary.context == null ||
            primary is FocusScopeNode) {
          _focusMenu();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant RemoteFocusZones oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.menuIndex != widget.menuIndex) _lastContent = null;
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_trackContentFocus);
    for (final node in [_topZone, _menuZone, _contentZone, _miniZone]) {
      node.dispose();
    }
    super.dispose();
  }

  void _trackContentFocus() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null &&
        primary is! FocusScopeNode &&
        primary.ancestors.contains(_contentZone)) {
      _lastContent = primary;
    }
  }

  bool _move(TraversalDirection direction) =>
      FocusManager.instance.primaryFocus?.focusInDirection(direction) ?? false;

  void _focusMenu() {
    final index = widget.menuIndex.clamp(0, widget.menuNodes.length - 1);
    widget.menuNodes[index].requestFocus();
  }

  /// `false` si [node] está en una sección oculta (las otras pestañas siguen
  /// montadas detrás de un Offstage y su foco no se debe usar).
  static bool _isShown(FocusNode node) {
    RenderObject? render = node.context?.findRenderObject();
    if (render == null || !render.attached) return false;
    while (render != null) {
      if (render is RenderOffstage && render.offstage) return false;
      render = render.parent;
    }
    return true;
  }

  static bool _focusFirstIn(FocusNode zone) {
    for (final node in zone.traversalDescendants) {
      if (node is! FocusScopeNode && _isShown(node)) {
        node.requestFocus();
        return true;
      }
    }
    return false;
  }

  void _focusContent() {
    final last = _lastContent;
    if (last != null &&
        last.context != null &&
        last.canRequestFocus &&
        _isShown(last)) {
      last.requestFocus();
    } else {
      _focusFirstIn(_contentZone);
    }
  }

  static bool _isArrow(KeyEvent event) =>
      (event is KeyDownEvent || event is KeyRepeatEvent) &&
      (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown);

  KeyEventResult _onContentKey(FocusNode _, KeyEvent event) {
    if (!_isArrow(event)) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!_move(TraversalDirection.left)) _focusMenu();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _move(TraversalDirection.right);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (!_move(TraversalDirection.up)) _focusFirstIn(_topZone);
    } else {
      if (!_move(TraversalDirection.down)) _focusFirstIn(_miniZone);
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _onMenuKey(FocusNode _, KeyEvent event) {
    if (!_isArrow(event)) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _focusContent();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (!_move(TraversalDirection.down)) _focusFirstIn(_miniZone);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored; // arriba sube a la barra (misma zona)
  }

  KeyEventResult _onTopKey(FocusNode _, KeyEvent event) {
    if (!_isArrow(event)) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _focusContent();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (!_move(TraversalDirection.left)) _focusMenu();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onMiniKey(FocusNode _, KeyEvent event) {
    if (!_isArrow(event)) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _focusContent();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    Widget wrap(FocusNode node, FocusOnKeyEventCallback onKey, Widget child) =>
        Focus(focusNode: node, onKeyEvent: onKey, child: child);
    return widget.layout(
      wrap(_topZone, _onTopKey, widget.top),
      wrap(_menuZone, _onMenuKey, widget.menu),
      wrap(_contentZone, _onContentKey, widget.content),
      wrap(_miniZone, _onMiniKey, widget.mini),
    );
  }
}
