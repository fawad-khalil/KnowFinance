import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/enums.dart';
import 'alert_parser.dart';
import 'parsed_transaction.dart';

enum SmsAccess { granted, denied, permanentlyDenied, unsupported }

/// Reads bank alerts from the Android SMS inbox. iOS doesn't let apps read
/// SMS, so there the app relies on pasted text and statement files.
class SmsReader {
  const SmsReader([this._parser = const AlertParser()]);

  static const _channel = MethodChannel('knowfinance/sms');
  final AlertParser _parser;

  static bool get supported => Platform.isAndroid;

  Future<SmsAccess> requestAccess() async {
    if (!supported) return SmsAccess.unsupported;
    final status = await Permission.sms.request();
    if (status.isGranted) return SmsAccess.granted;
    if (status.isPermanentlyDenied) return SmsAccess.permanentlyDenied;
    return SmsAccess.denied;
  }

  /// Parses every inbox message received after [since]. Messages that
  /// aren't completed transactions are dropped by the parser.
  Future<({List<ParsedTransaction> transactions, int scanned})> read(DateTime since) async {
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'inbox',
      {'sinceMillis': since.millisecondsSinceEpoch},
    );
    final out = <ParsedTransaction>[];
    for (final m in raw ?? const <Map<Object?, Object?>>[]) {
      final t = _parser.parse(
        (m['body'] as String?) ?? '',
        sender: m['sender'] as String?,
        receivedAt: DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()),
        source: EntrySource.sms,
        useReceivedTime: true,
      );
      if (t != null) out.add(t);
    }
    return (transactions: out, scanned: raw?.length ?? 0);
  }
}
