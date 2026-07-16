# Versioning And Migrations

Modex uses semantic application versions plus a monotonically increasing build number. The source of truth is `ModexApplicationVersion` in `Sources/ModexCore/Models`.

## Release Bump

For a new release:

1. Update `ModexApplicationVersion.current`.
2. Increment `ModexApplicationVersion.buildNumber`.
3. Decide whether persisted or derived data is still compatible.
4. Add an ordered startup migration when cache invalidation or transformation is required.
5. Run `swift run modex --version` and package the app.

`scripts/package-app.sh` asks the compiled executable for its version and build number, then writes both into the bundle `Info.plist`. The CLI, SwiftUI version labels, and packaged metadata therefore use the same values.

## Startup Migrations

`ModexStartupMigrator` stores the last successfully run application version in `UserDefaults`. Migrations are selected by the version in which they were introduced and run oldest first before settings or persistent stores are opened.

Migration operations must be idempotent because an interrupted or failed migration is retried at the next launch. The last-run version advances only after every pending operation succeeds. A newer recorded version is never overwritten during a downgrade.

Each migration must use a fixed literal introduction version. Never register a migration with `.current`, because changing the current release would also move the historical migration boundary.

The current scan cache and Codex sidebar-state cache are process-local, so restarting Modex already rebuilds them. A future persistent cache should live under Modex Application Support and register an explicit removal or transformation migration whenever its format or the interpreted Codex schema changes.

## Storage Schemas

Application versions and storage schemas solve different problems. `history.sqlite` uses SQLite `PRAGMA user_version` and owns its additive schema migrations. Future stores should do the same and reject databases created by a newer unsupported schema.

Cross-store changes, semantic reinterpretation of saved values, or deliberate cache resets belong in the application startup migration catalog. A change confined to one SQLite table belongs in that store's schema migration.

## Updates

No update framework is included yet. Sparkle can be evaluated once Modex has a signed, notarized, and published distribution with an authenticated update feed. Adding update checks must not change the version source of truth or silently perform data migration before the new application has launched successfully.
