import 'dart:collection';

import 'errors.dart';

typedef JsonObject = Map<String, Object?>;

final class JsonReader {
  JsonReader(this.value, this.path);

  final JsonObject value;
  final String path;

  static JsonReader root(Object? value) =>
      JsonReader(object(value, r'$'), r'$');

  static JsonObject object(Object? value, String path) {
    if (value is! Map) {
      throw CoordinatorProtocolException(
        'Expected a JSON object at $path.',
        path: path,
      );
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw CoordinatorProtocolException(
          'Expected string object keys at $path.',
          path: path,
        );
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  Object? raw(String key) => value[key];

  bool contains(String key) => value.containsKey(key);

  JsonReader requiredObject(String key) {
    if (!value.containsKey(key)) {
      throw _missing(key);
    }
    return JsonReader(object(value[key], '$path.$key'), '$path.$key');
  }

  JsonReader? optionalObject(String key) {
    final item = value[key];
    if (item == null) {
      return null;
    }
    return JsonReader(object(item, '$path.$key'), '$path.$key');
  }

  List<Object?> requiredList(String key) {
    if (!value.containsKey(key)) {
      throw _missing(key);
    }
    return _list(value[key], '$path.$key');
  }

  List<Object?> optionalList(String key) {
    final item = value[key];
    return item == null ? const [] : _list(item, '$path.$key');
  }

  String requiredString(String key) {
    if (!value.containsKey(key)) {
      throw _missing(key);
    }
    final item = value[key];
    if (item is! String || item.trim().isEmpty) {
      throw _type(key, 'a non-empty string');
    }
    return item;
  }

  String? optionalString(String key) {
    final item = value[key];
    if (item == null) {
      return null;
    }
    if (item is! String) {
      throw _type(key, 'a string or null');
    }
    return item;
  }

  int requiredInt(String key) {
    if (!value.containsKey(key)) {
      throw _missing(key);
    }
    final item = value[key];
    if (item is! int) {
      throw _type(key, 'an integer');
    }
    return item;
  }

  int? optionalInt(String key) {
    final item = value[key];
    if (item == null) {
      return null;
    }
    if (item is! int) {
      throw _type(key, 'an integer or null');
    }
    return item;
  }

  double? optionalDouble(String key) {
    final item = value[key];
    if (item == null) {
      return null;
    }
    if (item is! num) {
      throw _type(key, 'a number or null');
    }
    final result = item.toDouble();
    if (!result.isFinite) {
      throw _type(key, 'a finite number or null');
    }
    return result;
  }

  bool requiredBool(String key) {
    if (!value.containsKey(key)) {
      throw _missing(key);
    }
    final result = _boolish(value[key]);
    if (result == null) {
      throw _type(key, 'a boolean');
    }
    return result;
  }

  bool? optionalBool(String key) {
    final item = value[key];
    if (item == null) {
      return null;
    }
    final result = _boolish(item);
    if (result == null) {
      throw _type(key, 'a boolean or 0/1');
    }
    return result;
  }

  DateTime requiredDate(String key) {
    final raw = requiredString(key);
    final result = DateTime.tryParse(raw);
    if (result == null) {
      throw _type(key, 'an ISO-8601 timestamp');
    }
    return result;
  }

  DateTime? optionalDate(String key) {
    final raw = optionalString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final result = DateTime.tryParse(raw);
    if (result == null) {
      throw _type(key, 'an ISO-8601 timestamp or null');
    }
    return result;
  }

  List<String> optionalStringList(String key) {
    final list = optionalList(key);
    return List.unmodifiable(
      list.indexed.map((entry) {
        final (index, item) = entry;
        if (item is! String) {
          throw CoordinatorProtocolException(
            'Expected a string at $path.$key[$index].',
            path: '$path.$key[$index]',
          );
        }
        return item;
      }),
    );
  }

  CoordinatorProtocolException _missing(String key) =>
      CoordinatorProtocolException(
        'Missing required JSON field $path.$key.',
        path: '$path.$key',
      );

  CoordinatorProtocolException _type(String key, String expected) =>
      CoordinatorProtocolException(
        'Expected $expected at $path.$key.',
        path: '$path.$key',
      );

  static List<Object?> _list(Object? value, String path) {
    if (value is! List) {
      throw CoordinatorProtocolException(
        'Expected a JSON array at $path.',
        path: path,
      );
    }
    return value.cast<Object?>();
  }

  static bool? _boolish(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value == 0) {
      return false;
    }
    if (value == 1) {
      return true;
    }
    return null;
  }
}

Object? deepFreezeJson(Object? value, [String path = r'$']) {
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.indexed.map(
        (entry) => deepFreezeJson(entry.$2, '$path[${entry.$1}]'),
      ),
    );
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw CoordinatorProtocolException(
          'Expected string object keys at $path.',
          path: path,
        );
      }
      result[entry.key as String] = deepFreezeJson(
        entry.value,
        '$path.${entry.key}',
      );
    }
    return UnmodifiableMapView(result);
  }
  throw CoordinatorProtocolException(
    'Unsupported JSON value at $path.',
    path: path,
  );
}

/// Removes credentials from decoded server JSON before it can reach a model or
/// an exception.
///
/// Sensitive field names are removed even when a server returns a different
/// credential value. Exact occurrences of the bearer used for the request are
/// also removed from keys and free-form strings.
Object? redactJsonCredentials(Object? value, String credential) {
  if (value is String) {
    return value.replaceAll(credential, '[redacted]');
  }
  if (value is List) {
    return value
        .map((item) => redactJsonCredentials(item, credential))
        .toList(growable: false);
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const CoordinatorProtocolException(
          'Expected string object keys in coordinator JSON.',
        );
      }
      final rawKey = entry.key as String;
      final safeKey = rawKey.replaceAll(credential, '[redacted]');
      result[safeKey] = _isCredentialField(rawKey)
          ? '[redacted]'
          : redactJsonCredentials(entry.value, credential);
    }
    return result;
  }
  return value;
}

bool _isCredentialField(String key) {
  final normalized = key.toLowerCase().replaceAll('-', '_');
  return const {
    'authorization',
    'proxy_authorization',
    'token',
    'access_token',
    'refresh_token',
    'id_token',
    'client_secret',
    'api_key',
    'apikey',
    'bearer',
    'coordinator_bearer',
    'credential',
    'credentials',
    'password',
    'secret',
    'private_key',
    'signing_key',
    'cookie',
    'set_cookie',
  }.contains(normalized);
}
