import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwq_utils/jwq_utils.dart';

import 'nfm.dart';

void main() {
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

class ConnectionListPage extends StatefulWidget {
  const ConnectionListPage({Key? key}) : super(key: key);

  @override
  State<ConnectionListPage> createState() => ConnectionListPageState();
}

class ConnectionListPageState extends State<ConnectionListPage> {
  late List<ConnectionInfo> connections;
  late Future _loadPrefs;

  ConnectionListPageState() : super() {
    _loadPrefs = loadPrefs();
  }

  Future loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final connectionsJson = jsonDecode(prefs.getString('connections') ?? '[]');
    // TODO: List<String> history? (loaded as Set)
    connections =
        connectionsJson.map<ConnectionInfo>((json) => ConnectionInfo.fromJson(json)).toList();
  }

  Future savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final connectionsJson = jsonEncode(connections.map((c) => c.toJson()).toList());
    await prefs.setString('connections', connectionsJson);
    // TODO: support storing connections encrypted
  }

  Future editConnection([int? index]) async {
    ConnectionInfo conn =
        index == null ? ConnectionInfo.empty() : ConnectionInfo.copy(connections[index]);
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
                                  connections.add(conn);
                                } else {
                                  connections[index] = conn;
                                }
                                savePrefs();
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
                                        connections.removeAt(index);
                                        savePrefs();
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
    return FutureBuilder(
      future: _loadPrefs,
      builder: ((context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loading...')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
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
                final item = connections.removeAt(oldIndex);
                connections.insert(newIndex, item);
              });
            },
            children: connections
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
      }),
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
          drawer: Drawer(
            child: ReorderableListView(
              onReorder: (oldIndex, newIndex) {
                if (oldIndex < newIndex) {
                  newIndex--;
                }
                setState(() {
                  final item = widget.conn.bookmarks.removeAt(oldIndex);
                  widget.conn.bookmarks.insert(newIndex, item);
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
                      });
                    },
                  ),
              ],
            ),
          ),
          body: ListView(
            controller: AdjustableScrollController(100),
            children: [
              for (final entry in snapshot.data!)
                ListTile(
                  title: entryRow(entry), // TODO: show bookmarked
                  onTap: () {
                    if (entry.type == NfmEntryType.dir) {
                      setState(() {
                        entries = nfm.fetch(entry);
                      });
                    } else {
                      // TODO: actions
                    }
                  },
                  onLongPress: (entry.type == NfmEntryType.dir)
                      ? () {
                          setState(() {
                            widget.conn.bookmarks.add(entry.toBookmark());
                            // TODO: savePrefs()
                          });
                        }
                      : null,
                )
            ],
          ), // TODO
        );
      },
    );
  }
}
