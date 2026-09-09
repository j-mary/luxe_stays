import 'package:dio/dio.dart';

import '../../utils/ids.dart';

/// Stamps every outbound request with a correlation id and echoes it back onto
/// the response/error so that [ErrorMapper] can attach it to a [Failure].
///
/// The same id is sent to SynXis (`X-Correlation-Id`) and Salesforce
/// (`X-Correlation-Id`, surfaced in the Event Monitoring logs). When a guest
/// reports "my booking failed at 14:32", one grep across our logs and one
/// vendor ticket quoting the id resolves it.
class CorrelationInterceptor extends Interceptor {
  static const String header = 'X-Correlation-Id';
  static const String extraKey = 'correlationId';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final String cid =
        (options.extra[extraKey] as String?) ?? Ids.correlationId();
    options.extra[extraKey] = cid;
    options.headers[header] = cid;
    options.extra['startedAtMs'] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }
}
