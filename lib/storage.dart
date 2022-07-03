import 'package:path/path.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:collection/collection.dart';

final database = () async {
  return databaseFactoryFfi.openDatabase(
    join(await databaseFactoryFfi.getDatabasesPath(), 'nfm.db'),
    options: OpenDatabaseOptions(
      onCreate: (db, version) {
        return db.execute('''
CREATE TABLE "connections" (
	"id"	INTEGER,
	"order"	INTEGER DEFAULT 0,
	"title"	TEXT NOT NULL,
	"url"	TEXT NOT NULL,
	"username"	INTEGER,
	"password"	INTEGER,
	"autoconnect"	INTEGER DEFAULT 0,
	PRIMARY KEY("id" AUTOINCREMENT)
);

CREATE TABLE "bookmarks" (
	"connection_id"	INTEGER,
	"path"	TEXT,
	"order"	INTEGER DEFAULT 0,
	FOREIGN KEY("connection_id") REFERENCES "connections"("id"),
	PRIMARY KEY("connection_id","path")
);

CREATE TABLE "history" (
	"connection_id"	INTEGER,
	"path"	TEXT,
	FOREIGN KEY("connection_id") REFERENCES "connections"("id"),
	PRIMARY KEY("connection_id","path")
);

CREATE TABLE "entry_actions" (
	"id"	INTEGER,
	"order"	INTEGER DEFAULT 0,
	"title"	TEXT NOT NULL,
	"command"	TEXT NOT NULL,
	"add_to_history"	INTEGER DEFAULT 1,
	"toast_output"	INTEGER DEFAULT 0,
	"clipboard_output"	INTEGER DEFAULT 0,
	PRIMARY KEY("id" AUTOINCREMENT)
);
''');
      },
      version: 1,
    ),
  );
}();

class EntryCommandAction {
  int? id, order;
  String title = '', command = '';
  bool addToHistory = true, toastOutput = false, clipboardOutput = false;

  EntryCommandAction();

  EntryCommandAction.fromMap(Map<String, dynamic> map)
      : id = map['id'],
        order = map['order'],
        title = map['title'],
        command = map['command'],
        addToHistory = map['add_to_history'] == 1,
        toastOutput = map['toast_output'] == 1,
        clipboardOutput = map['clipboard_output'] == 1;

  Map<String, dynamic> toMap() => {
        'id': id,
        'order': order,
        'title': title,
        'command': command,
        'add_to_history': addToHistory ? 1 : 0,
        'toast_output': toastOutput ? 1 : 0,
        'clipboard_output': clipboardOutput ? 1 : 0,
      };

  Future<void> insertUpdate() async {
    id = await (await database).insert(
      'entry_actions',
      toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete() async {
    assert(id != null);
    await (await database).delete(
      'entry_actions',
      where: 'id = ?',
      whereArgs: [id],
    );
    id = null;
  }
}

class Connection {
  int? id, order;
  String title = '', url = '', username = '', password = '';
  bool autoConnect = false;

  Connection();

  Connection.fromMap(Map<String, dynamic> map)
      : id = map['id'],
        order = map['order'],
        title = map['title'],
        url = map['url'],
        username = map['username'],
        password = map['password'],
        autoConnect = map['autoconnect'] == 1;

  Map<String, dynamic> toMap() => {
        'id': id,
        'order': order,
        'title': title,
        'url': url,
        'username': username,
        'password': password,
        'autoconnect': autoConnect ? 1 : 0,
      };

  Future<void> insertUpdate() async {
    id = await (await database).insert(
      'connections',
      toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete() async {
    assert(id != null);
    await (await database).delete(
      'connections',
      where: 'id = ?',
      whereArgs: [id],
    );
    id = null;
  }

  Future<void> toggleAutoConnect() async {
    assert(id != null);
    autoConnect = !autoConnect;
    await (await database).update('connections', {'autoconnect': 0});
    await (await database).update(
      'connections',
      {'autoconnect': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Set<String>> historySet(List<String> paths) async {
    assert(id != null);
    return (await (await database).query(
      'history',
      columns: ['path'],
      where: 'connection_id = ? AND path IN (${List.filled(paths.length, '?').join(',')})',
      whereArgs: <Object?>[id] + paths,
    ))
        .map<String>((e) => e['path'] as String)
        .toSet();
  }

  Future<void> historyAdd(String path) async {
    assert(id != null);
    await (await database).insert(
      'history',
      {
        'connection_id': id,
        'path': path,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> historyRemove(String path) async {
    assert(id != null);
    await (await database).delete(
      'history',
      where: 'connection_id = ? AND path = ?',
      whereArgs: [id, path],
    );
  }

  Future<List<String>> getBookmarks() async {
    assert(id != null);
    return (await (await database).query(
      'bookmarks',
      columns: ['path'],
      where: 'connection_id = ?',
      whereArgs: [id],
      orderBy: '`order`',
    ))
        .map<String>((e) => e['path'] as String)
        .toList();
  }

  Future<void> bookmarksReorder(List<String> paths) async {
    assert(id != null);
    final batch = (await database).batch();
    paths.forEachIndexed((i, path) {
      batch.update(
        'bookmarks',
        {'order': i},
        where: 'connection_id = ? AND path = ?',
        whereArgs: [id, path],
      );
    });
    await batch.commit();
  }

  Future<void> bookmarkToggle(String path) async {
    assert(id != null);
    if (await isBookmarked(path)) {
      await (await database).delete(
        'bookmarks',
        where: 'connection_id = ? AND path = ?',
        whereArgs: [id, path],
      );
    } else {
      await (await database).insert(
        'bookmarks',
        {
          'connection_id': id,
          'path': path,
        },
      );
    }
  }

  Future<bool> isBookmarked(String path) async {
    assert(id != null);
    return (await (await database).query(
      'bookmarks',
      columns: ['path'],
      where: 'connection_id = ? AND path = ?',
      whereArgs: [id, path],
      limit: 1,
    ))
        .isNotEmpty;
  }
}

Future<List<Connection>> getConnections() async {
  return (await (await database).query('connections'))
      .map<Connection>((e) => Connection.fromMap(e))
      .toList();
}

Future<void> reorderConnections(List<Connection> connections) async {
  final batch = (await database).batch();
  connections.forEachIndexed((i, c) {
    assert(c.id != null);
    batch.update(
      'connections',
      {'order': i},
      where: 'id = ?',
      whereArgs: [c.id],
    );
  });
  await batch.commit();
}

Future<List<EntryCommandAction>> getActions() async {
  return (await (await database).query('entry_actions', orderBy: '`order`'))
      .map<EntryCommandAction>((e) => EntryCommandAction.fromMap(e))
      .toList();
}

Future<void> reorderActions(List<Connection> actions) async {
  final batch = (await database).batch();
  actions.forEachIndexed((i, a) {
    assert(a.id != null);
    batch.update(
      'entry_actions',
      {'order': i},
      where: 'id = ?',
      whereArgs: [a.id],
    );
  });
  await batch.commit();
}
