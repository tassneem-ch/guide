import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../application/settings.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../l10n/generated/app_localizations.dart';

/// Text field with debounced place autocomplete.
///
/// Behavior:
/// - suggestions come from the backend's `/v1/places` proxy (Google Places
///   API (New) when configured, keyless geocoding otherwise);
/// - an older in-flight response can never overwrite a newer query
///   (monotonic request sequence + debounce);
/// - selecting a suggestion resolves its REAL coordinates (details call when
///   the provider needs one) before it reaches the planner — typed text is
///   never treated as a location;
/// - `lat, lon` typed directly is accepted as a coordinate-based fallback;
/// - failures show inline with a retry; empty results are explicit.
class PlaceField extends ConsumerStatefulWidget {
  const PlaceField({
    super.key,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.onCleared,
    this.onFocusChanged,
    this.initial,
  });

  final String label;
  final IconData icon;
  final ValueChanged<GeoPoint> onSelected;

  /// Reports whether this field gained or lost focus. Owners use it to make
  /// room for the suggestions list (e.g. by shrinking a bottom sheet) — on
  /// small screens the list is otherwise hidden behind it.
  final ValueChanged<bool>? onFocusChanged;

  /// Called when the current text no longer matches a resolved selection
  /// (cleared, edited, or replaced) — the owner should drop the stale point.
  final VoidCallback? onCleared;
  final GeoPoint? initial;

  @override
  ConsumerState<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends ConsumerState<PlaceField> {
  /// What the field shows for a point: its name when it has one, otherwise
  /// the raw coordinates (honest — the planner really holds that point).
  static String _textFor(GeoPoint? point) =>
      point == null ? '' : (point.name ?? '${point.lat}, ${point.lon}');

  late final TextEditingController _controller =
      TextEditingController(text: _textFor(widget.initial));
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  bool _loading = false;
  String? _error;

  int _seq = 0; // monotonic: responses with a stale sequence are dropped
  PlaceSuggestion? _selected;

  /// The point this field most recently handed to [PlaceField.onSelected].
  /// Its echo back through [PlaceField.initial] is OUR change, not an
  /// external one — the label and selection state must survive it.
  GeoPoint? _lastEmitted;

  /// Whether a real search for the current text completed (its result may
  /// have been empty). Only then is "No results" a truthful statement.
  bool _searched = false;

  late String _session = _newSession();
  GeoPoint? _bias;
  bool _biasTried = false;

  static final Random _random = Random();

  static String _newSession() =>
      'g${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(0x7fffffff).toRadixString(36)}';

  @override
  void didUpdateWidget(covariant PlaceField old) {
    super.didUpdateWidget(old);
    final next = widget.initial;
    final prev = old.initial;
    final changed = next == null
        ? prev != null
        : (prev == null || prev.lat != next.lat || prev.lon != next.lon);
    if (changed && next != null) {
      // The point we just selected, coming back from the planner: not an
      // external change. Keep the visible label (never stomp it with raw
      // coordinates) and keep `_selected` so later edits still invalidate
      // the stored point correctly.
      final echo = _lastEmitted != null &&
          next.lat == _lastEmitted!.lat &&
          next.lon == _lastEmitted!.lon;
      if (echo) return;
      // Reflect an externally changed selection (map tap, swap,
      // my-location). When the selection became null, keep whatever the
      // user is typing.
      _lastEmitted = null;
      _controller.text = _textFor(next);
      _selected = null;
      _suggestions = const [];
      _error = null;
      _searched = false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Best-effort bias from the last known device position. Optional: never
  /// requests permission, never blocks or fails a search.
  Future<GeoPoint?> _bestEffortBias() async {
    if (_biasTried) return _bias;
    _biasTried = true;
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position != null) {
        _bias = GeoPoint(lat: position.latitude, lon: position.longitude);
      }
    } catch (_) {
      // Bias is a preference; losing it changes nothing user-visible.
    }
    return _bias;
  }

  /// Direct coordinate entry ("36.8065, 10.1815") — a real, verifiable
  /// fallback that needs no provider at all.
  GeoPoint? _tryParseCoordinates(String query) {
    final match = RegExp(r'^(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)$')
        .firstMatch(query);
    if (match == null) return null;
    final lat = double.tryParse(match.group(1)!);
    final lon = double.tryParse(match.group(2)!);
    if (lat == null || lon == null) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return GeoPoint(lat: lat, lon: lon);
  }

  Future<void> _onChanged(String raw) async {
    final query = raw.trim();
    _debounce?.cancel();
    _seq++; // whatever is in flight is stale now
    _searched = false; // the current text has not been searched (yet)

    // Editing the text away from the selected place invalidates the stored
    // coordinates — the planner must never keep a point the text no longer
    // describes.
    final selected = _selected;
    if (selected != null && query != selected.label) {
      _selected = null;
      widget.onCleared?.call();
    }

    if (query.length < 2) {
      setState(() {
        _suggestions = const [];
        _error = null;
        _loading = false;
      });
      return;
    }

    final coordinates = _tryParseCoordinates(query);
    if (coordinates != null) {
      setState(() {
        _suggestions = const [];
        _error = null;
        _loading = false;
      });
      // The typed text itself is the label of this point — the planner and
      // any echo back keep showing what the user wrote, not a reformatted
      // version of it.
      final labeled = coordinates.copyWith(name: query);
      _selected = PlaceSuggestion(label: query, point: labeled);
      _lastEmitted = labeled;
      widget.onSelected(labeled);
      return;
    }

    final mySeq = _seq;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _error = null;
      });
      final repos = ref.read(repositoriesProvider);
      try {
        // Warm the bias in the background (fire-and-forget): a location
        // lookup must never delay or break a search — later queries use it
        // once it is available.
        unawaited(_bestEffortBias());
        final results = await repos.geocode.suggest(
          query,
          sessionToken: _session,
          bias: _bias,
        );
        if (!mounted || mySeq != _seq) return; // superseded — drop
        setState(() {
          _suggestions = results;
          _searched = true;
          _loading = false;
        });
      } on Failure catch (e) {
        if (!mounted || mySeq != _seq) return;
        setState(() {
          _suggestions = const [];
          _error = e.message;
          _loading = false;
        });
      } catch (e) {
        if (!mounted || mySeq != _seq) return;
        setState(() {
          _suggestions = const [];
          _error = e.toString();
          _loading = false;
        });
      }
    });
  }

  Future<void> _select(PlaceSuggestion suggestion) async {
    _debounce?.cancel();
    _seq++;
    final mySeq = _seq;
    setState(() {
      _loading = true;
      _error = null;
      _suggestions = const [];
    });
    final repos = ref.read(repositoriesProvider);
    try {
      final point = await repos.geocode.resolveSuggestion(
        suggestion,
        sessionToken: _session,
      );
      if (!mounted || mySeq != _seq) return;
      final label = point.name ?? suggestion.label;
      // The planner stores the label as the point's name so every surface
      // (fields, prayer card, waypoints, persistence) shows the place name
      // instead of bare coordinates.
      final resolved = point.name == null ? point.copyWith(name: label) : point;
      setState(() {
        _selected =
            PlaceSuggestion(id: suggestion.id, label: label, point: resolved);
        _controller.text = label;
        _loading = false;
        _searched = false;
      });
      _session = _newSession(); // selection ends this autocomplete session
      _lastEmitted = resolved;
      widget.onSelected(resolved);
      if (mounted) FocusScope.of(context).unfocus();
    } on Failure catch (e) {
      if (!mounted || mySeq != _seq) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || mySeq != _seq) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _clear() {
    _debounce?.cancel();
    _seq++;
    _controller.clear();
    setState(() {
      _suggestions = const [];
      _error = null;
      _selected = null;
      _lastEmitted = null;
      _searched = false;
      _loading = false;
    });
    _session = _newSession();
    widget.onCleared?.call();
  }

  void _retry() {
    final query = _controller.text.trim();
    if (query.length >= 2) {
      // Fresh session attempt; reuses the normal search path.
      _onChanged(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasText = _controller.text.trim().isNotEmpty;
    // Focus is tracked on the TextField itself so the owner can react to
    // this field only (its suggestions list below needs screen room).
    return Focus(
      onFocusChange: (focused) => widget.onFocusChanged?.call(focused),
      child: _buildField(context, l10n, hasText),
    );
  }

  Widget _buildField(
      BuildContext context, AppLocalizations l10n, bool hasText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: Icon(widget.icon),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (hasText)
                  IconButton(
                    tooltip: l10n.clearInput,
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: _clear,
                  ),
              ],
            ),
          ),
          onChanged: _onChanged,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: Text(l10n.retry),
                ),
              ],
            ),
          ),
        // "No results" only after an actual search came back empty — a
        // field showing a selection (e.g. raw coordinates) was never
        // searched, so claiming "no results" would be a lie.
        if (_searched &&
            _suggestions.isEmpty &&
            _controller.text.trim().length >= 2 &&
            !_loading &&
            _error == null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              l10n.noResults,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        for (final suggestion in _suggestions)
          ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined, size: 20),
            title: Text(suggestion.label),
            onTap: () => _select(suggestion),
          ),
      ],
    );
  }
}
