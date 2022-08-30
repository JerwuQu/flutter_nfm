import 'dart:io';

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfm/storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:jwq_utils/jwq_utils.dart';
import 'package:shlex/shlex.dart' as shlex;
import 'package:url_launcher/url_launcher.dart';

import 'nfm.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  sqfliteFfiInit();
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

class ConnectionListPage extends StatefulWidget {
  const ConnectionListPage({Key? key}) : super(key: key);

  @override
  State<ConnectionListPage> createState() => ConnectionListPageState();
}

class ConnectionListPageState extends State<ConnectionListPage> {
  List<Connection> connections = [];

  @override
  void initState() {
    super.initState();
    getConnections().then((cons) {
      setState(() {
        connections = cons;
      });
      final autoConn = cons.firstWhereOrNull((c) => c.autoConnect);
      if (autoConn != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (ctx) => ConnectionPage(autoConn)),
          );
        });
      }
    });
  }

  Future editConnection([Connection? sourceConn]) async {
    Connection conn = sourceConn == null ? Connection() : Connection.fromMap(sourceConn.toMap());
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
                            onPressed: () async {
                              await conn.insertUpdate();
                              if (!mounted) return;
                              Navigator.of(context).pop();
                            },
                            child: const Text('Save'),
                          ),
                        ] +
                        (conn.id == null
                            ? []
                            : [
                                const SizedBox(width: 40),
                                TextButton(
                                  style: elevatedButtonStyle(context, color: Colors.red),
                                  onPressed: () async {
                                    if (await confirm(context)) {
                                      await conn.delete();
                                      if (!mounted) return;
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
            final item = connections.removeAt(oldIndex);
            connections.insert(newIndex, item);
          });
          reorderConnections(connections);
        },
        children: connections
            .mapIndexed<Widget>(
              (index, conn) => ListTile(
                title: Row(children: [
                  IconButton(
                    icon: conn.autoConnect
                        ? const Icon(Icons.auto_awesome)
                        : const Icon(Icons.auto_awesome_outlined),
                    color: conn.autoConnect ? Colors.orange : Colors.grey,
                    onPressed: () async {
                      await conn.toggleAutoConnect();
                      setState(() {});
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(conn.username == '' ? conn.url : '${conn.username}@${conn.url}')),
                ]),
                key: Key(conn.hashCode.toString()),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (ctx) => ConnectionPage(conn)),
                  );
                },
                onLongPress: () async {
                  await editConnection(conn);
                  final newConnections = await getConnections();
                  setState(() {
                    connections = newConnections;
                  });
                },
              ),
            )
            .toList(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await editConnection();
          final newConnections = await getConnections();
          setState(() {
            connections = newConnections;
          });
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ConnectionPage extends StatefulWidget {
  final Connection conn;

  const ConnectionPage(this.conn, {Key? key}) : super(key: key);

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  late Nfm nfm;
  String entryPath = '/'; // TODO: make this into breadcrumbs instead
  Future<void> loadingFuture = Future.value();
  List<NfmEntry> entries = [];
  Set<String> pathHistorySet = {};
  List<String> bookmarks = [];
  Set<String> bookmarkSet = {};
  List<EntryCommandAction> actions = [];

  @override
  void initState() {
    super.initState();
    nfm = Nfm(widget.conn.url, widget.conn.username, widget.conn.password);
    fetchEntries();
    refreshActions(setState);
    refreshBookmarks();
  }

  Future refreshBookmarks() async {
    final newBookmarks = await widget.conn.getBookmarks();
    setState(() {
      bookmarks = newBookmarks;
      bookmarkSet = newBookmarks.toSet();
    });
  }

  Future refreshHistory() async {
    final newHistorySet = await widget.conn.historySet(entries.map<String>((e) => e.path).toList());
    setState(() {
      pathHistorySet = newHistorySet;
    });
  }

  Future refreshActions(void Function(void Function()) setState) async {
    final newActions = await getActions();
    setState(() {
      actions = newActions;
    });
  }

  void fetchEntries([NfmEntry? entry]) {
    setState(() {
      loadingFuture = () async {
        final lEntries = await nfm.fetch(entry);
        setState(() {
          entries = lEntries;
        });
        await refreshHistory();
      }();
    });
  }

  Widget entryRow(NfmEntry entry) {
    List<Widget> bookmarkBtn = (entry.type == NfmEntryType.dir)
        ? [
            IconButton(
              icon: bookmarkSet.contains(entry.path)
                  ? const Icon(Icons.star)
                  : const Icon(Icons.star_outline),
              color: bookmarkSet.contains(entry.path) ? Colors.orange : Colors.grey,
              onPressed: () {
                widget.conn.bookmarkToggle(entry.path).then((_) => refreshBookmarks());
              },
            ),
            const SizedBox(width: 6),
          ]
        : [];
    return Row(
      children: (bookmarkBtn +
          [
            Icon(entry.type == NfmEntryType.file ? Icons.file_copy : Icons.folder),
            const SizedBox(width: 6),
            Expanded(child: Text(entry.title)),
            const SizedBox(width: 16),
          ]),
    );
  }

  Future editActionDialog([EntryCommandAction? sourceAction]) async {
    EntryCommandAction action = sourceAction == null
        ? EntryCommandAction()
        : EntryCommandAction.fromMap(sourceAction.toMap());
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
                      value: action.clipboardOutput,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (val) => setState(() => action.clipboardOutput = val ?? false),
                    ),
                    const SizedBox(height: 8),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                              TextButton(
                                style: elevatedButtonStyle(context),
                                onPressed: () async {
                                  if (action.title.isEmpty || action.command.isEmpty) {
                                    showError(context, 'Invalid action',
                                        'Title and Command are required');
                                    return;
                                  }
                                  await action.insertUpdate();
                                  if (!mounted) return;
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Save'),
                              ),
                            ] +
                            (sourceAction == null
                                ? []
                                : [
                                    const SizedBox(width: 8),
                                    TextButton(
                                      style: elevatedButtonStyle(context, color: Colors.red),
                                      onPressed: () async {
                                        if (await confirm(context)) {
                                          await action.delete();
                                          if (!mounted) return;
                                          Navigator.of(context).pop();
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

  // TODO: move `actionDialog` to a separate widget (along with `editActionDialog` and `refreshActions`)
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
                  ReorderableListView(
                    shrinkWrap: true,
                    onReorder: (oldIndex, newIndex) {
                      if (oldIndex < newIndex) {
                        newIndex--;
                      }
                      setState(() {
                        final item = actions.removeAt(oldIndex);
                        actions.insert(newIndex, item);
                      });
                      reorderActions(actions);
                    },
                    children: actions
                        .mapIndexed<Widget>(
                          (index, action) => ListTile(
                            key: Key(action.id?.toString() ?? action.title),
                            title: Row(children: [
                              Expanded(
                                  child: Text(action.title,
                                      style: const TextStyle(color: Colors.blue))),
                              IconButton(
                                onPressed: () {
                                  editActionDialog(action).then((_) => refreshActions(setState));
                                },
                                icon: const Icon(Icons.edit),
                              ),
                              const SizedBox(width: 16),
                            ]),
                            onTap: () {
                              final url = nfm.authedEntryUrl(entry).toString();
                              final args = shlex.split(action.command);
                              args.forEachIndexed((i, str) {
                                if (str == '\$URL') {
                                  args[i] = url;
                                } else if (str == '\$PATH') {
                                  args[i] = entry.path;
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
                                if (action.clipboardOutput) {
                                  Clipboard.setData(ClipboardData(text: r.stdout));
                                  if (!action.toastOutput) {
                                    scaffoldKey.currentState?.showSnackBar(const SnackBar(
                                        content: Text('Result copied to clipboard')));
                                  }
                                }
                                if (!action.toastOutput && !action.clipboardOutput) {
                                  scaffoldKey.currentState?.showSnackBar(
                                      const SnackBar(content: Text('Process exited successfully')));
                                }
                              });
                              if (action.addToHistory) {
                                widget.conn.historyAdd(entry.path).then((_) => refreshHistory());
                              }
                              Navigator.of(context).pop();
                            },
                            onLongPress: () {
                              editActionDialog(action).then((_) => refreshActions(setState));
                            },
                          ),
                        )
                        .toList(),
                  ),
                  ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        title: const Text('Open URL'),
                        onTap: () async {
                          await launchUrl(nfm.authedEntryUrl(entry),
                              mode: LaunchMode.externalNonBrowserApplication);
                          if (!mounted) return;
                          Navigator.of(context).pop();
                        },
                      ),
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
                          editActionDialog().then((_) => refreshActions(setState));
                        },
                      ),
                      (pathHistorySet.contains(entry.path)
                          ? ListTile(
                              title: const Text('Remove from history'),
                              onTap: () {
                                widget.conn.historyRemove(entry.path).then((_) => refreshHistory());
                                Navigator.of(context).pop();
                              },
                            )
                          : ListTile(
                              title: const Text('Add to history'),
                              onTap: () {
                                widget.conn.historyAdd(entry.path).then((_) => refreshHistory());
                                Navigator.of(context).pop();
                              },
                            ))
                    ],
                  )
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
    return FutureBuilder<void>(
      future: loadingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loading...')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return SplitView(
          title: Text(entryPath),
          drawer: ReorderableListView(
            onReorder: (oldIndex, newIndex) {
              if (oldIndex < newIndex) {
                newIndex--;
              }
              setState(() {
                final item = bookmarks.removeAt(oldIndex);
                bookmarks.insert(newIndex, item);
              });
              widget.conn.bookmarksReorder(bookmarks);
            },
            scrollController: AdjustableScrollController(100),
            children: [
              for (final bookmark in bookmarks)
                ListTile(
                  key: Key(bookmark),
                  title: entryRow(NfmEntry.fromBookmarkPath(bookmark)),
                  onTap: () => fetchEntries(NfmEntry.fromBookmarkPath(bookmark)),
                ),
            ],
          ),
          body: ListView(
            controller: AdjustableScrollController(100),
            children: [
              for (final entry in entries)
                ListTile(
                  title: entryRow(entry),
                  tileColor: pathHistorySet.contains(entry.path) ? Colors.green : null,
                  onTap: () {
                    if (entry.type == NfmEntryType.dir) {
                      fetchEntries(entry);
                    } else {
                      actionDialog(entry).then((_) => setState(() {}));
                    }
                  },
                )
            ],
          ),
        );
      },
    );
  }
}
