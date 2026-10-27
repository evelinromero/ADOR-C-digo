import 'dart:async';
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/song.dart';
import 'seed_songs.dart';

/// Todo lo que la app necesita de "un servidor".
/// Hay dos implementaciones: [FirebaseBackend] (real, con Google) y
/// [LocalBackend] (modo demo, guarda todo en el teléfono).
abstract class Backend {
  bool get isDemo;

  Stream<AppUser?> authChanges();
  Future<void> signInWithGoogle();
  Future<void> signInDemo({required bool admin});
  Future<void> signOut();

  Stream<List<Song>> songs();
  Future<void> saveSong(Song song);
  Future<void> deleteSong(String id);

  Stream<Set<String>> favorites(String uid);
  Future<void> setFavorite(String uid, String songId, bool favorite);
}

// ---------------------------------------------------------------------------
// Firebase
// ---------------------------------------------------------------------------

class FirebaseBackend implements Backend {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _songs =>
      _db.collection('songs');

  @override
  bool get isDemo => false;

  @override
  Stream<AppUser?> authChanges() => _auth.authStateChanges().map((u) {
        if (u == null) return null;
        return AppUser(
          uid: u.uid,
          name: u.displayName ?? u.email ?? 'Usuario',
          email: u.email ?? '',
          photoUrl: u.photoURL,
          isAdmin: isAdminEmail(u.email),
        );
      });


  @override
  Future<void> signInWithGoogle() async {
    UserCredential cred;

    if (kIsWeb) {
      final provider = GoogleAuthProvider()..addScope('email');
      cred = await _auth.signInWithPopup(provider);
    } else {
      final googleSignIn = GoogleSignIn.instance;

      await googleSignIn.initialize(
        serverClientId: '87979743586-4dn2ncelggmmri411e17gkh1nat6ih06.apps.googleusercontent.com',
      );

      final googleUser = await googleSignIn.authenticate();

      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception(
          'Google no devolvió un token de autenticación. '
          'Verifica la configuración de Firebase y SHA-1.',
        );
      }

      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );

      cred = await _auth.signInWithCredential(credential);
    }

    final user = cred.user;

    if (user != null) {
      await _db.collection('users').doc(user.uid).set({
        'name': user.displayName,
        'email': user.email,
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }


  @override
  Future<void> signInDemo({required bool admin}) =>
      throw UnsupportedError('Solo disponible en modo demo');

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Stream<List<Song>> songs() => _songs
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Song.fromMap(d.id, d.data())).toList());

  @override
  Future<void> saveSong(Song song) async {
    try {
      if (song.id.isEmpty) {
        await _songs.add(song.toMap()).timeout(
          const Duration(seconds: 25),
        );
      } else {
        await _songs.doc(song.id).set(song.toMap()).timeout(
          const Duration(seconds: 25),
        );
      }
    } on FirebaseException catch (e) {
      debugPrint('FIREBASE ERROR: ${e.code}');
      debugPrint('FIREBASE MESSAGE: ${e.message}');
      rethrow;
    } on TimeoutException {
      debugPrint('FIREBASE ERROR: timeout');
      rethrow;
    }
  }

  @override
  Future<void> deleteSong(String id) => _songs.doc(id).delete();

  @override
  Stream<Set<String>> favorites(String uid) =>
      _db.collection('users').doc(uid).snapshots().map((d) =>
          ((d.data()?['favorites'] as List?) ?? const []).cast<String>().toSet());

  @override
  Future<void> setFavorite(String uid, String songId, bool favorite) =>
      _db.collection('users').doc(uid).set({
        'favorites': favorite
            ? FieldValue.arrayUnion([songId])
            : FieldValue.arrayRemove([songId]),
      }, SetOptions(merge: true));
}

// ---------------------------------------------------------------------------
// Modo demo (sin Firebase): todo se guarda en el teléfono
// ---------------------------------------------------------------------------

class LocalBackend implements Backend {
  static const _kSongs = 'demo_songs';
  static const _kUser = 'demo_user_admin';
  static const _kFavs = 'demo_favs_';

  late final SharedPreferences _prefs;
  List<Song> _songList = [];
  AppUser? _user;
  final Map<String, Set<String>> _favs = {};

  final _userCtrl = StreamController<AppUser?>.broadcast();
  final _songsCtrl = StreamController<List<Song>>.broadcast();
  final _favCtrl = StreamController<void>.broadcast();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_kSongs);
    if (raw == null) {
      _songList = seedSongs();
      await _persistSongs();
    } else {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _songList = map.entries
          .map((e) => Song.fromMap(e.key, e.value as Map<String, dynamic>))
          .toList();
    }
    _sortSongs();
    final admin = _prefs.getBool(_kUser);
    if (admin != null) _user = _demoUser(admin);
  }

  AppUser _demoUser(bool admin) => AppUser(
        uid: admin ? 'demo-admin' : 'demo-user',
        name: admin ? 'Administrador (demo)' : 'Usuario (demo)',
        email: admin ? 'admin@demo' : 'usuario@demo',
        isAdmin: admin,
      );

  void _sortSongs() =>
      _songList.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> _persistSongs() => _prefs.setString(
      _kSongs, jsonEncode({for (final s in _songList) s.id: s.toMap()}));

  @override
  bool get isDemo => true;

  @override
  Stream<AppUser?> authChanges() async* {
    yield _user;
    yield* _userCtrl.stream;
  }

  @override
  Future<void> signInWithGoogle() => throw StateError(
      'Firebase no está configurado. Sigue los pasos de FIREBASE_SETUP.md');

  @override
  Future<void> signInDemo({required bool admin}) async {
    _user = _demoUser(admin);
    await _prefs.setBool(_kUser, admin);
    _userCtrl.add(_user);
  }

  @override
  Future<void> signOut() async {
    _user = null;
    await _prefs.remove(_kUser);
    _userCtrl.add(null);
  }

  @override
  Stream<List<Song>> songs() async* {
    yield List.of(_songList);
    yield* _songsCtrl.stream;
  }

  @override
  Future<void> saveSong(Song song) async {
    if (song.id.isEmpty) {
      _songList.add(
          song.copyWith(id: DateTime.now().microsecondsSinceEpoch.toString()));
    } else {
      final i = _songList.indexWhere((s) => s.id == song.id);
      if (i >= 0) _songList[i] = song;
    }
    _sortSongs();
    await _persistSongs();
    _songsCtrl.add(List.of(_songList));
  }

  @override
  Future<void> deleteSong(String id) async {
    _songList.removeWhere((s) => s.id == id);
    await _persistSongs();
    _songsCtrl.add(List.of(_songList));
  }

  Set<String> _favsOf(String uid) => _favs.putIfAbsent(
      uid, () => (_prefs.getStringList('$_kFavs$uid') ?? const []).toSet());

  @override
  Stream<Set<String>> favorites(String uid) async* {
    yield Set.of(_favsOf(uid));
    await for (final _ in _favCtrl.stream) {
      yield Set.of(_favsOf(uid));
    }
  }

  @override
  Future<void> setFavorite(String uid, String songId, bool favorite) async {
    final set = _favsOf(uid);
    favorite ? set.add(songId) : set.remove(songId);
    await _prefs.setStringList('$_kFavs$uid', set.toList());
    _favCtrl.add(null);
  }
}
