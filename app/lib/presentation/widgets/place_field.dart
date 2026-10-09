import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/settings.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../l10n/generated/app_localizations.dart';

/// Text field with debounced geocoding autocomplete.
///
/// Shows an explicit "no results" state instead of inventing matches, and
/// surfaces provider failures inline (never silently).
class PlaceField extends ConsumerStatefulWidget {
  const PlaceField({
    super.key,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.initial,
  });

  final String label;
  final IconData icon;
  final ValueChanged<GeoPoint> onSelected;
  final GeoPoint? initial;

  @override
  ConsumerState<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends ConsumerState<PlaceField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial?.name ?? '');
  Timer? _debounce;
  List<GeoPoint> _matches = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String query) async {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _matches = const [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final results =
            await ref.read(repositoriesProvider).geocode.geocode(query.trim());
        if (!mounted) return;
        setState(() => _matches = results);
      } on Failure catch (e) {
        if (!mounted) return;
        setState(() {
          _matches = const [];
          _error = e.message;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _matches = const [];
          _error = e.toString();
        });
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: Icon(widget.icon),
            suffixIcon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          onChanged: _onChanged,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              _error!,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ),
        if (_matches.isEmpty &&
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
        for (final match in _matches)
          ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined, size: 20),
            title: Text(match.name ?? '${match.lat}, ${match.lon}'),
            subtitle: match.tz == null ? null : Text(match.tz!),
            onTap: () {
              _debounce?.cancel();
              _controller.text = match.name ?? '${match.lat}, ${match.lon}';
              setState(() => _matches = const []);
              widget.onSelected(match);
              FocusScope.of(context).unfocus();
            },
          ),
      ],
    );
  }
}
