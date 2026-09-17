import 'dart:developer' as developer;

/// Structured logging.
///
/// Two rules this POC takes seriously, because they are what makes production
/// triage possible:
///  1. Every log line can carry a `correlationId`, which is the same id sent to
///     SynXis/Salesforce in the `X-Correlation-Id` header. Given a guest
///     complaint we can follow one booking across four vendors.
///  2. Nothing sensitive is ever logged. [redact] is applied to every payload
///     before it reaches a sink.
enum LogLevel { debug, info, warn, error }

typedef LogSink = void Function(LogRecord record);

class LogRecord {
  const LogRecord({
    required this.level,
    required this.message,
    required this.timestamp,
    this.name = 'luxe_stays',
    this.correlationId,
    this.context = const <String, Object?>{},
    this.error,
    this.stackTrace,
  });

  final LogLevel level;
  final String message;
  final DateTime timestamp;
  final String name;
  final String? correlationId;
  final Map<String, Object?> context;
  final Object? error;
  final StackTrace? stackTrace;

  @override
  String toString() {
    final StringBuffer b = StringBuffer()
      ..write('[${level.name.toUpperCase()}] ')
      ..write(message);
    if (correlationId != null) {
      b.write(' cid=$correlationId');
    }
    if (context.isNotEmpty) {
      b.write(' ${AppLogger.redact(context)}');
    }
    if (error != null) {
      b.write(' error=$error');
    }
    return b.toString();
  }
}

class AppLogger {
  AppLogger({
    this.minimumLevel = LogLevel.debug,
    List<LogSink>? sinks,
  }) : _sinks = sinks ?? <LogSink>[_developerSink];

  final LogLevel minimumLevel;
  final List<LogSink> _sinks;

  /// Keys whose values must never leave the device in plain text.
  static const Set<String> sensitiveKeys = <String>{
    'authorization',
    'access_token',
    'refresh_token',
    'client_secret',
    'password',
    'cardnumber',
    'card_number',
    'pan',
    'cvv',
    'cvc',
    'expiry',
    'email',
    'phone',
    'firstname',
    'lastname',
    'x-api-key',
    'apikey',
    'api_key',
    'guestname',
  };

  void debug(
    String message, {
    String? correlationId,
    Map<String, Object?>? context,
  }) => _log(LogLevel.debug, message, correlationId, context, null, null);

  void info(
    String message, {
    String? correlationId,
    Map<String, Object?>? context,
  }) => _log(LogLevel.info, message, correlationId, context, null, null);

  void warn(
    String message, {
    String? correlationId,
    Map<String, Object?>? context,
    Object? error,
  }) => _log(LogLevel.warn, message, correlationId, context, error, null);

  void error(
    String message, {
    String? correlationId,
    Map<String, Object?>? context,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _log(LogLevel.error, message, correlationId, context, error, stackTrace);

  void _log(
    LogLevel level,
    String message,
    String? correlationId,
    Map<String, Object?>? context,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (level.index < minimumLevel.index) {
      return;
    }
    final LogRecord record = LogRecord(
      level: level,
      message: message,
      timestamp: DateTime.now().toUtc(),
      correlationId: correlationId,
      context: context ?? const <String, Object?>{},
      error: error,
      stackTrace: stackTrace,
    );
    for (final LogSink sink in _sinks) {
      sink(record);
    }
  }

  /// Recursively replaces the values of [sensitiveKeys] with `***`.
  ///
  /// Applied to headers and bodies before they are logged, so a
  /// `--verbose` build never writes a bearer token or a PAN to logcat.
  static Map<String, Object?> redact(Map<Object?, Object?> input) {
    final Map<String, Object?> out = <String, Object?>{};
    input.forEach((Object? key, Object? value) {
      final String k = key.toString();
      if (sensitiveKeys.contains(k.toLowerCase())) {
        out[k] = '***';
      } else if (value is Map) {
        out[k] = redact(value);
      } else if (value is List) {
        out[k] = value
            .map((Object? e) => e is Map ? redact(e) : e)
            .toList(growable: false);
      } else {
        out[k] = value;
      }
    });
    return out;
  }

  static void _developerSink(LogRecord record) {
    developer.log(
      record.toString(),
      name: record.name,
      time: record.timestamp,
      level: switch (record.level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warn => 900,
        LogLevel.error => 1000,
      },
      error: record.error,
      stackTrace: record.stackTrace,
    );
  }
}
