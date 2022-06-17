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
      home: const ConnectionListPage(),
    );
  }
}

class EntryCommandAction {
  String title, command;
  bool addToHistory, toastResult, copyResultToClipboard;

  EntryCommandAction()
      : title = '',
        command = '',
        addToHistory = true, // TODO: use
        toastResult = false,
        copyResultToClipboard = false;

  EntryCommandAction.fromJson(Map<String, dynamic> json)
      : title = json['title'],
        command = json['command'],
        addToHistory = json['addToHistory'],
        toastResult = json['toastResult'],
        copyResultToClipboard = json['clipboardResult'];
  toJson() => {
        'title': title,
        'command': command,
        'addToHistory': addToHistory,
        'toastResult': toastResult,
        'clipboardResult': copyResultToClipboard,
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

    // TODO: List<String> history? (loaded as Set)
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
    ConnectionInfo conn =
        index == null ? ConnectionInfo.empty() : ConnectionInfo.copy(settings.connections[index]);
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
  late Future<List<NfmEntry>> entries;

  @override
  void initState() {
    super.initState();
    nfm = Nfm(widget.conn);
    entries = nfm.fetch();
  }

  Widget entryRow(NfmEntry entry, [bool bookmarked = false]) {
    return Row(
      children: (bookmarked
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

  Future actionDialog(NfmEntry entry) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListView(
                    shrinkWrap: true,
                    children: [
                          for (final action in settings.actions)
                            ListTile(
                              title: Text(action.title),
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
                                  if (action.toastResult) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(content: Text(r.stdout)));
                                  }
                                  if (action.copyResultToClipboard) {
                                    Clipboard.setData(ClipboardData(text: r.stdout));
                                    if (!action.toastResult) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                          content: Text('Result copied to clipboard')));
                                    }
                                  }
                                });
                                Navigator.of(context).pop();
                              },
                              onLongPress: () {
                                // TODO: edit/delete
                              },
                            )
                        ] +
                        // TODO: separate user-made from built-in
                        [
                          ListTile(
                            title: const Text('Copy URL to clipboard'),
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: nfm.authedEntryUrl(entry).toString()));
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('URL copied to clipboard')));
                              Navigator.of(context).pop();
                            },
                          ),
                          ListTile(
                            title: const Text('Add action'),
                            onTap: () {
                              // TODO
                            },
                          ),
                          // TODO: add to history & remove from history
                        ]),
              ],
            ),
          ),
        );
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
          title: Text('Current dir'), // TODO
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
                  title: entryRow(bookmark, true),
                  onTap: () {
                    setState(() {
                      entries = nfm.fetch(bookmark);
                    });
                  },
                  onLongPress: () {
                    setState(() {
                      widget.conn.bookmarks.remove(bookmark);
                      settings.save();
                    });
                  },
                ),
            ],
          ),
          body: ListView(
            controller: AdjustableScrollController(100),
            children: [
              for (final entry in snapshot.data!)
                ListTile(
                  title: entryRow(entry), // TODO: show if bookmarked (URI set?)
                  onTap: () {
                    if (entry.type == NfmEntryType.dir) {
                      setState(() {
                        entries = nfm.fetch(entry);
                      });
                    } else {
                      actionDialog(entry);
                    }
                  },
                  onLongPress: (entry.type == NfmEntryType.dir)
                      ? () {
                          setState(() {
                            widget.conn.bookmarks.add(entry.toBookmark());
                            settings.save();
                          });
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
