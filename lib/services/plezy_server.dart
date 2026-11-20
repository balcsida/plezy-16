/// Base URL of the Plezy server: the tracker OAuth proxy (`/auth`), log
/// uploads (`/logs`) and Discord posters (`/posters`). Watch Together rooms
/// run on Open Watch Party relays, not here.
///
/// A fork runs its own instance of `server/` (TRADEMARKS.md) and names it at
/// build time; the tracker registrations are build-time values the same way.
const String plezyServerBaseUrl = String.fromEnvironment('PLEZY_SERVER_URL', defaultValue: 'https://ice.plezy.app');
