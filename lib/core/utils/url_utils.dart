import '../constants/api_constants.dart';

class UrlUtils {
  static String normalizeMediaUrl(String? url) {
    final raw = (url ?? '').trim();
    if (raw.isEmpty) return '';

    final originRaw = ApiConstants.baseUrl.replaceAll('/api/v1', '');
    final origin = Uri.tryParse(originRaw);

    // Relative URL.
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      // Backend bug: sometimes returns file:// URLs (invalid for network images).
      if (raw.startsWith('file://')) return '';
      if (origin == null) return raw;
      if (raw.startsWith('/')) return origin.resolve(raw).toString();
      return origin.resolve('/$raw').toString();
    }

    final uri = Uri.tryParse(raw);
    if (uri == null || origin == null) return raw;

    if (uri.scheme == 'file') return '';

    // Backend sometimes returns localhost URLs; replace with our API origin host.
    final isLocalHost = uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '10.0.2.2';
    if (!isLocalHost) return raw;

    return uri
        .replace(
          scheme: origin.scheme,
          host: origin.host,
          port: origin.hasPort ? origin.port : null,
        )
        .toString();
  }
}
