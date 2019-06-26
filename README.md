# angular_sentry

Helper to implements sentry with Angular.

## Usage

### Basic

```dart
import "package:angular/angular.dart";
import "package:angular_sentry/angular_sentry.dart";

// ignore: uri_has_not_been_generated
import 'main.template.dart' as ng;

const sentryModule = Module(provide: [
    ValueProvider.forToken(sentryLoggerToken, "MY_SENTRY_DSN"),
    ValueProvider.forToken(sentryEnvironmentToken, "production"),
    ValueProvider.forToken(sentryReleaseVersionToken, "1.0.0"),
    ClassProvider<ExceptionHandler>(
        ExceptionHandler,
        useClass: AngularSentry,
      ),
]);

@GenerateInjector(
  [sentryModule],
)
const scannerApp = ng.scannerApp$Injector;

main() {
  runApp(appComponentNgFactory, createInjector: scannerApp);
}
```

### Advanced

Implement your own class using AngularSentry

```dart

const sentryModule = Module(provide: [
    ...
    ClassProvider<ExceptionHandler>(
        ExceptionHandler,
        useClass: AppSentry,
      ),
]);

main() {
  runApp(appComponentNgFactory, createInjector: scannerApp);
}

class AppSentry extends AngularSentry {
  AppSentry(Injector injector, NgZone zone)
      : super(
          injector,
          zone,
          dsn: "MY_SENTRY_DSN",
          environment: "production",
          release: "1.0.0",
        );

  @override
  Event transformEvent(Event e) {
    return super.transformEvent(e).replace(
      userContext: new User(id: '1', ipAddress: '0.0.0.0'),
      extra: {"location_url": window.location.href},
    );
  }

  @override
  void capture(exception, [trace, String reason]) {
    if (exception is ClientException) {
      logError("Network error");
    } else {
      super.capture(exception, trace, reason);
    }
  }
}

```
