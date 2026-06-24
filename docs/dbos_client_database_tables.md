# DBOS Client — PostgreSQL Tables & Queries (Haskell Port Reference)

## Schema overview

8 PostgreSQL tables, all scoped under a configurable schema name (default `dbos`).

## Table: `workflow_status`

Core table — one row per workflow execution. Primary key: `workflow_uuid`.

| Column | Type | Domain type |
|---|---|---|
| workflow_uuid | TEXT | WorkflowId |
| status | TEXT | WorkflowStatusString |
| name | TEXT | FunctionName |
| class_name | TEXT | Maybe FunctionName |
| config_name | TEXT | Maybe Text |
| authenticated_user | TEXT | Maybe Text |
| authenticated_roles | TEXT | Maybe Text (JSON array) |
| assumed_role | TEXT | Maybe Text |
| queue_name | TEXT | Maybe QueueName |
| application_version | TEXT | Maybe AppVersion |
| application_id | TEXT | Maybe ApplicationId |
| executor_id | TEXT | Maybe ExecutorId |
| recovery_attempts | INTEGER | Maybe Int |
| workflow_timeout_ms | BIGINT | Maybe Int64 |
| workflow_deadline_epoch_ms | BIGINT | Maybe EpochMs |
| deduplication_id | TEXT | Maybe DeduplicationId |
| inputs | TEXT | Text (serialized, see Serializer) |
| serialization | TEXT | Maybe Text |
| queue_partition_key | TEXT | Maybe Text |
| parent_workflow_id | TEXT | Maybe WorkflowId |
| owner_xid | TEXT | Maybe OwnerXid |
| forked_from | TEXT | Maybe WorkflowId |
| was_forked_from | BOOLEAN | Bool |
| started_at_epoch_ms | BIGINT | Maybe EpochMs |
| delay_until_epoch_ms | BIGINT | Maybe EpochMs |
| attributes | JSONB | Maybe (Map Text Value) |
| schedule_name | TEXT | Maybe ScheduleName |
| created_at | BIGINT | EpochMs |
| updated_at | BIGINT | EpochMs |
| completed_at | BIGINT | Maybe EpochMs |
| priority | INTEGER | Int (default 0) |

Domain types map 1:1 via their `IsScalar` instance. The codec layer never sees
raw `Text` for ID fields — it always works through the typed newtype.

```haskell
data WorkflowStatus = WorkflowStatus
  { workflowId              :: !WorkflowId
  , status                  :: !WorkflowStatusString
  , name                    :: !FunctionName
  , className               :: !(Maybe FunctionName)
  , configName              :: !(Maybe Text)
  , authenticatedUser       :: !(Maybe Text)
  , authenticatedRoles      :: !(Maybe [Text])
  , assumedRole             :: !(Maybe Text)
  , queueName               :: !(Maybe QueueName)
  , appVersion              :: !(Maybe AppVersion)
  , appId                   :: !(Maybe ApplicationId)
  , executorId              :: !(Maybe ExecutorId)
  , recoveryAttempts        :: !(Maybe Int)
  , workflowTimeoutMs       :: !(Maybe Int64)
  , deduplicationId         :: !(Maybe DeduplicationId)
  , input                   :: !(Maybe WorkflowInputs)
  , serialization           :: !(Maybe Text)
  , queuePartitionKey       :: !(Maybe Text)
  , parentWorkflowId        :: !(Maybe WorkflowId)
  , forkedFrom              :: !(Maybe WorkflowId)
  , wasForkedFrom           :: !Bool
  , dequeuedAt              :: !(Maybe EpochMs)
  , delayUntilEpochMs       :: !(Maybe EpochMs)
  , attributes              :: !(Maybe (Map Text Value))
  , scheduleName            :: !(Maybe ScheduleName)
  , createdAt               :: !EpochMs
  , updatedAt               :: !EpochMs
  , completedAt             :: !(Maybe EpochMs)
  , priority                :: !Int
  }

data WorkflowStatusString
  = StatusEnqueued | StatusPending | StatusSuccess
  | StatusError | StatusCancelled | StatusDelayed
  | StatusMaxRecoveryAttemptsExceeded
```

---

## Table: `operation_outputs`

Function execution checkpoints for exactly-once replay. PK: `(workflow_uuid, function_id)`.

| Column | Domain type |
|---|---|
| workflow_uuid | WorkflowId |
| function_id | FunctionId |
| function_name | FunctionName |
| output | Maybe Text (serialized) |
| error | Maybe Text (serialized) |
| child_workflow_id | Maybe WorkflowId |
| started_at_epoch_ms | EpochMs |
| completed_at_epoch_ms | Maybe EpochMs |
| serialization | Maybe Text |

---

## Table: `notifications`

Inter-workflow messages. PK: `message_uuid`.

| Column | Domain type |
|---|---|
| destination_uuid | WorkflowId |
| topic | Maybe Text |
| message | Text (serialized Value) |
| message_uuid | MessageUuid |
| serialization | Maybe Text |
| created_at_epoch_ms | EpochMs |
| consumed | Bool |

---

## Table: `workflow_events`

Key-value events (latest value per key). PK: `(workflow_uuid, key)`.

| Column | Domain type |
|---|---|
| workflow_uuid | WorkflowId |
| key | Text |
| value | Maybe Text (serialized) |
| serialization | Maybe Text |

---

## Table: `workflow_events_history`

Immutable append-only log of event writes. PK: `(workflow_uuid, function_id, key)`.

| Column | Domain type |
|---|---|
| workflow_uuid | WorkflowId |
| function_id | FunctionId |
| key | Text |
| value | Maybe Text (serialized) |
| serialization | Maybe Text |

---

## Table: `streams`

Ordered stream data. PK: `(workflow_uuid, key, offset)`.

| Column | Domain type |
|---|---|
| workflow_uuid | WorkflowId |
| function_id | FunctionId |
| key | Text |
| value | Maybe Text (serialized) |
| serialization | Maybe Text |
| offset | Int |

---

## Table: `workflow_schedules`

Cron schedule definitions. PK: `schedule_name`.

| Column | Domain type |
|---|---|
| schedule_id | ScheduleId |
| schedule_name | ScheduleName |
| workflow_name | FunctionName |
| workflow_class_name | Maybe FunctionName |
| schedule | Text (cron expression) |
| status | ScheduleStatus |
| context | Maybe Text (serialized) |
| created_at | EpochMs |
| last_fired_at | Maybe EpochMs |
| automatic_backfill | Bool |
| cron_timezone | Maybe Text |
| queue_name | Maybe QueueName |

---

## Table: `queues`

Dynamic queue configuration. PK: `name`.

| Column | Domain type |
|---|---|
| name | QueueName |
| queue_id | Text (UUID) |
| concurrency | Maybe Int |
| worker_concurrency | Maybe Int |
| rate_limit_max | Maybe Int |
| rate_limit_period_sec | Maybe Double |
| priority_enabled | Bool |
| partition_queue | Bool |
| polling_interval_sec | Double |
| created_at | EpochMs |
| updated_at | EpochMs |

---

## Haskell port: PostgreSQL driver strategy

Use **hasql** + **resource-pool** for connection management.
Use **postgresql-types** + **hasql-postgresql-types** for typed codecs.

### Pattern: parameterized statement

Each query module exposes a top-level `Statement` value with typed encoder/decoder:

```haskell
-- DBOS.Client.PG.WorkflowStatus.hs

import Hasql.PostgresqlTypes ()
import qualified Hasql.Statement as Statement
import qualified Hasql.Encoders as Encoders
import qualified Hasql.Decoders as Decoders
import qualified Hasql.Mapping.IsScalar as IsScalar

enqueueStatement :: Statement.Encode EnqueueParams -> Statement.Decode EnqueueResult -> Statement EnqueueParams EnqueueResult
enqueueStatement = Statement.preparedStatement
  "INSERT INTO dbos.workflow_status (...) \
  \VALUES ($1, $2, ...) \
  \ON CONFLICT (workflow_uuid) DO UPDATE SET ... \
  \RETURNING recovery_attempts, status, workflow_deadline_epoch_ms, ..."
  ( (...) $> Encoders.param (Encoders.nonNullable IsScalar.encoder @WorkflowId)
        <> Encoders.param (Encoders.nonNullable IsScalar.encoder @WorkflowStatusString)
        <> ...
  )
  ( (...) $> Decoders.column (Decoders.nonNullable IsScalar.decoder @(Maybe Int))
        <> Decoders.column (Decoders.nonNullable IsScalar.decoder @WorkflowStatusString)
        <> ...
  )
  True
```

### Pattern: dynamic filters (list_workflows)

Build SQL + params programmatically. The WHERE clause is assembled from optional
filter fields; params are composed with `<>` into a single `Encoders.Params` tuple.

```haskell
buildListWorkflowsQuery :: ListWorkflowsFilter -> (ByteString, Encoders.Params ())
buildListWorkflowsQuery filter =
  let clauses = catMaybes
        [ (\ids -> ("workflow_uuid = ANY($1)" :: ByteString, encodeParam ids)) <$> lwfWorkflowIds filter
        , (\ss -> ("status = ANY($1)", encodeParam ss)) <$> lwfStatus filter
        , ...
        ]
      (whereParts, params) = unzip clauses
      sql = "SELECT ... FROM dbos.workflow_status"
         <> if null whereParts then "" else " WHERE " <> intercalate " AND " whereParts
         <> " ORDER BY created_at " <> if lwfSortDesc filter then "DESC" else "ASC"
         <> " LIMIT $n OFFSET $n"
   in (sql, mconcat params)
```

### Pattern: polling loop

```haskell
pollForResult :: Pool -> WorkflowId -> NominalDiffTime -> IO (WorkflowStatusString, Maybe Text, Maybe Text)
pollForResult pool wfId interval = do
  let stmt = Statement.preparedStatement
        "SELECT status, output, error FROM dbos.workflow_status WHERE workflow_uuid = $1"
        (Encoders.param (Encoders.nonNullable IsScalar.encoder @WorkflowId))
        ( (,,) <$> Decoders.column (Decoders.nonNullable IsScalar.decoder @WorkflowStatusString)
               <*> Decoders.column (Decoders.nullable IsScalar.decoder @Pt.Text)
               <*> Decoders.column (Decoders.nullable IsScalar.decoder @Pt.Text)
        )
        True
  loop
  where
    loop = do
      result <- runSession pool stmt wfId
      case result of
        Left err          -> throwM err
        Right (status, _, _)
          | status `elem` [StatusSuccess, StatusError, StatusCancelled] -> pure result
          | otherwise -> threadDelay (floor (interval * 1_000_000)) >> loop
```

### Pattern: in-transaction execution

Hasql's `Session` does not expose a `Connection` directly for in-transaction use.
Instead, use `withTransaction` from `hasql-transaction` or run the whole operation
as a single `Session` (which runs inside a libpq transaction implicitly).

---

## Query catalog by API method

### constructor / check_connection

```sql
SELECT 1
```

### enqueue

```sql
INSERT INTO <schema>.workflow_status (<28 columns>) VALUES ($1..$28)
ON CONFLICT (workflow_uuid) DO UPDATE SET
    recovery_attempts = CASE
        WHEN <schema>.workflow_status.recovery_attempts IS NULL
             OR <schema>.workflow_status.recovery_attempts < EXCLUDED.recovery_attempts
        THEN EXCLUDED.recovery_attempts
        ELSE <schema>.workflow_status.recovery_attempts
    END,
    updated_at = EXTRACT(epoch FROM now()) * 1000,
    executor_id = CASE
        WHEN EXCLUDED.executor_id IS NOT NULL THEN EXCLUDED.executor_id
        ELSE <schema>.workflow_status.executor_id
    END
RETURNING recovery_attempts, status, workflow_deadline_epoch_ms,
          name, class_name, config_name, queue_name, owner_xid, serialization
```

If recovery attempts exceeded:

```sql
UPDATE <schema>.workflow_status
SET status = 'MAX_RECOVERY_ATTEMPTS_EXCEEDED',
    deduplication_id = NULL, started_at_epoch_ms = NULL, queue_name = NULL
WHERE workflow_uuid = $1 AND status = 'PENDING'
```

### get_result (polling loop)

```sql
SELECT status, output, error, serialization
FROM <schema>.workflow_status
WHERE workflow_uuid = $1
```

### get_status / retrieve_workflow

```sql
SELECT <28 columns>
FROM <schema>.workflow_status
WHERE workflow_uuid = $1
```

### wait_first (polling loop)

```sql
SELECT workflow_uuid
FROM <schema>.workflow_status
WHERE workflow_uuid = ANY($1)
  AND status NOT IN ('PENDING', 'ENQUEUED', 'DELAYED')
LIMIT 1
```

### send / send_bulk

```sql
INSERT INTO <schema>.notifications
    (destination_uuid, topic, message, message_uuid, serialization)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (message_uuid) DO NOTHING
```

Fork tree walk (send_to_forks):

```sql
SELECT workflow_uuid, forked_from FROM <schema>.workflow_status
WHERE forked_from = ANY($1)
```

### get_event

```sql
SELECT value, serialization
FROM <schema>.workflow_events
WHERE workflow_uuid = $1 AND key = $2
```

### cancel_workflow / cancel_workflows

```sql
UPDATE <schema>.workflow_status
SET status = 'CANCELLED',
    queue_name = NULL, deduplication_id = NULL, started_at_epoch_ms = NULL,
    updated_at = EXTRACT(epoch FROM now()) * 1000,
    completed_at = EXTRACT(epoch FROM now()) * 1000
WHERE workflow_uuid = ANY($1)
  AND status NOT IN ('SUCCESS', 'ERROR')
```

Child discovery:

```sql
SELECT workflow_uuid FROM <schema>.workflow_status
WHERE parent_workflow_id = ANY($1)
```

### update_workflow_attributes

```sql
UPDATE <schema>.workflow_status
SET attributes = $1::jsonb,
    updated_at = EXTRACT(epoch FROM now()) * 1000
WHERE workflow_uuid = $2
```

### delete_workflow / delete_workflows

```sql
DELETE FROM <schema>.workflow_status
WHERE workflow_uuid = ANY($1)
```
CASCADES to `operation_outputs`, `notifications`, `workflow_events`, `workflow_events_history`, `streams`.

### resume_workflow / resume_workflows

```sql
UPDATE <schema>.workflow_status
SET status = 'ENQUEUED',
    queue_name = $1,
    recovery_attempts = 0,
    workflow_deadline_epoch_ms = NULL,
    deduplication_id = NULL,
    started_at_epoch_ms = NULL,
    updated_at = EXTRACT(epoch FROM now()) * 1000,
    completed_at = NULL
WHERE workflow_uuid = ANY($2)
  AND status NOT IN ('SUCCESS', 'ERROR')
```

### set_workflow_delay

```sql
UPDATE <schema>.workflow_status
SET delay_until_epoch_ms = $1,
    updated_at = EXTRACT(epoch FROM now()) * 1000
WHERE workflow_uuid = $2 AND status = 'DELAYED'
```

### list_workflows

Dynamic query builder. Base columns same as `get_status`. Optional WHERE clauses AND-composed:

| Filter | Column | SQL |
|---|---|---|
| workflow_ids | workflow_uuid | `= ANY($1)` |
| status | status | `= ANY($1)` |
| name | name | `= ANY($1)` |
| app_version | application_version | `= ANY($1)` |
| forked_from | forked_from | `= ANY($1)` |
| parent_workflow_id | parent_workflow_id | `= ANY($1)` |
| user | authenticated_user | `= ANY($1)` |
| queue_name | queue_name | `= ANY($1)` |
| executor_id | executor_id | `= ANY($1)` |
| workflow_id_prefix | workflow_uuid | `LIKE $1 \|\| '%'` |
| start_time | created_at | `>= $1` |
| end_time | created_at | `<= $1` |
| completed_after | completed_at | `>= $1` |
| completed_before | completed_at | `<= $1` |
| dequeued_after | started_at_epoch_ms | `>= $1` |
| dequeued_before | started_at_epoch_ms | `<= $1` |
| was_forked_from | was_forked_from | `= $1` |
| has_parent | parent_workflow_id | `IS NOT NULL` / `IS NULL` |
| attributes | attributes | `@> $1::jsonb` |
| schedule_name | schedule_name | `= ANY($1)` |

### list_queued_workflows

Same as list_workflows with `WHERE queue_name IS NOT NULL AND status IN ('DELAYED', 'ENQUEUED', 'PENDING')`

### list_workflow_steps

```sql
SELECT function_id, function_name, output, error, child_workflow_id,
       started_at_epoch_ms, completed_at_epoch_ms, serialization
FROM <schema>.operation_outputs
WHERE workflow_uuid = $1
ORDER BY function_id
LIMIT $2 OFFSET $3
```

### fork_workflow

Multi-step transaction:

1. **Read original**:
   ```sql
   SELECT workflow_uuid, name, class_name, config_name, application_id,
          authenticated_user, authenticated_roles, assumed_role, inputs,
          serialization, attributes
   FROM <schema>.workflow_status WHERE workflow_uuid = $1
   ```

2. **Insert forked row**:
   ```sql
   INSERT INTO <schema>.workflow_status (...)
   VALUES ($1, 'ENQUEUED', ...)
   ```

3. **Mark original**: `UPDATE ... SET was_forked_from = TRUE WHERE workflow_uuid = $1`

4. **Copy checkpoints**:
   ```sql
   INSERT INTO <schema>.operation_outputs (...)
   SELECT $1, function_id, output, error, serialization, function_name, ...
   FROM <schema>.operation_outputs
   WHERE workflow_uuid = $2 AND function_id < $3
   ```

5. **Copy event history**: similar INSERT FROM SELECT on `workflow_events_history`

6. **Copy latest events**: `workflow_events` (uses ROW_NUMBER() OVER PARTITION BY)

7. **Copy streams**: INSERT FROM SELECT on `streams`

### read_stream

```sql
SELECT value, serialization
FROM <schema>.streams
WHERE workflow_uuid = $1 AND key = $2 AND offset = $3
```

### create_schedule

```sql
INSERT INTO <schema>.workflow_schedules (...)
VALUES ($1, $2, $3, $4, $5, 'ACTIVE', $6, NULL, $7, $8, $9)
```

### list_schedules

```sql
SELECT * FROM <schema>.workflow_schedules
[WHERE status = ANY($1)]
[AND workflow_name = ANY($2)]
```

### get_schedule

```sql
SELECT * FROM <schema>.workflow_schedules WHERE schedule_name = $1
```

### delete_schedule

```sql
DELETE FROM <schema>.workflow_schedules WHERE schedule_name = $1
```

### register_queue

```sql
SELECT name FROM <schema>.queues WHERE name = $1

INSERT INTO <schema>.queues (name, concurrency, worker_concurrency, rate_limit_max,
       rate_limit_period_sec, priority_enabled, partition_queue,
       polling_interval_sec, updated_at)
VALUES ($1..$9) ON CONFLICT (name) DO UPDATE SET ...

SELECT * FROM <schema>.queues WHERE name = $1
```

### retrieve_queue

```sql
SELECT * FROM <schema>.queues WHERE name = $1
```

### list_queues

```sql
SELECT * FROM <schema>.queues
```

### delete_queue

```sql
DELETE FROM <schema>.queues WHERE name = $1
```

### set_concurrency (queue property setter)

```sql
UPDATE <schema>.queues SET concurrency = $1, updated_at = EXTRACT(epoch FROM now()) * 1000
WHERE name = $2
```
