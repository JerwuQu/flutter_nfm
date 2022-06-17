import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwq_utils/jwq_utils.dart';
import 'package:shlex/shlex.dart' as shlex;

import 'nfm.dart';

var settings = SettingManager();
final GlobalKey<ScaffoldMessengerState> scaffoldKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  await settings.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'nfm',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      scaffoldMessengerKey: scaffoldKey,
      home: const ConnectionListPage(),
    );
  }
}

class ConnectionInfo {
  String url, username, password;
  List<NfmEntry> bookmarks;
  late Set<String> _bookmarkUris;
  Set<String> history;

  ConnectionInfo.empty()
      : url = '',
        username = '',
        password = '',
        bookmarks = [],
        _bookmarkUris = {},
        history = {};
  ConnectionInfo.fromJson(Map<String, dynamic> json)
      : url = json['url'],
        username = json['username'],
        password = json['password'],
        bookmarks = ((json['bookmarks'] ?? []) as List<dynamic>)
            .map((e) => NfmEntry.fromBookmarkJson(e))
            .toList(),
        history =
            ((json['history'] ?? []) as List<dynamic>).map<String>((e) => e as String).toSet() {
    _bookmarkUris = bookmarks.map<String>((b) => b.uriPath).toSet();
  }
  toJson() => {
        'url': url,
        'username': username,
        'password': password,
        'bookmarks': bookmarks.map((e) => e.toBookmarkJson()).toList(),
        'history': history.toList(),
      };

  bool isBookmarked(NfmEntry entry) => _bookmarkUris.contains(entry.uriPath);
  void toggleBookmark(NfmEntry entry) {
    if (isBookmarked(entry)) {
      bookmarks.removeWhere((e) => e.uriPath == entry.uriPath);
      _bookmarkUris.remove(entry.uriPath);
    } else {
      bookmarks.add(entry.toBookmark());
      _bookmarkUris.add(entry.uriPath);
    }
    settings.save();
  }

  bool isInHistory(NfmEntry entry) => history.contains(entry.uriPath);
  void addToHistory(NfmEntry entry) {
    history.add(entry.uriPath);
    settings.save();
  }

  void removeFromHistory(NfmEntry entry) {
    history.remove(entry.uriPath);
    settings.save();
  }
}

class EntryCommandAction {
  String title, command;
  bool addToHistory, toastOutput, copyOutputToClipboard;

  EntryCommandAction()
      : title = '',
        command = '',
        addToHistory = true,
        toastOutput = false,
        copyOutputToClipboard = false;

  EntryCommandAction.fromJson(Map<String, dynamic> json)
      : title = json['title'],
        command = json['command'],
        addToHistory = json['addToHistory'],
        toastOutput = json['toastOutput'],
        copyOutputToClipboard = json['clipboardOutput'];
  toJson() => {
        'title': title,
        'command': command,
        'addToHistory': addToHistory,
        'toastOutput': toastOutput,
        'clipboardOutput': copyOutputToClipboard,
      };
}

class SettingManager {
  // TODO: support storing connections encrypted

  late List<ConnectionInfo> connections;
  late List<EntryCommandAction> actions;

  Future load() async {
    final prefs = await SharedPreferences.getInstance();

    final connectionsJson = jsonDecode(prefs.getString('connections') ?? '[]');
    connections =
        connectionsJson.map<ConnectionInfo>((json) => ConnectionInfo.fromJson(json)).toList();

    final actionsJson = jsonDecode(prefs.getString('actions') ?? '[]');
    actions =
        actionsJson.map<EntryCommandAction>((json) => EntryCommandAction.fromJson(json)).toList();
  }

  Future save() async {
    final prefs = await SharedPreferences.getInstance();

    final connectionsJson = jsonEncode(connections.map((c) => c.toJson()).toList());
    await prefs.setString('connections', connectionsJson);

    final actionsJson = jsonEncode(actions.map((a) => a.toJson()).toList());
    await prefs.setString('actions', actionsJson);
  }
}

class ConnectionListPage extends StatefulWidget {
  const ConnectionListPage({Key? key}) : super(key: key);

  @override
  State<ConnectionListPage> createState() => ConnectionListPageState();
}

class ConnectionListPageState extends State<ConnectionListPage> {
  Future editConnection([int? index]) async {
    ConnectionInfo conn = index == null
        ? ConnectionInfo.empty()
        : ConnectionInfo.fromJson(settings.connections[index].toJson());
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    decoration: const InputDecoration(
                      hintText: 'https://example.com/dir.json/',
                      labelText: 'URL',
                    ),
                    initialValue: conn.url,
                    onChanged: (str) => conn.url = str,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Username'),
                    initialValue: conn.username,
                    onChanged: (str) => conn.username = str,
                  ),
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Password'),
                    initialValue: conn.password,
                    onChanged: (str) => conn.password = str,
                    obscureText: true,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                          TextButton(
                            style: elevatedButtonStyle(context),
                            onPressed: () {
                              setState(() {
                                if (index == null) {
                                  settings.connections.add(conn);
                                } else {
                                  settings.connections[index] = conn;
                                }
                                settings.save();
                              });
                              return Navigator.of(context).pop();
                            },
                            child: const Text('Save'),
                          ),
                        ] +
                        (index == null
                            ? []
                            : [
                                const SizedBox(width: 40),
                                TextButton(
                                  style: elevatedButtonStyle(context, color: Colors.red),
                                  onPressed: () async {
                                    if (await confirm(context)) {
                                      setState(() {
                                        settings.connections.removeAt(index);
                                        settings.save();
                                      });
                                      Navigator.of(context).pop();
                                    }
                                  },
                                  child: const Text('Delete'),
                                ),
                              ]),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
      ),
      body: ReorderableListView(
        scrollController: AdjustableScrollController(100),
        onReorder: (oldIndex, newIndex) {
          if (oldIndex < newIndex) {
            newIndex--;
          }
          setState(() {
            final item = settings.connections.removeAt(oldIndex);
            settings.connections.insert(newIndex, item);
          });
        },
        children: settings.connections
            .mapIndexed<Widget>(
              (index, conn) => ListTile(
                title: Text(conn.username == '' ? conn.url : '${conn.username}@${conn.url}'),
                key: Key(conn.hashCode.toString()),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (ctx) => ConnectionPage(conn)),
                  );
                },
                onLongPress: () => editConnection(index),
              ),
            )
            .toList(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => editConnection(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ConnectionPage extends StatefulWidget {
  final ConnectionInfo conn;

  const ConnectionPage(this.conn, {Key? key}) : super(key: key);

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  late Nfm nfm;
  String entryUri = '/'; // TODO: make this into breadcrumbs instead
  late Future<List<NfmEntry>> entries;

  @override
  void initState() {
    super.initState();
    nfm = Nfm(widget.conn.url, widget.conn.username, widget.conn.password);
    entries = nfm.fetch();
  }

  Widget entryRow(NfmEntry entry) {
    return Row(
      children: (widget.conn.isBookmarked(entry)
              ? <Widget>[
                  const Icon(Icons.star, color: Colors.orange),
                  const SizedBox(width: 6),
                ]
              : <Widget>[]) +
          [
            Icon(entry.type == NfmEntryType.file ? Icons.file_copy : Icons.folder),
            const SizedBox(width: 6),
            Expanded(child: Text(entry.title)),
          ],
    );
  }

  Future editActionDialog([int? index]) async {
    EntryCommandAction? action = index == null
        ? EntryCommandAction()
        : EntryCommandAction.fromJson(settings.actions[index].toJson());
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return Dialog(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: action.title,
                      onChanged: (val) => setState(() => action.title = val),
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    TextFormField(
                      initialValue: action.command,
                      onChanged: (val) => setState(() => action.command = val),
                      decoration: const InputDecoration(
                        labelText: 'Command',
                        hintText: 'mpv --fs \$URL',
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: const Text('Add to history'),
                      value: action.addToHistory,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (val) => setState(() => action.addToHistory = val ?? false),
                    ),
                    CheckboxListTile(
                      title: const Text('Toast output'),
                      value: action.toastOutput,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (val) => setState(() => action.toastOutput = val ?? false),
                    ),
                    CheckboxListTile(
                      title: const Text('Copy output to clipboard'),
                      value: action.copyOutputToClipboard,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (val) =>
                          setState(() => action.copyOutputToClipboard = val ?? false),
                    ),
                    const SizedBox(height: 8),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                              TextButton(
                                style: elevatedButtonStyle(context),
                                onPressed: () {
                                  if (action.title.isEmpty || action.command.isEmpty) {
                                    showError(context, 'Invalid action',
                                        'Title and Command are required');
                                    return;
                                  }
                                  setState(() {
                                    if (index == null) {
                                      settings.actions.add(action);
                                    } else {
                                      settings.actions[index] = action;
                                    }
                                    settings.save();
                                    Navigator.of(context).pop();
                                  });
                                },
                                child: const Text('Save'),
                              ),
                            ] +
                            (index == null
                                ? []
                                : [
                                    const SizedBox(width: 8),
                                    TextButton(
                                      style: elevatedButtonStyle(context, color: Colors.red),
                                      onPressed: () async {
                                        if (await confirm(context)) {
                                          setState(() {
                                            settings.actions.removeAt(index);
                                            settings.save();
                                            Navigator.of(context).pop();
                                          });
                                        }
                                      },
                                      child: const Text('Delete'),
                                    ),
                                  ])),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  Future actionDialog(NfmEntry entry) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setState) {
          return Dialog(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListView(
                      shrinkWrap: true,
                      children: settings.actions
                              .mapIndexed<Widget>(
                                (index, action) => ListTile(
                                  title: Row(children: [
                                    Expanded(
                                        child: Text(action.title,
                                            style: const TextStyle(color: Colors.blue))),
                                    IconButton(
                                      onPressed: () {
                                        editActionDialog(index).then((_) => setState(() {}));
                                      },
                                      icon: const Icon(Icons.edit),
                                    ),
                                  ]),
                                  onTap: () {
                                    final url = nfm.authedEntryUrl(entry).toString();
                                    final args = shlex.split(action.command);
                                    args.forEachIndexed((i, str) {
                                      if (str == '\$URL') {
                                        args[i] = url;
                                      }
                                    });
                                    Process.run(args[0], args.slice(1), runInShell: true).then((r) {
                                      if (r.exitCode != 0) {
                                        showError(context, "Process returned non-zero", r.stdout);
                                        return;
                                      }
                                      if (action.toastOutput) {
                                        scaffoldKey.currentState
                                            ?.showSnackBar(SnackBar(content: Text(r.stdout)));
                                      }
                                      if (action.copyOutputToClipboard) {
                                        Clipboard.setData(ClipboardData(text: r.stdout));
                                        if (!action.toastOutput) {
                                          scaffoldKey.currentState?.showSnackBar(const SnackBar(
                                              content: Text('Result copied to clipboard')));
                                        }
                                      }
                                      if (!action.toastOutput && !action.copyOutputToClipboard) {
                                        scaffoldKey.currentState?.showSnackBar(const SnackBar(
                                            content: Text('Process exited successfully')));
                                      }
                                    });
                                    if (action.addToHistory) {
                                      setState(() => widget.conn.addToHistory(entry));
                                    }
                                    Navigator.of(context).pop();
                                  },
                                  onLongPress: () {
                                    editActionDialog(index).then((_) => setState(() {}));
                                  },
                                ),
                              )
                              .toList() +
                          [
                            ListTile(
                              title: const Text('Copy URL to clipboard'),
                              onTap: () {
                                Clipboard.setData(
                                    ClipboardData(text: nfm.authedEntryUrl(entry).toString()));
                                scaffoldKey.currentState?.showSnackBar(
                                    const SnackBar(content: Text('URL copied to clipboard')));
                                Navigator.of(context).pop();
                              },
                            ),
                            ListTile(
                              title: const Text('Add action'),
                              onTap: () {
                                editActionDialog(null).then((_) => setState(() {}));
                              },
                            ),
                          ] +
                          (widget.conn.isInHistory(entry)
                              ? [
                                  ListTile(
                                    title: const Text('Remove from history'),
                                    onTap: () {
                                      setState(() {
                                        widget.conn.removeFromHistory(entry);
                                        Navigator.of(context).pop();
                                      });
                                    },
                                  )
                                ]
                              : [
                                  ListTile(
                                    title: const Text('Add to history'),
                                    onTap: () {
                                      setState(() {
                                        widget.conn.addToHistory(entry);
                                        Navigator.of(context).pop();
                                      });
                                    },
                                  )
                                ])),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<NfmEntry>>(
      future: entries,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loading...')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return SplitView(
          title: Text(entryUri),
          drawer: ReorderableListView(
            onReorder: (oldIndex, newIndex) {
              if (oldIndex < newIndex) {
                newIndex--;
              }
              setState(() {
                final item = widget.conn.bookmarks.removeAt(oldIndex);
                widget.conn.bookmarks.insert(newIndex, item);
                settings.save();
              });
            },
            scrollController: AdjustableScrollController(100),
            children: [
              for (final bookmark in widget.conn.bookmarks)
                ListTile(
                  key: Key(bookmark.uriPath),
                  title: entryRow(bookmark),
                  onTap: () {
                    setState(() {
                      entryUri = bookmark.uriPath;
                      entries = nfm.fetch(bookmark);
                    });
                  },
                  onLongPress: () {
                    setState(() => widget.conn.toggleBookmark(bookmark));
                  },
                ),
            ],
          ),
          body: ListView(
            controller: AdjustableScrollController(100),
            children: [
              for (final entry in snapshot.data!)
                ListTile(
                  title: entryRow(entry),
                  tileColor: widget.conn.isInHistory(entry) ? Colors.green : null,
                  onTap: () {
                    if (entry.type == NfmEntryType.dir) {
                      setState(() {
                        entryUri = entry.uriPath;
                        entries = nfm.fetch(entry);
                      });
                    } else {
                      actionDialog(entry).then((_) => setState(() {}));
                    }
                  },
                  onLongPress: (entry.type == NfmEntryType.dir)
                      ? () {
                          setState(() => widget.conn.toggleBookmark(entry));
                        }
                      : null,
                )
            ],
          ),
        );
      },
    );
  }
}
