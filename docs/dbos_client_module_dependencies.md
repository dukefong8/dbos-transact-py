# DBOS Client — Haskell Port: Architecture & Dependencies

## Porting strategy

The Python `DBOSClient` is a synchronous class whose every async variant is a thin `asyncio.to_thread` wrapper.
In Haskell there is one canonical `IO`-based implementation. Callers choose sync vs async at the call site via
`async` from the `async` package — no separate async variants needed.

Python's `threading.Event` for polling loops → Haskell `TVar Bool` + `STM` `retry`/`TMVar`.

## Haskell module structure

```
DBOS.Client              — Public API (DBOSClient record, WorkflowHandle types)
DBOS.Client.Internal     — Connection pool lifecycle, DBOSClient record construction
DBOS.Client.Types        — All records, sum types, newtypes, error types, IsScalar instances
DBOS.Client.PG           — PostgreSQL queries (one module per table, typed Encoders/Decoders)
  DBOS.Client.PG.WorkflowStatus
  DBOS.Client.PG.Queue
  DBOS.Client.PG.Schedule
  DBOS.Client.PG.Notification
  DBOS.Client.PG.Event
  DBOS.Client.PG.OperationOutput
  DBOS.Client.PG.QueryBuilder   — dynamic WHERE clause assembly for list_workflows
DBOS.Client.Polling      — Polling loop combinators (async + STM)
DBOS.Client.Serialize    — Serialization typeclass (JSON default, pluggable)
DBOS.Client.Schedule     — Cron parsing (croniter equivalent via `cron` package)
```

## Core types

```haskell
data DBOSClient = DBOSClient
  { pool       :: Pool
  , schema     :: SchemaName
  , serializer :: Serializer
  }

-- Handles — store workflowId + pool, expose getResult/getStatus
data WorkflowHandlePolling r = WorkflowHandlePolling
  { workflowId :: WorkflowId
  , pool       :: Pool
  }

data WorkflowHandleAsyncPolling r = WorkflowHandleAsyncPolling
  { workflowId :: WorkflowId
  , pool       :: Pool
  }
```

Haskell has one canonical type per handle; async callers wrap with `async`.

## SystemDB — just Hasql Session

No wrapper typeclass, no record of methods. `Session` is the unit of work:

```haskell
type SystemDB = Session

-- Pooled: runSession pool (Session a) → IO a
-- In-transaction: run (Connection) → IO a
```

## Serialization

```haskell
class Serializer s where
  serialize   :: s -> Value -> Text
  deserialize :: s -> Text -> Value

data DefaultSerializer = DefaultSerializer
  -- serialize = decodeUtf8 . Aeson.encode
  -- deserialize = fromMaybe Null . Aeson.decode . encodeUtf8
```

Rank-2 field in the config:

```haskell
data DBOSClientConfig = DBOSClientConfig
  { ...
  , serializer :: (forall s. Serializer s => s)
  }
```

## Enum types (sum types)

```haskell
data WorkflowStatusString
  = StatusEnqueued | StatusPending | StatusSuccess
  | StatusError | StatusCancelled | StatusDelayed
  | StatusMaxRecoveryAttemptsExceeded
  deriving (Eq, Show, Ord, Generic)

-- IsScalar instance renders via Pt.Text:
--   StatusEnqueued → "ENQUEUED"   (encoder)
--   "ENQUEUED"     → StatusEnqueued (decoder)
```

## Codec approach: postgresql-types + Hasql.IsScalar

Every domain newtype gets an `IsScalar` instance that delegates to its carrier
type's `postgresql-types` encoder/decoder (e.g. `WorkflowId` delegates to `Pt.Text`,
`EpochMs` to `Pt.Int8`). The carrier instances come from `Hasql.PostgresqlTypes`.

```haskell
import Hasql.PostgresqlTypes ()

instance IsScalar.IsScalar WorkflowId where
  encoder = contramap unWorkflowId (IsScalar.encoder @Pt.Text)
  decoder = fmap WorkflowId (IsScalar.decoder @Pt.Text)
```

Queries compose encoders/decoders explicitly — no typeclass-based row encoding:

```haskell
selectStatus :: Statement WorkflowId WorkflowStatusString
selectStatus = Statement.preparedStatement
  "SELECT status FROM dbos.workflow_status WHERE workflow_uuid = $1"
  (Encoders.param (Encoders.nonNullable IsScalar.encoder @WorkflowId))
  (Decoders.rowMaybe (Decoders.column (Decoders.nonNullable IsScalar.decoder @WorkflowStatusString)))
  True
```

## Method signatures

```haskell
-- Constructor
withDBOSClient  :: DBOSClientConfig -> (DBOSClient -> IO a) -> IO a
withDBOSClient' :: DBOSClientConfig -> IO DBOSClient

-- Workflow operations
enqueue        :: DBOSClient -> EnqueueOptions -> [Value] -> IO (WorkflowHandlePolling Value)
enqueueInTx    :: Session -> EnqueueOptions -> [Value] -> IO (WorkflowHandlePolling Value)
retrieveWorkflow :: DBOSClient -> WorkflowId -> IO (WorkflowHandlePolling Value)
waitFirst      :: DBOSClient -> [WorkflowHandlePolling a] -> IO (WorkflowHandlePolling a)
forkWorkflow   :: DBOSClient -> WorkflowId -> StepIndex -> ForkOptions -> IO (WorkflowHandlePolling Value)

-- Query operations (no polling)
getStatus      :: DBOSClient -> WorkflowId -> IO (Maybe WorkflowStatus)
getResult      :: WorkflowHandlePolling r -> NominalDiffTime -> IO r
listWorkflows  :: DBOSClient -> ListWorkflowsFilter -> IO [WorkflowStatus]

-- Notifications / Events
send           :: DBOSClient -> SendMessage -> IO ()
sendBulk       :: DBOSClient -> [SendMessage] -> IO ()
getEvent       :: DBOSClient -> WorkflowId -> Text -> NominalDiffTime -> IO (Maybe Value)

-- Queue management
registerQueue  :: DBOSClient -> QueueConfig -> IO ()
retrieveQueue  :: DBOSClient -> QueueName -> IO (Maybe QueueConfig)
deleteQueue    :: DBOSClient -> QueueName -> IO ()
listQueues     :: DBOSClient -> IO [QueueConfig]

-- Schedule management
createSchedule :: DBOSClient -> CreateScheduleInput -> IO ()
listSchedules  :: DBOSClient -> IO [WorkflowSchedule]
getSchedule    :: DBOSClient -> ScheduleName -> IO (Maybe WorkflowSchedule)
deleteSchedule :: DBOSClient -> ScheduleName -> IO ()
triggerSchedule :: DBOSClient -> ScheduleName -> IO (WorkflowHandlePolling Value)

-- Lifecycle
destroy        :: DBOSClient -> IO ()
```

Notes:
- No `*Async` suffix methods — callers use `async` from `async` package.
- No `*InTransaction` suffix methods — expose `withTransaction :: Pool -> Session a -> IO a` combinator instead.
- Dynamic filters (`listWorkflows`) build SQL via `QueryBuilder` monoid + `Encoders.Params` list.

## Error handling

```haskell
-- Infrastructure errors (SqlError, pool timeout) throw as Exception.
-- Domain errors use Either in the return type.

data InitError    = InitInvalidURL Text | InitConnectionFailed Text
data EnqueueError = EnqueueInvalidOptions ValidationError
                  | EnqueueDeduplicated WorkflowId QueueName DeduplicationId
data PollResultError = PollWorkflowNotFound WorkflowId
                     | PollWorkflowCancelled Text
                     | PollWorkflowFailed Value
-- ... etc, see Types
```

## Patterns that simplify in Haskell

1. **No async variants** — one `IO`-based implementation. Async callers use `async`.

2. **No `in_transaction` variants** — expose `withTransaction` combinator.

3. **No QuasiQuotes** — `hasql-interpolate` is not used. Raw SQL strings with `$N` params + `Encoders.param`/`Decoders.column`.

4. **Polling loops** use `TVar`/`TMVar` + async background thread. `getResult` blocks in STM.

5. **Streams** — Python's `read_stream` generator → Haskell `ConduitT` (if ported).

6. **Dynamic filters** — build WHERE clause via simple monoid, pass params as tuple.

7. **Cron parsing** — use `cron` package on Hackage instead of porting `croniter`.

## Module dependency tree

```
DBOS.Client.Types              — no deps, pure records & sum types
DBOS.Client.Serialize          — depends on: Types, aeson
DBOS.Client.Schedule           — depends on: Types, cron
DBOS.Client.PG.*               — depends on: Types, hasql, postgresql-types, hasql-postgresql-types
DBOS.Client.PG.QueryBuilder    — depends on: Types
DBOS.Client.Polling            — depends on: Types, async, stm
DBOS.Client.Internal           — depends on: PG.*, Polling, Serialize, hasql, resource-pool
DBOS.Client                    — depends on: Internal, Types (re-exports)
```
