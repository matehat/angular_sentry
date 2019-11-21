library angular_sentry;

import "dart:html" as html;
import 'dart:async';

import 'package:meta/meta.dart';
import 'package:angular/angular.dart';
import 'package:logging/logging.dart';
import 'package:sentry/browser_client.dart';
import 'package:http/http.dart';

export 'package:sentry/sentry.dart';

typedef Event TransformEvent(Event e);

/// Use to transform the event before sending to sentry
/// add tags or extra for example
const sentryTransformEventToken = OpaqueToken<TransformEvent>(
  'sentry.transformEvent',
);

/// provide environment data to the sentry report
const sentryEnvironmentToken = OpaqueToken<String>('sentry.env');

/// The release version of the application.
const sentryReleaseVersionToken = OpaqueToken<String>('sentry.release');

/// Pass Logger to sentry
/// If no logger, it will print exception to console
const sentryLoggerToken = OpaqueToken<Logger>('sentry.logger');

/// Provide sentry dsn
/// If no dsn provided, it will log the exception without reporting it to sentry
const sentryDsnToken = OpaqueToken<String>('sentry.dsn');

const _breadcrumbsLimit = 30;

class AngularSentry implements ExceptionHandler {
  final Logger log;
  final String environment;
  final String release;
  final String dsn;
  final Client client;
  final TransformEvent eventTransformer;

  final _exceptionController = StreamController<Event>.broadcast();

  Stream<Event> _onException;
  SentryClient _sentry;

  ApplicationRef _appRef;

  StreamSubscription<Breadcrumb> _loggerListener;
  List<Breadcrumb> _breadcrumbs = [];

  AngularSentry(
    Injector injector, {
    @Optional() this.client,
    @Optional() @Inject(sentryDsnToken) this.dsn,
    @Optional() @Inject(sentryLoggerToken) this.log,
    @Optional() @Inject(sentryEnvironmentToken) this.environment,
    @Optional() @Inject(sentryReleaseVersionToken) this.release,
    @Optional() @Inject(sentryTransformEventToken) this.eventTransformer,
  }) {
    // prevent DI circular dependency
    new Future<Null>.delayed(Duration.zero, () {
      _appRef = injector.get(ApplicationRef) as ApplicationRef;
    });

    _onException = _exceptionController.stream
        .map(
          transformEvent,
        )
        .where(
          (event) => event != null,
        )..listen(
            _sendEvent,
            onError: logError,
          );

    _loggerListener =
        Logger.root.onRecord.map(_recordToBreadcrumb).listen(_buildBreadcrumbs);

    _initSentry();
  }

  void _initSentry() {
    if (dsn == null) return;

    try {
      _sentry = SentryClient(
        dsn: dsn,
        httpClient: client,
        environmentAttributes: Event(
          environment: environment,
          release: release,
        ),
      );
    } catch (e, s) {
      logError(e, s);
    }
  }

  void _sendEvent(Event e) {
    try {
      _sentry?.capture(event: e);
    } catch (e, s) {
      logError(e, s);
    }
  }

  /// onException stream after [transformEvent] call
  Stream<Event> get onException => _onException;

  /// can be override to transform sentry report
  /// adding tags or extra for example
  @protected
  @mustCallSuper
  Event transformEvent(Event e) {
    try {
      if (eventTransformer == null) return e;

      return eventTransformer(e);
    } catch (e, s) {
      logError(e, s);
      return e;
    }
  }

  /// Log the catched error using Logging
  /// if no logger provided, print into console with window.console.error
  void logError(exception, [stackTrace, String reason]) {
    if (log != null) {
      log.severe(reason, exception, stackTrace);
    } else {
      logErrorWindow(exception, stackTrace, reason);
    }
  }

  /// log error using window.console.error
  void logErrorWindow(exception, [stackTrace, String reason]) {
    if (reason != null) html.window.console.error(reason.toString());

    html.window.console.error(exception.toString());

    if (stackTrace != null) html.window.console.error(stackTrace.toString());
  }

  @protected
  @mustCallSuper
  void capture(dynamic exception, [dynamic stackTrace, String reason]) =>
      _exceptionController.add(Event(
        exception: exception,
        stackTrace: stackTrace,
        message: reason,
      ));

  @override
  @protected
  void call(dynamic exception, [dynamic stackTrace, String reason]) {
    logError(exception, stackTrace, reason);
    capture(exception, stackTrace, reason);

    // not sure about this
    // the application state might not be clean
    _appRef?.tick();
  }

  void dispose() {
    _exceptionController.close();
    _loggerListener.cancel();
    _sentry.close();
  }

  void _buildBreadcrumbs(Breadcrumb breadcrumb) {
    if (_breadcrumbs.length >= _breadcrumbsLimit) {
      _breadcrumbs.removeAt(0);
    }
    _breadcrumbs.add(breadcrumb);
  }
}

SeverityLevel _logLevelToSeverityLevel(Level level) {
  if (level == Level.WARNING) {
    return SeverityLevel.warning;
  }

  if (level == Level.SEVERE) {
    return SeverityLevel.error;
  }

  if (level == Level.SHOUT) {
    return SeverityLevel.fatal;
  }

  return SeverityLevel.info;
}

Breadcrumb _recordToBreadcrumb(LogRecord record) => Breadcrumb(
      record.message,
      record.time,
      level: _logLevelToSeverityLevel(record.level),
      category: record.loggerName,
    );
