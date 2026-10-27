import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../state/app_state.dart';
import '../widgets/osm_map.dart';
import '../widgets/song_widgets.dart';
import 'location_picker_screen.dart';

/// Formulario del administrador para agregar o editar una canción.
class SongFormScreen extends StatefulWidget {
  final Song? song;
  const SongFormScreen({super.key, this.song});

  @override
  State<SongFormScreen> createState() => _SongFormScreenState();
}

class _SongFormScreenState extends State<SongFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.song?.title);
  late final _artist = TextEditingController(text: widget.song?.artist);
  late final _year = TextEditingController(
    text: widget.song?.year?.toString() ?? '',
  );
  late final _genre = TextEditingController(text: widget.song?.genre);
  late final _event = TextEditingController(text: widget.song?.event);
  late final _history = TextEditingController(text: widget.song?.history);
  late final _meaning = TextEditingController(text: widget.song?.meaning);
  late final _lyrics = TextEditingController(text: widget.song?.lyrics);
  late final _audio = TextEditingController(text: widget.song?.audioUrl);
  late final _external = TextEditingController(text: widget.song?.externalUrl);
  late final _place = TextEditingController(text: widget.song?.placeName);

  late String? _image = widget.song?.imageBase64;
  late LatLng? _location = widget.song?.hasLocation == true
      ? LatLng(widget.song!.latitude!, widget.song!.longitude!)
      : null;
  bool _saving = false;

  bool get _editing => widget.song != null;

  @override
  void dispose() {
    for (final c in [
      _title,
      _artist,
      _year,
      _genre,
      _event,
      _history,
      _meaning,
      _lyrics,
      _audio,
      _external,
      _place,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 900,
      maxHeight: 900,
      imageQuality: 70,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 300 * 1024) {
      _snack('La imagen supera los 300 KB. Elige una imagen más pequeña.');
      return;
    }
    setState(() => _image = base64Encode(bytes));
  }

  Future<void> _pickLocation() async {
    final p = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initial: _location),
      ),
    );
    if (p != null) setState(() => _location = p);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  String? _url(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final u = Uri.tryParse(v.trim());
    return (u == null || !u.hasScheme || !u.scheme.startsWith('http'))
        ? 'Debe ser un enlace que empiece con https://'
        : null;
  }

  Future<void> _save() async {
    if (_saving) return;

    if (!_form.currentState!.validate()) {
      _snack('Revisa los campos marcados en rojo');
      return;
    }

    setState(() => _saving = true);

    final song = Song(
      id: widget.song?.id ?? '',
      title: _title.text.trim(),
      artist: _artist.text.trim(),
      year: int.tryParse(_year.text.trim()),
      genre: _genre.text.trim(),
      event: _event.text.trim(),
      history: _history.text.trim(),
      meaning: _meaning.text.trim(),
      lyrics: _lyrics.text.trim(),
      imageBase64: _image,
      audioUrl: _audio.text.trim(),
      externalUrl: _external.text.trim(),
      placeName: _place.text.trim(),
      latitude: _location?.latitude,
      longitude: _location?.longitude,
      createdAt: widget.song?.createdAt ?? DateTime.now(),
    );

    try {
      await context
          .read<AppState>()
          .backend
          .saveSong(song)
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;

      _snack(_editing ? 'Canción actualizada' : 'Canción agregada');
      Navigator.of(context).pop();
    } on TimeoutException {
      if (!mounted) return;
      _snack(
        'La operación tardó demasiado. '
        'Revisa el catálogo antes de volver a guardar.',
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Error al guardar: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Editar canción' : 'Nueva canción'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            _header('Imagen'),
            _imagePicker(),
            _header('Datos de la canción'),
            _field(_title, 'Nombre de la canción *', validator: _required),
            _field(_artist, 'Banda / artista *', validator: _required),
            Row(
              children: [
                Expanded(
                  child: _field(
                    _year,
                    'Año',
                    keyboard: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final y = int.tryParse(v.trim());
                      return (y == null || y < 1000 || y > 2100)
                          ? 'Año inválido'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _field(_genre, 'Género')),
              ],
            ),
            _header('Historia'),
            _field(
              _event,
              'Suceso que representa *',
              hint: 'Ej. Guerra en Afganistán',
              validator: _required,
            ),
            _field(
              _history,
              'Contexto del suceso',
              hint: '¿Qué pasó? ¿Cuándo? ¿A quién afectó?',
              lines: 5,
            ),
            _field(
              _meaning,
              'Doble sentido / significado oculto',
              hint: '¿Qué dice la canción entre líneas?',
              lines: 5,
            ),
            _field(_lyrics, 'Letra', lines: 10),
            _header('Audio'),
            _field(
              _audio,
              'Enlace directo al audio (mp3)',
              hint: 'https://.../cancion.mp3',
              keyboard: TextInputType.url,
              validator: _url,
            ),
            _field(
              _external,
              'Enlace de YouTube o Spotify',
              hint: 'https://youtube.com/...',
              keyboard: TextInputType.url,
              validator: _url,
            ),
            _header('Ubicación (opcional)'),
            _field(
              _place,
              'Lugar donde se creó',
              hint: 'Ej. Kabul, Afganistán',
            ),
            _locationPicker(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save),
        label: Text(_editing ? 'Guardar cambios' : 'Agregar canción'),
      ),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        fontSize: 12,
      ),
    ),
  );

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    int lines = 1,
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      minLines: lines,
      maxLines: lines == 1 ? 1 : null,
      keyboardType: lines > 1 ? TextInputType.multiline : keyboard,
      textCapitalization: keyboard == TextInputType.url
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: lines > 1,
      ),
    ),
  );

  Widget _imagePicker() => Row(
    children: [
      SongImage(
        base64Image: _image,
        width: 110,
        height: 110,
        radius: BorderRadius.circular(14),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.photo_library),
              label: const Text('Galería'),
              onPressed: () => _pickImage(ImageSource.gallery),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.photo_camera),
              label: const Text('Cámara'),
              onPressed: () => _pickImage(ImageSource.camera),
            ),
            if (_image != null)
              TextButton(
                onPressed: () => setState(() => _image = null),
                child: const Text('Quitar imagen'),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _locationPicker() {
    final loc = _location;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loc != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 160,
              child: OsmMap(
                key: ValueKey(loc),
                center: loc,
                zoom: 5,
                interactive: false,
                markers: [pinMarker(loc)],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_location_alt),
                label: Text(loc == null ? 'Elegir en el mapa' : 'Cambiar'),
                onPressed: _pickLocation,
              ),
            ),
            if (loc != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _location = null),
                child: const Text('Quitar'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
