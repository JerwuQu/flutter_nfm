import 'dart:convert';

import 'package:http/http.dart';
import 'package:http/http.dart' as http;

enum NfmEntryType {
  file,
  dir,
}

class NfmEntry {
  static String _normalizePath(NfmEntryType type, String path) =>
      type == NfmEntryType.dir ? endingSlash(noStartingSlash(path)) : noStartingSlash(path);

  final NfmEntryType type;
  final String title;
  final String path; // path after base uri

  NfmEntry(this.type, this.title, String path) : path = _normalizePath(type, path);

  NfmEntry.fromBookmarkPath(String path)
      : type = NfmEntryType.dir,
        title = endingSlash(path),
        path = _normalizePath(NfmEntryType.dir, path);

  NfmEntry toBookmark() {
    if (type != NfmEntryType.dir) {
      throw NfmException('Not a directory');
    }
    return NfmEntry(type, path, path);
  }

  Uri toUri(Uri baseUri) =>
      baseUri.replace(path: _normalizePath(type, joinPaths(baseUri.path, path)));
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
  final Uri baseUri;

  Nfm(String baseUrl, String username, String password)
      : baseUri = Uri.parse(baseUrl).replace(userInfo: _authUserInfo(username, password));

  static String? _authUserInfo(String username, String password) {
    return username.isNotEmpty || password.isNotEmpty ? '$username:$password' : null;
  }

  Uri authedEntryUrl(NfmEntry entry) => entry.toUri(baseUri);

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
          entry == null ? e['name'] : joinPaths(entry.path, e['name']),
        );
      }).toList();
      if (entry?.path.isEmpty ?? true) {
        return entries;
      } else {
        return [NfmEntry(NfmEntryType.dir, '..', removePathSegment(entry!.path))] + entries;
      }
    } catch (e) {
      throw NfmException('Invalid response. Not a valid JSON index url?');
    }
  }
}
