import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/io/io_exception.dart';

void main() {
  group('NerveException', () {
    test('creates with message only', () {
      final exception = NerveException('Test error');

      expect(exception.message, 'Test error');
      expect(exception.cause, isNull);
      expect(exception.toString(), 'NerveException: Test error');
    });

    test('creates with message and cause', () {
      final cause = Exception('Root cause');
      final exception = NerveException('Test error', cause);

      expect(exception.message, 'Test error');
      expect(exception.cause, cause);
      expect(exception.toString(), contains('Test error'));
      expect(exception.toString(), contains('cause:'));
    });

    test('implements Exception interface', () {
      final exception = NerveException('Test');

      expect(exception, isA<Exception>());
    });
  });

  group('ConnectionFailedException', () {
    test('extends NerveException', () {
      final exception = ConnectionFailedException('Connection refused');

      expect(exception, isA<NerveException>());
      expect(exception.message, 'Connection refused');
    });

    test('creates with cause', () {
      final cause = SocketException('ECONNREFUSED');
      final exception = ConnectionFailedException('Failed to connect', cause);

      expect(exception.cause, cause);
    });

    test('toString includes exception type', () {
      final exception = ConnectionFailedException('Host unreachable');

      expect(exception.toString(), contains('ConnectionFailedException'));
    });
  });

  group('ConnectionLostException', () {
    test('extends NerveException', () {
      final exception = ConnectionLostException('Connection reset');

      expect(exception, isA<NerveException>());
      expect(exception.message, 'Connection reset');
    });

    test('toString includes exception type', () {
      final exception = ConnectionLostException('Peer closed');

      expect(exception.toString(), contains('ConnectionLostException'));
    });
  });

  group('TimeoutException', () {
    test('extends NerveException', () {
      final exception = TimeoutException('Operation timed out after 30s');

      expect(exception, isA<NerveException>());
      expect(exception.message, 'Operation timed out after 30s');
    });

    test('toString includes exception type', () {
      final exception = TimeoutException('Connect timeout');

      expect(exception.toString(), contains('TimeoutException'));
    });
  });

  group('ProtocolException', () {
    test('extends NerveException', () {
      final exception = ProtocolException('Invalid frame');

      expect(exception, isA<NerveException>());
      expect(exception.message, 'Invalid frame');
    });

    test('toString includes exception type', () {
      final exception = ProtocolException('Handshake failed');

      expect(exception.toString(), contains('ProtocolException'));
    });
  });

  group('Exception hierarchy behavior', () {
    test('can catch all nerve exceptions with base type', () {
      final exceptions = <NerveException>[
        ConnectionFailedException('test'),
        ConnectionLostException('test'),
        TimeoutException('test'),
        ProtocolException('test'),
      ];

      for (final e in exceptions) {
        expect(() => throw e, throwsA(isA<NerveException>()));
      }
    });

    test('can catch specific exception types', () {
      expect(
        () => throw ConnectionFailedException('test'),
        throwsA(isA<ConnectionFailedException>()),
      );
      expect(
        () => throw ConnectionLostException('test'),
        throwsA(isA<ConnectionLostException>()),
      );
      expect(
        () => throw TimeoutException('test'),
        throwsA(isA<TimeoutException>()),
      );
      expect(
        () => throw ProtocolException('test'),
        throwsA(isA<ProtocolException>()),
      );
    });
  });
}

// Dummy class for testing cause parameter
class SocketException implements Exception {
  final String message;
  SocketException(this.message);

  @override
  String toString() => 'SocketException: $message';
}
