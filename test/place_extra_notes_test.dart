// Model JSON round-trip and PlaceStore CRUD for Place.extraNotes — the
// "My review" section's dated note log (see place_detail_extra_notes_test.dart
// for the widget-level test). Kept in its own file rather than appended to
// place_json_test.dart/place_store_test.dart to avoid colliding with other
// in-flight edits to those files.
import 'dart:convert';

import 'package:cheaptripchip/data/local_repositories.dart';
import 'package:cheaptripchip/data/mock_data.dart';
import 'package:cheaptripchip/data/place_store.dart';
import 'package:cheaptripchip/models/place.dart';
import 'package:cheaptripchip/models/place_note.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const _base = Place(
  id: 'p',
  name: 'n',
  areaLabel: '',
  region: '',
  category: PlaceCategory.cafe,
  location: LatLng(1, 1),
  descriptionEn: '',
  originalCaption: '',
  address: '',
  hours: '',
  sourceHandle: '',
  sourcePlatform: SourcePlatform.instagram,
);

void main() {
  group('PlaceNote / Place.extraNotes JSON round-trip', () {
    test('round-trips through JSON (including via a real encoder)', () {
      final createdAt = DateTime.utc(2026, 9, 27, 10, 30);
      final withNotes = _base.copyWith(
        extraNotes: [
          PlaceNote(
            id: 'n1',
            text: '1st visit: great ramen',
            createdAt: createdAt,
          ),
          PlaceNote(
            id: 'n2',
            text: '2nd visit: still good',
            createdAt: createdAt,
          ),
        ],
      );

      final reencoded =
          jsonDecode(jsonEncode(withNotes.toJson())) as Map<String, dynamic>;
      final decoded = Place.fromJson(reencoded);

      expect(decoded.extraNotes, hasLength(2));
      expect(decoded.extraNotes[0].id, 'n1');
      expect(decoded.extraNotes[0].text, '1st visit: great ramen');
      expect(decoded.extraNotes[0].createdAt, createdAt);
      expect(decoded.extraNotes[1].id, 'n2');
    });

    test('missing extraNotes defaults to an empty list', () {
      expect(Place.fromJson(_base.toJson()).extraNotes, isEmpty);
      expect(Place.fromJson(const {}).extraNotes, isEmpty);
    });

    test('skips malformed entries instead of throwing', () {
      final json = {
        ..._base.toJson(),
        'extraNotes': [
          {'id': 'ok', 'text': 'fine', 'createdAt': '2026-09-27T00:00:00Z'},
          {'id': 'no-text'},
          {'text': 'no id', 'createdAt': '2026-09-27T00:00:00Z'},
          {'id': 'bad-date', 'text': 'x', 'createdAt': 'not a date'},
          'not even a map',
          null,
        ],
      };

      final decoded = Place.fromJson(json);
      expect(decoded.extraNotes, hasLength(1));
      expect(decoded.extraNotes.single.id, 'ok');
    });

    test('copyWith replaces extraNotes wholesale (like photoUrls)', () {
      final withOne = _base.copyWith(
        extraNotes: [
          PlaceNote(id: 'n1', text: 'a', createdAt: DateTime.utc(2026)),
        ],
      );
      expect(withOne.copyWith(myNotes: 'x').extraNotes, withOne.extraNotes);
      expect(withOne.copyWith(extraNotes: const []).extraNotes, isEmpty);
    });
  });

  group('PlaceStore note methods', () {
    setUp(() async {
      PlaceStore.instance.bindRepository(LocalPlaceRepository());
      await Future<void>.delayed(Duration.zero);
    });

    test('addNote appends a note with the given text', () async {
      final store = PlaceStore.instance;
      final target = MockData.places.first;

      await store.addNote(target.id, '  1st visit: loved it  ');
      await Future<void>.delayed(Duration.zero);

      final notes = store.byId(target.id).extraNotes;
      expect(notes, hasLength(1));
      expect(notes.single.text, '1st visit: loved it');
    });

    test('addNote is a no-op for blank text or an unknown id', () async {
      final store = PlaceStore.instance;
      final target = MockData.places.first;

      await store.addNote(target.id, '   ');
      await Future<void>.delayed(Duration.zero);
      expect(store.byId(target.id).extraNotes, isEmpty);

      await store.addNote('does-not-exist', 'x');
      await Future<void>.delayed(Duration.zero);
      expect(store.byIdOrNull('does-not-exist'), isNull);
    });

    test(
      'editNote replaces the text of the given note, keeps createdAt',
      () async {
        final store = PlaceStore.instance;
        final target = MockData.places.first;

        await store.addNote(target.id, 'first draft');
        await Future<void>.delayed(Duration.zero);
        final noteId = store.byId(target.id).extraNotes.single.id;
        final createdAt = store.byId(target.id).extraNotes.single.createdAt;

        await store.editNote(target.id, noteId, ' edited text ');
        await Future<void>.delayed(Duration.zero);

        final note = store.byId(target.id).extraNotes.single;
        expect(note.text, 'edited text');
        expect(note.id, noteId);
        expect(note.createdAt, createdAt);
      },
    );

    test('editNote no-ops for an unknown note id or blank text', () async {
      final store = PlaceStore.instance;
      final target = MockData.places.first;
      await store.addNote(target.id, 'keep me');
      await Future<void>.delayed(Duration.zero);

      await store.editNote(target.id, 'does-not-exist', 'x');
      await Future<void>.delayed(Duration.zero);
      expect(store.byId(target.id).extraNotes.single.text, 'keep me');

      final noteId = store.byId(target.id).extraNotes.single.id;
      await store.editNote(target.id, noteId, '   ');
      await Future<void>.delayed(Duration.zero);
      expect(store.byId(target.id).extraNotes.single.text, 'keep me');
    });

    test('deleteNote removes the note and returns it', () async {
      final store = PlaceStore.instance;
      final target = MockData.places.first;
      await store.addNote(target.id, 'note A');
      await store.addNote(target.id, 'note B');
      await Future<void>.delayed(Duration.zero);
      final noteA = store.byId(target.id).extraNotes.first;

      final removed = await store.deleteNote(target.id, noteA.id);
      await Future<void>.delayed(Duration.zero);

      expect(removed?.id, noteA.id);
      expect(store.byId(target.id).extraNotes, hasLength(1));
      expect(
        store.byId(target.id).extraNotes.any((n) => n.id == noteA.id),
        isFalse,
      );
    });

    test('deleteNote returns null for an unknown note/place id', () async {
      final store = PlaceStore.instance;
      final target = MockData.places.first;

      expect(await store.deleteNote(target.id, 'nope'), isNull);
      expect(await store.deleteNote('does-not-exist', 'nope'), isNull);
    });

    test('restoreNote (Undo) re-inserts the exact note', () async {
      final store = PlaceStore.instance;
      final target = MockData.places.first;
      await store.addNote(target.id, 'about to delete');
      await Future<void>.delayed(Duration.zero);
      final note = store.byId(target.id).extraNotes.single;

      final removed = await store.deleteNote(target.id, note.id);
      await Future<void>.delayed(Duration.zero);
      expect(store.byId(target.id).extraNotes, isEmpty);

      await store.restoreNote(target.id, removed!);
      await Future<void>.delayed(Duration.zero);
      final restored = store.byId(target.id).extraNotes.single;
      expect(restored.id, note.id);
      expect(restored.text, note.text);
      expect(restored.createdAt, note.createdAt);
    });

    test(
      'restoreNote is a no-op if a note with that id already exists',
      () async {
        final store = PlaceStore.instance;
        final target = MockData.places.first;
        await store.addNote(target.id, 'only one');
        await Future<void>.delayed(Duration.zero);
        final note = store.byId(target.id).extraNotes.single;

        await store.restoreNote(target.id, note);
        await Future<void>.delayed(Duration.zero);
        expect(store.byId(target.id).extraNotes, hasLength(1));
      },
    );
  });
}
