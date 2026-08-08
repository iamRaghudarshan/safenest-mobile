/// Edit profile — the name AND the photo.
///
/// The photo half was simply absent. The web app's row has said "Change your
/// name or photo" since the beginning, `POST /api/auth/avatar` and
/// `DELETE /api/auth/avatar` have both existed all along, and the Avatar widget
/// in this app already renders `avatar_url` — so the phone could DISPLAY a
/// profile picture and offered no way on earth to set one. It could only ever
/// be put there from the laptop.
///
/// The upload is a plain multipart POST of the original bytes. The server does
/// the work that matters — centre-crops to a square and downscales to a small
/// JPEG — so there is nothing to reimplement here, and resizing on the phone
/// first would only mean two different croppers to keep in agreement.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import 'brand_button.dart';

class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({super.key});

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  late final TextEditingController _name;
  bool _busy = false;
  String? _error;

  /// The picked image, held only until it is sent. Shown as a preview so the
  /// person sees what they chose before committing to it.
  Uint8List? _picked;
  String _pickedName = 'photo.jpg';

  /// Set when Remove is pressed, applied on Save — so it can be changed of mind
  /// about without having already destroyed the old photo.
  bool _removing = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<Session>().user;
    _name = TextEditingController(text: '${user?['name'] ?? ''}');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.image,
        // The bytes, not a path: on iOS a picked photo may live in a container
        // the app cannot re-open later, and this is uploaded immediately anyway.
        withData: true,
      );
      final f = res?.files.firstOrNull;
      if (f == null) return;
      final bytes = f.bytes;
      if (bytes == null) {
        setState(() => _error = 'That image could not be read from your phone.');
        return;
      }
      // Refused here as well as at the server. 8 MB is the server's limit, and
      // finding that out after uploading eight megabytes over a home connection
      // is a slow way to be told no.
      if (bytes.length > 8 * 1024 * 1024) {
        setState(() => _error =
            'That photo is larger than 8 MB. Pick a smaller one.');
        return;
      }
      setState(() {
        _picked = bytes;
        _pickedName = f.name;
        _removing = false;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not open your photos.');
    }
  }

  Future<void> _save() async {
    final session = context.read<Session>();
    final navigator = Navigator.of(context);
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Your name needs at least two characters.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.api.put('/api/auth/profile', {'name': name});

      if (_removing) {
        await session.api.delete('/api/auth/avatar');
      } else if (_picked != null) {
        // postMultipartJson, not postMultipart: this endpoint answers "Image
        // too large (max 8 MB)" and "That file isn't a readable image", and a
        // bool would throw both away and leave somebody pressing the button
        // again.
        await session.api.postMultipartJson(
          '/api/auth/avatar',
          fileField: 'file',
          filename: _pickedName,
          bytes: _picked!,
        );
      }

      await session.refreshUser();
      navigator.pop(true);
    } on ApiError catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = context.watch<Session>();
    final user = session.user;
    final base = session.baseUrl ?? '';
    final avatarUrl = '${user?['avatar_url'] ?? ''}';
    final hasServerPhoto = avatarUrl.isNotEmpty && !_removing;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          22, 0, 22, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Edit profile', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 18),

          // The photo, big enough to judge. A 40px avatar is for a header; when
          // choosing one you want to see what it actually looks like.
          Center(
            child: Stack(children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kBrand, kBrand2],
                  ),
                  boxShadow: softShadow(theme.brightness == Brightness.dark),
                ),
                clipBehavior: Clip.antiAlias,
                child: _picked != null
                    ? Image.memory(_picked!,
                        fit: BoxFit.cover, width: 96, height: 96)
                    : hasServerPhoto
                        ? Image.network(
                            avatarUrl.startsWith('http')
                                ? avatarUrl
                                : '$base$avatarUrl',
                            fit: BoxFit.cover,
                            width: 96,
                            height: 96,
                            errorBuilder: (_, _, _) => _initials(user, 96),
                          )
                        : _initials(user, 96),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: theme.colorScheme.surface,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _busy ? null : _pick,
                    child: const Padding(
                      padding: EdgeInsets.all(7),
                      child: Icon(Icons.photo_camera_outlined,
                          size: 18, color: kBrand),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
            TextButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(hasServerPhoto || _picked != null
                  ? 'Change photo'
                  : 'Upload photo'),
            ),
            if (hasServerPhoto || _picked != null)
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _picked = null;
                          _removing = avatarUrl.isNotEmpty;
                        }),
                icon: const Icon(Icons.delete_outline, size: 18, color: kDanger),
                label: const Text('Remove', style: TextStyle(color: kDanger)),
              ),
          ]),
          if (_removing) ...[
            const SizedBox(height: 4),
            Text('Your photo will be removed when you save.',
                style: theme.textTheme.bodySmall),
          ],

          const SizedBox(height: 18),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Your name'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            // Said plainly rather than shown as a disabled box: the address is
            // the login identity, and only an admin can move it.
            child: Text(
                'Your email is ${user?['email'] ?? ''} and can only be changed '
                'by an administrator.',
                style: theme.textTheme.bodySmall),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          ],
          const SizedBox(height: 18),
          BrandButton(
              label: 'Save', block: true, busy: _busy, onPressed: _busy ? null : _save),
        ]),
      ),
    );
  }

  Widget _initials(Map<String, dynamic>? user, double size) {
    final name = '${user?['name'] ?? ''}'.trim();
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.isEmpty
        ? '?'
        : parts.take(2).map((p) => p[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      child: Text(letters,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.34)),
    );
  }
}
