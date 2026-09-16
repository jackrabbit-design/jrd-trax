# TraxKit

Foundation package for Trax: duration parsing and the SwiftData models/persistence layer.

## Running tests

From the `TraxKit/` directory:

```
swift test
```

On some machines this fails with `plugin for module 'SwiftDataMacros' not found`, depending on
toolchain resolution. If that happens, run instead:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Schema versioning

The SwiftData schema is currently unversioned — there is no `VersionedSchema` or
`SchemaMigrationPlan`. This is a deliberate simplification for early development. Once real
users have unsynced local `TimeEntry` rows on device, a model change without a migration plan
would be a data-loss event, so a versioned migration plan should be added before that risk is
real.

## Foreign keys

Models use plain `String` foreign keys (e.g. `TraxTask.projectId`) rather than SwiftData
`@Relationship`, to mirror the IDs of a remote system (Kantata). This means there is no cascade
delete and no referential integrity enforced at the database level. Cleaning up orphaned rows
(e.g. a deleted `Project`'s `TraxTask` rows) is the responsibility of whichever layer manages
sync/deletion.

## `Allocation` uniqueness

There should be exactly one `Allocation` row per `(taskId, date)` pair. This is an app-level
invariant, not schema-enforced — see the doc comment on `Allocation` for why (compound
uniqueness constraints require macOS 15+, and this package targets macOS 14).
