Uri? publicSourceUri(String? value) {
  if (value == null || RegExp(r'[\s\\]').hasMatch(value)) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      uri.host.isEmpty ||
      (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (!host.contains('.') ||
      !RegExp(r'^[a-z0-9.-]+$').hasMatch(host) ||
      RegExp(r'^[\d.]+$').hasMatch(host) ||
      host
          .split('.')
          .any(
            (part) =>
                part.isEmpty || part.startsWith('-') || part.endsWith('-'),
          )) {
    return null;
  }
  return uri;
}

bool sourceMatchesDomain(String? url, String? domain) {
  final uri = publicSourceUri(url);
  final expected = publicSourceUri(domain == null ? null : 'https://$domain');
  if (uri == null ||
      expected == null ||
      expected.path.isNotEmpty ||
      expected.hasQuery ||
      expected.hasFragment) {
    return false;
  }
  String normalize(String host) => host.replaceFirst(RegExp(r'^www\.'), '');
  final host = normalize(uri.host);
  final allowed = normalize(expected.host);
  return host == allowed || host.endsWith('.$allowed');
}
