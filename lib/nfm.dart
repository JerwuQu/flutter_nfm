import 'dart:convert';

import 'package:http/http.dart';
import 'package:http/http.dart' as http;

class ConnectionInfo {
  String url, username, password;
  List<NfmEntry> bookmarks;

  ConnectionInfo.empty()
      : url = '',
        username = '',
        password = '',
        bookmarks = [];
  ConnectionInfo.copy(ConnectionInfo source)
      : url = source.url,
        username = source.username,
        password = source.password,
        bookmarks = source.bookmarks;

  ConnectionInfo.fromJson(Map<String, dynamic> json)
      : url = json['url'],
        username = json['username'],
        password = json['password'],
        bookmarks =
            (json['bookmarks'] as List<dynamic>).map((e) => NfmEntry.fromBookmarkJson(e)).toList();
  toJson() => {
        'url': url,
        'username': username,
        'password': password,
        'bookmarks': bookmarks.map((e) => e.toBookmarkJson()).toList(),
      };
}

enum NfmEntryType {
  file,
  dir,
}

class NfmEntry {
  static String _normalizePath(NfmEntryType type, String path) =>
      noStartingSlash(type == NfmEntryType.dir ? endingSlash(path) : path);

  final NfmEntryType type;
  final String title;
  final String uriPath; // path after base path

  NfmEntry(this.type, this.title, String uriPath) : uriPath = _normalizePath(type, uriPath);

  NfmEntry.fromBookmarkJson(Map<String, dynamic> json)
      : type = NfmEntryType.dir,
        title = endingSlash(json['uri']),
        uriPath = json['uri'];

  toBookmarkJson() {
    if (type != NfmEntryType.dir) {
      throw NfmException('Not a directory');
    }
    return {'uri': uriPath};
  }

  NfmEntry toBookmark() {
    if (type != NfmEntryType.dir) {
      throw NfmException('Not a directory');
    }
    return NfmEntry(type, uriPath, uriPath);
  }

  Uri toUri(Uri baseUri) =>
      baseUri.replace(path: _normalizePath(type, joinPaths(baseUri.path, uriPath)));
}

class NfmException implements Exception {
  final String message;

  NfmException(this.message);
}

String endingSlash(String uri) => uri.endsWith('/') ? uri : '$uri/';
String noStartingSlash(String uri) => uri.startsWith('/') ? uri.substring(1) : uri;
String joinPaths(String a, String b) => endingSlash(a) + noStartingSlash(b);

String removePathSegment(String uri) {
  uri = uri.endsWith('/') ? uri.substring(0, uri.length - 1) : uri;
  final i = uri.lastIndexOf('/');
  return i > 0 ? uri.substring(0, i) : '';
}

class Nfm {
  final ConnectionInfo conn;

  Nfm(this.conn);

  String? _authUserInfo() {
    return conn.username.isNotEmpty || conn.password.isNotEmpty
        ? '${conn.username}:${conn.password}'
        : null;
  }

  Uri authedEntryUrl(NfmEntry entry) =>
      entry.toUri(Uri.parse(conn.url).replace(userInfo: _authUserInfo()));

  Future<List<NfmEntry>> fetch([NfmEntry? entry]) async {
    if (entry != null && entry.type != NfmEntryType.dir) {
      throw NfmException('Not a directory');
    }
    Map<String, String> headers = {
      'user-agent': 'nfm',
      'content-type': 'application/json',
    };
    Response resp;
    try {
      resp = await http.get(
        authedEntryUrl(entry ?? NfmEntry(NfmEntryType.dir, '', '')),
        headers: headers,
      );
    } catch (e) {
      throw NfmException('Failed to connect to host');
    }
    if (resp.statusCode == 401) {
      throw NfmException('Invalid username/password');
    } else if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw NfmException('Invalid response. Not a valid RPC url?');
    }

    try {
      List<dynamic> res = jsonDecode(resp.body);
      final entries = res.map((e) {
        return NfmEntry(
          e['type'] == 'directory' ? NfmEntryType.dir : NfmEntryType.file,
          e['name'],
          entry == null ? e['name'] : joinPaths(entry.uriPath, e['name']),
        );
      }).toList();
      if (entry?.uriPath.isEmpty ?? true) {
        return entries;
      } else {
        return [NfmEntry(NfmEntryType.dir, '..', removePathSegment(entry!.uriPath))] + entries;
      }
    } catch (e) {
      throw NfmException('Invalid response. Not a valid JSON index url?');
    }
  }
}
