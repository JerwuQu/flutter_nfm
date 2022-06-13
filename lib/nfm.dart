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
  NfmEntryType type;
  String title;
  String uriPath; // path after base path

  NfmEntry(this.type, this.title, this.uriPath);

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
    return NfmEntry(NfmEntryType.dir, endingSlash(uriPath), uriPath);
  }
}

class NfmException implements Exception {
  final String message;

  NfmException(this.message);
}

String endingSlash(String uri) {
  return uri.endsWith('/') ? uri : '$uri/';
}

String noStartingSlash(String uri) {
  return uri.startsWith('/') ? uri.substring(1) : uri;
}

String joinPaths(String a, String b) {
  return endingSlash(a) + noStartingSlash(b);
}

String removePathSegment(String uri) {
  uri = uri.endsWith('/') ? uri.substring(0, uri.length - 1) : uri;
  final i = uri.lastIndexOf('/');
  return i > 0 ? uri.substring(0, i) : '';
}

class Nfm {
  final ConnectionInfo conn;

  Nfm(this.conn);

  Uri entryUrl(NfmEntry? entry) {
    final baseUrl = Uri.parse(conn.url);
    if (entry == null) {
      return baseUrl.replace(path: endingSlash(baseUrl.path));
    }
    return entry.type == NfmEntryType.dir
        ? baseUrl.replace(path: endingSlash(joinPaths(baseUrl.path, entry.uriPath)))
        : baseUrl.replace(path: joinPaths(baseUrl.path, entry.uriPath));
  }

  Future<List<NfmEntry>> fetch([NfmEntry? entry]) async {
    if (entry != null && entry.type != NfmEntryType.dir) {
      throw NfmException('Not a directory');
    }
    Map<String, String> headers = {
      'user-agent': 'nfm',
      'content-type': 'application/json',
    };
    if (conn.username.isNotEmpty || conn.password.isNotEmpty) {
      headers['authorization'] =
          'Basic ${base64Encode(utf8.encode('${conn.username}:${conn.password}'))}';
    }
    Response resp;
    try {
      resp = await http.get(entryUrl(entry), headers: headers);
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
          entry == null ? e['name'] : noStartingSlash(joinPaths(entry.uriPath, e['name'])),
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
