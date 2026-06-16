/// Stable bootstrap URL — the app fetches this to discover the current
/// server URL. To point the app at a new server, edit server_config.json
/// at the repo root and push. No app rebuild needed.
const String kConfigUrl =
    'https://raw.githubusercontent.com/jeeven0099/candy/main/server_config.json';
