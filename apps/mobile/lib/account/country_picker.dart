import 'package:flutter/material.dart';

import '../data/catalog/country_catalog.dart';

/// Full-screen searchable picker over the fixed country list (see
/// data/catalog/country_catalog.dart) — a plain dropdown gets unwieldy
/// past a couple hundred entries, so this is a search field over a
/// ListView instead. Returns the picked [Country], or null if the user
/// backs out without picking one.
Future<Country?> pickCountry(BuildContext context, {String? currentCode}) {
  return Navigator.of(context).push<Country>(
    MaterialPageRoute(builder: (_) => _CountryPickerScreen(currentCode: currentCode)),
  );
}

class _CountryPickerScreen extends StatefulWidget {
  const _CountryPickerScreen({this.currentCode});
  final String? currentCode;

  @override
  State<_CountryPickerScreen> createState() => _CountryPickerScreenState();
}

class _CountryPickerScreenState extends State<_CountryPickerScreen> {
  final _controller = TextEditingController();
  List<Country> _results = countries;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final query = _controller.text.trim().toLowerCase();
    setState(() {
      _results = query.isEmpty
          ? countries
          : countries.where((c) => c.name.toLowerCase().contains(query)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search countries…',
            border: InputBorder.none,
          ),
        ),
      ),
      body: ListView.builder(
        itemCount: _results.length,
        itemBuilder: (context, i) {
          final country = _results[i];
          final selected = country.code == widget.currentCode;
          return ListTile(
            title: Text(country.name),
            trailing: selected ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
            onTap: () => Navigator.of(context).pop(country),
          );
        },
      ),
    );
  }
}
