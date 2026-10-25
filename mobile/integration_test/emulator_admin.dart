// Shared by the integration tests. The emulators enforce the PRODUCTION rules,
// so steps reserved for staff or Cloud Functions go through the Firestore
// emulator's REST API as `owner`, which bypasses the rules.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:golden_gift/core/config/app_env.dart';
import 'package:http/http.dart' as http;

Uri _doc(String path, [String query = '']) => Uri.parse(
    'http://${AppEnv.emulatorHost}:${AppEnv.firestorePort}/v1/projects/goldengift-iq/databases/(default)/documents/$path'
    '${query.isEmpty ? '' : '?$query'}');

const _owner = {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'};

/// The code `sendOtp` issued for [phoneE164]. On the emulator the functions use
/// the log driver (nothing is sent) and mirror the code to `otp_debug/{digits}`,
/// which every client is denied.
Future<String> emulatorCode(String phoneE164) async {
  final uri = _doc('otp_debug/${phoneE164.replaceAll(RegExp(r'\D'), '')}');
  for (var attempt = 0; attempt < 40; attempt++) {
    final res = await http.get(uri, headers: _owner);
    if (res.statusCode == 200) {
      final fields = (jsonDecode(res.body) as Map<String, dynamic>)['fields'] as Map<String, dynamic>?;
      final code = (fields?['code'] as Map<String, dynamic>?)?['stringValue'] as String?;
      if (code != null) return code;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError('no OTP for $phoneE164 in otp_debug — is the functions emulator running?');
}

/// Firestore REST value encoding (the subset the tests write).
Map<String, dynamic> _value(Object? v) => switch (v) {
      null => {'nullValue': null},
      bool b => {'booleanValue': b},
      int i => {'integerValue': '$i'},
      double d => {'doubleValue': d},
      String s => {'stringValue': s},
      DateTime t => {'timestampValue': t.toUtc().toIso8601String()},
      Timestamp t => {'timestampValue': t.toDate().toUtc().toIso8601String()},
      List<dynamic> l => {
          'arrayValue': {'values': [for (final e in l) _value(e)]}
        },
      Map<String, dynamic> m => {
          'mapValue': {'fields': {for (final e in m.entries) e.key: _value(e.value)}}
        },
      _ => throw ArgumentError('unsupported value $v'),
    };

/// Merges [data] into the document at [path] as `owner` (the dashboard's writes).
Future<void> adminWrite(String path, Map<String, dynamic> data) async {
  final mask = data.keys.map((k) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent('`$k`')}').join('&');
  final res = await http.patch(
    _doc(path, mask),
    headers: _owner,
    body: jsonEncode({'fields': {for (final e in data.entries) e.key: _value(e.value)}}),
  );
  if (res.statusCode >= 300) {
    throw StateError('admin write $path failed: ${res.statusCode} ${res.body}');
  }
}
