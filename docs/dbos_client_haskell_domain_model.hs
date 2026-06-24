{- DBOS Client — Haskell Domain Model
   Maps every Python class / TypedDict / enum to idiomatic Haskell ADTs.
   Shape matches the Python original; idioms are Haskell (newtype, sum types,
   strict fields, no inheritance).

   Database layer: hasql + postgresql-types + hasql-postgresql-types.
   Every PostgreSQL type gets a precise Haskell representation in
   PostgresqlTypes.*. Domain newtypes derive their encoders/decoders
   via contramap / dimap over the IsScalar encoder/decoder of their carrier.
-}

{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE KindSignatures    #-}

module DBOS.Client.Types where

import Data.Aeson (Value)
import Data.Int (Int64)
import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Time (NominalDiffTime)
import GHC.Generics (Generic)
import GHC.TypeLits (KnownNat, Symbol)

import qualified PostgresqlTypes as Pt
import qualified Hasql.Encoders as Encoders
import qualified Hasql.Decoders as Decoders
import qualified Hasql.Mapping.IsScalar as IsScalar

-- ---------------------------------------------------------------------------
-- Core newtypes
-- ---------------------------------------------------------------------------
-- Every newtype carries a precise PostgreSQL type annotation so the
-- codec can be derived mechanically via the carrier's IsScalar instance.

newtype WorkflowId       = WorkflowId       { unWorkflowId       :: Text } deriving (Eq, Ord, Show, Generic)
newtype QueueName        = QueueName        { unQueueName        :: Text } deriving (Eq, Ord, Show, Generic)
newtype ScheduleName     = ScheduleName     { unScheduleName     :: Text } deriving (Eq, Ord, Show, Generic)
newtype FunctionId       = FunctionId       { unFunctionId       :: Int   } deriving (Eq, Ord, Show, Generic)
newtype FunctionName     = FunctionName     { unFunctionName     :: Text } deriving (Eq, Ord, Show, Generic)
newtype AppVersion       = AppVersion       { unAppVersion       :: Text } deriving (Eq, Ord, Show, Generic)
newtype ExecutorId       = ExecutorId       { unExecutorId       :: Text } deriving (Eq, Ord, Show, Generic)
newtype ApplicationId    = ApplicationId    { unApplicationId    :: Text } deriving (Eq, Ord, Show, Generic)
newtype ScheduleId       = ScheduleId       { unScheduleId       :: Text } deriving (Eq, Ord, Show, Generic)
newtype DeduplicationId  = DeduplicationId  { unDeduplicationId  :: Text } deriving (Eq, Ord, Show, Generic)
newtype MessageUuid      = MessageUuid      { unMessageUuid      :: Text } deriving (Eq, Ord, Show, Generic)
newtype OwnerXid         = OwnerXid         { unOwnerXid         :: Text } deriving (Eq, Ord, Show, Generic)
newtype SchemaName       = SchemaName       { unSchemaName       :: Text } deriving (Eq, Ord, Show, Generic)

-- Epoch milliseconds — keeps wire format exact, conversion to UTCTime is a
-- separate concern at the boundary.
newtype EpochMs          = EpochMs          { unEpochMs          :: Int64 } deriving (Eq, Ord, Show, Generic)
newtype StepIndex        = StepIndex        { unStepIndex        :: Int    } deriving (Eq, Ord, Show, Generic)


-- ---------------------------------------------------------------------------
-- Workflow lifecycle
-- ---------------------------------------------------------------------------

data WorkflowStatusString
  = StatusPending
  | StatusSuccess
  | StatusError
  | StatusMaxRecoveryAttemptsExceeded
  | StatusCancelled
  | StatusEnqueued
  | StatusDelayed
  deriving (Eq, Ord, Show, Enum, Bounded, Generic)

data WorkflowStatus = WorkflowStatus
  { workflowId              :: !WorkflowId
  , status                  :: !WorkflowStatusString
  , name                    :: !FunctionName
  , className               :: !(Maybe FunctionName)
  , configName              :: !(Maybe Text)
  , authenticatedUser       :: !(Maybe Text)
  , authenticatedRoles      :: !(Maybe [Text])
  , assumedRole             :: !(Maybe Text)
  , input                   :: !(Maybe WorkflowInputs)
  , output                  :: !(Maybe Value)
  , error                   :: !(Maybe DBOSExceptionPayload)
  , createdAt               :: !(Maybe EpochMs)
  , updatedAt               :: !(Maybe EpochMs)
  , queueName               :: !(Maybe QueueName)
  , executorId              :: !(Maybe ExecutorId)
  , appVersion              :: !(Maybe AppVersion)
  , appId                   :: !(Maybe ApplicationId)
  , recoveryAttempts        :: !(Maybe Int)
  , workflowTimeoutMs       :: !(Maybe Int64)
  , workflowDeadlineEpochMs :: !(Maybe EpochMs)
  , deduplicationId         :: !(Maybe DeduplicationId)
  , priority                :: !(Maybe Int)
  , queuePartitionKey       :: !(Maybe Text)
  , forkedFrom              :: !(Maybe WorkflowId)
  , wasForkedFrom           :: !Bool
  , parentWorkflowId        :: !(Maybe WorkflowId)
  , dequeuedAt              :: !(Maybe EpochMs)
  , delayUntilEpochMs       :: !(Maybe EpochMs)
  , completedAt             :: !(Maybe EpochMs)
  , attributes              :: !(Maybe (Map Text Value))
  , scheduleName            :: !(Maybe ScheduleName)
  }
  deriving (Eq, Show, Generic)

-- Internal insert/update shape — not returned to users. Same columns but all
-- serialized as Text, synchronized to the DB row layout.
data WorkflowStatusInternal = WorkflowStatusInternal
  { wsiWorkflowUuid           :: !WorkflowId
  , wsiStatus                 :: !WorkflowStatusString
  , wsiName                   :: !FunctionName
  , wsiClassName              :: !(Maybe FunctionName)
  , wsiConfigName             :: !(Maybe Text)
  , wsiAuthenticatedUser      :: !(Maybe Text)
  , wsiAssumedRole            :: !(Maybe Text)
  , wsiAuthenticatedRoles     :: !(Maybe Text)        -- JSON array as text
  , wsiOutput                 :: !(Maybe Text)        -- serialized
  , wsiError                  :: !(Maybe Text)        -- serialized
  , wsiCreatedAt              :: !(Maybe EpochMs)
  , wsiUpdatedAt              :: !(Maybe EpochMs)
  , wsiQueueName              :: !(Maybe QueueName)
  , wsiExecutorId             :: !(Maybe ExecutorId)
  , wsiAppVersion             :: !(Maybe AppVersion)
  , wsiAppId                  :: !(Maybe ApplicationId)
  , wsiRecoveryAttempts       :: !(Maybe Int)
  , wsiWorkflowTimeoutMs      :: !(Maybe Int64)
  , wsiWorkflowDeadlineEpochMs :: !(Maybe EpochMs)
  , wsiDeduplicationId        :: !(Maybe DeduplicationId)
  , wsiPriority               :: !Int
  , wsiInputs                 :: !Text               -- serialized
  , wsiQueuePartitionKey      :: !(Maybe Text)
  , wsiForkedFrom             :: !(Maybe WorkflowId)
  , wsiParentWorkflowId       :: !(Maybe WorkflowId)
  , wsiStartedAtEpochMs       :: !(Maybe EpochMs)
  , wsiSerialization          :: !(Maybe Text)
  , wsiOwnerXid               :: !(Maybe OwnerXid)
  , wsiDelayUntilEpochMs      :: !(Maybe EpochMs)
  , wsiAttributes             :: !(Maybe (Map Text Value))
  , wsiScheduleName           :: !(Maybe ScheduleName)
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Workflow inputs
-- ---------------------------------------------------------------------------

data WorkflowInputs = WorkflowInputs
  { wiArgs   :: ![Value]
  , wiKwargs :: !(Map Text Value)
  }
  deriving (Eq, Show, Generic)

-- JSON-serializable subset for portable workflows.
data JsonWorkflowArgs = JsonWorkflowArgs
  { jwaPositionalArgs :: !(Maybe [Value])
  , jwaNamedArgs      :: !(Maybe (Map Text Value))
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Enqueue options
-- ---------------------------------------------------------------------------

data EnqueueOptions = EnqueueOptions
  { eoWorkflowName          :: !FunctionName
  , eoQueueName             :: !QueueName
  , eoWorkflowId            :: !(Maybe WorkflowId)
  , eoAppVersion            :: !(Maybe AppVersion)
  , eoWorkflowTimeout       :: !(Maybe NominalDiffTime)
  , eoDelaySeconds          :: !(Maybe Double)
  , eoDeduplicationId       :: !(Maybe DeduplicationId)
  , eoPriority              :: !(Maybe Int)
  , eoMaxRecoveryAttempts   :: !(Maybe Int)
  , eoQueuePartitionKey     :: !(Maybe Text)
  , eoAuthenticatedUser     :: !(Maybe Text)
  , eoAuthenticatedRoles    :: !(Maybe [Text])
  , eoSerializationType     :: !(Maybe WorkflowSerializationFormat)
  , eoClassName             :: !(Maybe FunctionName)
  , eoInstanceName          :: !(Maybe Text)
  , eoAttributes            :: !(Maybe (Map Text Value))
  }
  deriving (Eq, Show, Generic)

-- Internal enqueue options — mirrors EnqueueOptionsInternal TypedDict.
data EnqueueOptionsInternal = EnqueueOptionsInternal
  { eoiDeduplicationId     :: !(Maybe DeduplicationId)
  , eoiPriority            :: !(Maybe Int)
  , eoiAppVersion          :: !(Maybe AppVersion)
  , eoiQueuePartitionKey   :: !(Maybe Text)
  , eoiDelayUntilEpochMs   :: !(Maybe EpochMs)
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Queue
-- ---------------------------------------------------------------------------

data QueueConfig = QueueConfig
  { qcName               :: !QueueName
  , qcConcurrency        :: !(Maybe Int)
  , qcWorkerConcurrency  :: !(Maybe Int)
  , qcRateLimitMax       :: !(Maybe Int)
  , qcRateLimitPeriodSec :: !(Maybe Double)
  , qcPriorityEnabled    :: !Bool
  , qcPartitionQueue     :: !Bool
  , qcPollingIntervalSec :: !Double
  }
  deriving (Eq, Show, Generic)

data QueueConflictResolution
  = ConflictUpdateIfLatestVersion
  | ConflictAlwaysUpdate
  | ConflictNeverUpdate
  deriving (Eq, Show, Generic)

data QueueRateLimit = QueueRateLimit
  { qrlLimit  :: !Int
  , qrlPeriod :: !Double
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Send / Notifications
-- ---------------------------------------------------------------------------

data SendMessage = SendMessage
  { smDestinationId  :: !WorkflowId
  , smMessage        :: !Value
  , smTopic          :: !(Maybe Text)
  , smIdempotencyKey :: !(Maybe DeduplicationId)
  }
  deriving (Eq, Show, Generic)

data NotificationInfo = NotificationInfo
  { niTopic            :: !(Maybe Text)
  , niMessage          :: !Value
  , niCreatedAtEpochMs :: !EpochMs
  , niConsumed         :: !Bool
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Steps / Operation outputs
-- ---------------------------------------------------------------------------

data RecordedResult = RecordedResult
  { rrOutput          :: !(Maybe Text)   -- serialized
  , rrError           :: !(Maybe Text)   -- serialized
  , rrSerialization   :: !(Maybe Text)
  , rrChildWorkflowId :: !(Maybe WorkflowId)
  }
  deriving (Eq, Show, Generic)

data OperationResultInternal = OperationResultInternal
  { oriWorkflowUuid     :: !WorkflowId
  , oriFunctionId       :: !FunctionId
  , oriFunctionName     :: !FunctionName
  , oriOutput           :: !(Maybe Text)    -- serialized
  , oriError            :: !(Maybe Text)    -- serialized
  , oriSerialization    :: !(Maybe Text)
  , oriStartedAtEpochMs :: !EpochMs
  }
  deriving (Eq, Show, Generic)

data StepInfo = StepInfo
  { siFunctionId         :: !FunctionId
  , siFunctionName       :: !FunctionName
  , siOutput             :: !(Maybe Value)
  , siError              :: !(Maybe DBOSExceptionPayload)
  , siChildWorkflowId    :: !(Maybe WorkflowId)
  , siStartedAtEpochMs   :: !(Maybe EpochMs)
  , siCompletedAtEpochMs :: !(Maybe EpochMs)
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

data GetEventWorkflowContext = GetEventWorkflowContext
  { gewcWorkflowUuid      :: !WorkflowId
  , gewcFunctionId        :: !FunctionId
  , gewcTimeoutFunctionId :: !FunctionId
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Schedules
-- ---------------------------------------------------------------------------

data WorkflowSchedule = WorkflowSchedule
  { wsScheduleId        :: !ScheduleId
  , wsScheduleName      :: !ScheduleName
  , wsWorkflowName      :: !FunctionName
  , wsWorkflowClassName :: !(Maybe FunctionName)
  , wsSchedule          :: !Text   -- cron expression
  , wsStatus            :: !ScheduleStatus
  , wsContext           :: !(Maybe Value)
  , wsLastFiredAt       :: !(Maybe EpochMs)
  , wsAutomaticBackfill :: !Bool
  , wsCronTimezone      :: !(Maybe Text)
  , wsQueueName         :: !(Maybe QueueName)
  }
  deriving (Eq, Show, Generic)

data ScheduleStatus
  = ScheduleActive
  | SchedulePaused
  | ScheduleCompleted
  deriving (Eq, Show, Generic)

-- Input for creating a schedule (all optional fields are wrapped).
data CreateScheduleInput = CreateScheduleInput
  { csiScheduleName      :: !ScheduleName
  , csiWorkflowName      :: !FunctionName
  , csiSchedule          :: !Text   -- cron expression
  , csiContext           :: !(Maybe Value)
  , csiWorkflowClassName :: !(Maybe FunctionName)
  , csiAutomaticBackfill :: !Bool
  , csiCronTimezone      :: !(Maybe Text)
  , csiQueueName         :: !(Maybe QueueName)
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Application versions
-- ---------------------------------------------------------------------------

data VersionInfo = VersionInfo
  { viVersionId      :: !Text
  , viVersionName    :: !Text
  , viVersionTimestamp :: !EpochMs
  , viCreatedAt      :: !EpochMs
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Metrics
-- ---------------------------------------------------------------------------

data MetricData = MetricData
  { mdMetricType :: !Text
  , mdMetricName :: !Text
  , mdValue      :: !Int
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Export / Import
-- ---------------------------------------------------------------------------

data ExportedWorkflow = ExportedWorkflow
  { ewWorkflowStatus        :: !WorkflowStatusInternal
  , ewOperationOutputs      :: ![OperationResultInternal]
  , ewWorkflowEvents        :: ![WorkflowEventRecord]
  , ewWorkflowEventsHistory :: ![WorkflowEventHistoryRecord]
  , ewStreams               :: ![(Text, Value)]
  }
  deriving (Eq, Show, Generic)

data WorkflowEventRecord = WorkflowEventRecord
  { werWorkflowUuid  :: !WorkflowId
  , werKey           :: !Text
  , werValue         :: !(Maybe Text)
  , werSerialization :: !(Maybe Text)
  }
  deriving (Eq, Show, Generic)

data WorkflowEventHistoryRecord = WorkflowEventHistoryRecord
  { wehrWorkflowUuid  :: !WorkflowId
  , wehrFunctionId    :: !FunctionId
  , wehrKey           :: !Text
  , wehrValue         :: !(Maybe Text)
  , wehrSerialization :: !(Maybe Text)
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Pending workflows (recovery)
-- ---------------------------------------------------------------------------

data GetPendingWorkflowsOutput = GetPendingWorkflowsOutput
  { gpwWorkflowId :: !WorkflowId
  , gpwQueueName  :: !(Maybe QueueName)
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Aggregation
-- ---------------------------------------------------------------------------

data WorkflowAggregateRow = WorkflowAggregateRow
  { warGroup             :: !(Map Text (Maybe Text))
  , warCount             :: !(Maybe Int)
  , warMinCreatedAt      :: !(Maybe EpochMs)
  , warMaxQueueWaitMs    :: !(Maybe Int64)
  , warMaxTotalLatencyMs :: !(Maybe Int64)
  }
  deriving (Eq, Show, Generic)

data StepAggregateRow = StepAggregateRow
  { sarGroup         :: !(Map Text (Maybe Text))
  , sarCount         :: !(Maybe Int)
  , sarMaxDurationMs :: !(Maybe Int64)
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Serialization
-- ---------------------------------------------------------------------------

data WorkflowSerializationFormat
  = SerializationPortable
  | SerializationNative
  | SerializationDefault
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Errors — per-method error types
--
-- Infrastructure errors (SqlError, connection pool timeout) propagate as
-- Exception; these cover only the domain errors that each method can
-- meaningfully produce.
-- ---------------------------------------------------------------------------

-- A newtype for a simple validation message. Shared across methods.
newtype ValidationError = ValidationError { unValidationError :: Text }
  deriving (Eq, Show, Generic)

data InitError
  = InitInvalidURL            !Text
  | InitConnectionFailed      !Text
  deriving (Eq, Show, Generic)

data EnqueueError
  = EnqueueInvalidOptions    !ValidationError
  | EnqueueDeduplicated      !WorkflowId !QueueName !DeduplicationId
  deriving (Eq, Show, Generic)

data QueueRegisterError
  = QueueRegisterInvalidOptions           !ValidationError
  | QueueRegisterUpdateIfLatestNotSupported   -- client has no app version
  deriving (Eq, Show, Generic)

data RetrieveError
  = RetrieveWorkflowNotFound  !WorkflowId
  deriving (Eq, Show, Generic)

data PollResultError
  = PollWorkflowNotFound      !WorkflowId
  | PollWorkflowCancelled     !Text
  | PollWorkflowFailed        !Value   -- user exception, opaque
  deriving (Eq, Show, Generic)

data ForkError
  = ForkWorkflowNotFound      !WorkflowId
  | ForkInvalidStep           !WorkflowId !Int
  deriving (Eq, Show, Generic)

data ScheduleCreateError
  = ScheduleInvalidCron       !Text
  | ScheduleInvalidTimezone   !Text
  | ScheduleAlreadyExists     !ScheduleName
  deriving (Eq, Show, Generic)

data WaitFirstError
  = WaitFirstEmptyList
  | WaitFirstDuplicateIds
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Method-to-error mapping
-- ---------------------------------------------------------------------------
-- constructor   │ IO (Either InitError DBOSClient)
-- enqueue       │ ExceptT EnqueueError IO WorkflowHandle
-- enqueue_in_tx │ ExceptT EnqueueError m WorkflowHandle
-- register_q    │ ExceptT QueueRegisterError IO QueueConfig
-- retrieve_q    │ IO (Maybe QueueConfig)
-- delete_q      │ IO ()
-- list_queues   │ IO [QueueConfig]
-- retrieve_wf   │ ExceptT RetrieveError IO WorkflowHandle
-- get_result    │ ExceptT PollResultError IO Value
-- get_status    │ ExceptT RetrieveError IO WorkflowStatus
-- wait_first    │ ExceptT WaitFirstError IO WorkflowHandle
-- send          │ IO ()
-- send_bulk     │ IO ()
-- send_in_tx    │ IO ()
-- get_event     │ IO (Maybe Value)
-- cancel        │ IO ()
-- delete        │ IO ()
-- resume        │ IO WorkflowHandle
-- set_delay     │ IO ()
-- update_attrs  │ IO ()
-- list_wfs      │ IO [WorkflowStatus]
-- list_steps    │ IO [StepInfo]
-- fork          │ ExceptT ForkError IO WorkflowHandle
-- read_stream   │ (not ported)
-- create_sched  │ ExceptT ScheduleCreateError IO ()
-- list_scheds   │ IO [WorkflowSchedule]
-- get_schedule  │ IO (Maybe WorkflowSchedule)
-- delete_sched  │ IO ()
-- pause_sched   │ IO ()
-- resume_sched  │ IO ()
-- trigger_sched │ IO WorkflowHandle
-- backfill_sched│ IO [WorkflowHandle]
-- list_app_vers │ IO [VersionInfo]
-- get_latest_app_ver │ IO VersionInfo
-- set_latest_app_ver │ IO ()
-- ---------------------------------------------------------------------------

-- Workflow handles
-- ---------------------------------------------------------------------------

-- Typeclass for the get_result / get_status pattern shared by all handles.
class WorkflowHandle m h r | h -> m r where
  getWorkflowId :: h -> WorkflowId
  getResult     :: h -> NominalDiffTime -> m r
  getStatus     :: h -> m WorkflowStatus

data WorkflowHandlePolling m r = WorkflowHandlePolling
  { whpWorkflowId :: !WorkflowId
  , whpSysDb     :: !(SystemDB m)
  }

data WorkflowHandleAsyncPolling m r = WorkflowHandleAsyncPolling
  { whapWorkflowId :: !WorkflowId
  , whapSysDb     :: !(SystemDB m)
  }

-- ---------------------------------------------------------------------------
-- DBOSClient config and config file types
-- ---------------------------------------------------------------------------

data DBOSClientConfig = DBOSClientConfig
  { dccSystemDatabaseUrl      :: !ByteString
  , dccApplicationDatabaseUrl :: !(Maybe ByteString)
  , dccDBOSSystemSchema       :: !SchemaName
  , dccPoolSize               :: !Int
  , dccPoolTimeout            :: !NominalDiffTime
  , dccSerializer             :: !(forall m. Serializer m => m)
  }

data RuntimeConfig = RuntimeConfig
  { rcStart          :: ![Text]
  , rcSetup          :: !(Maybe [Text])
  , rcAdminPort      :: !(Maybe Int)
  , rcRunAdminServer :: !(Maybe Bool)
  , rcMaxExecutorThreads :: !(Maybe Int)
  , rcNotificationListenerPollingIntervalSec :: !(Maybe Double)
  , rcSchedulerPollingIntervalSec :: !(Maybe Double)
  }
  deriving (Eq, Show, Generic)

data LoggerConfig = LoggerConfig
  { lcLogLevel        :: !(Maybe Text)
  , lcConsoleLogLevel :: !(Maybe Text)
  , lcOtlpLogLevel    :: !(Maybe Text)
  }
  deriving (Eq, Show, Generic)

data OTLPExporterConfig = OTLPExporterConfig
  { oecLogsEndpoint   :: !(Maybe [Text])
  , oecTracesEndpoint :: !(Maybe [Text])
  }
  deriving (Eq, Show, Generic)

data TelemetryConfig = TelemetryConfig
  { tcLogs           :: !(Maybe LoggerConfig)
  , tcOTLPExporter   :: !(Maybe OTLPExporterConfig)
  , tcOtlpAttributes :: !(Maybe (Map Text Text))
  , tcDisableOtlp    :: !Bool
  , tcOtelAttributeFormat :: !(Maybe OtelAttributeFormat)
  }
  deriving (Eq, Show, Generic)

data OtelAttributeFormat
  = OtelFormatLegacy
  | OtelFormatSemConv
  deriving (Eq, Show, Generic)

data DatabaseConfig = DatabaseConfig
  { dbcSysDbPoolSize      :: !(Maybe Int)
  , dbcDbEngineKwargs     :: !(Maybe (Map Text Value))
  , dbcSysDbEngineKwargs  :: !(Maybe (Map Text Value))
  , dbcMigrate            :: !(Maybe [Text])
  }
  deriving (Eq, Show, Generic)

data ConfigFile = ConfigFile
  { cfName              :: !Text
  , cfRuntimeConfig     :: !(Maybe RuntimeConfig)
  , cfDatabase          :: !(Maybe DatabaseConfig)
  , cfDatabaseUrl       :: !(Maybe ByteString)
  , cfSystemDatabaseUrl :: !(Maybe ByteString)
  , cfTelemetry         :: !(Maybe TelemetryConfig)
  , cfEnv               :: !(Map Text Text)
  , cfSystemDatabaseEngine :: !(Maybe ())
  , cfDBOSSystemSchema  :: !(Maybe SchemaName)
  , cfUseListenNotify   :: !Bool
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- ListWorkflows filter
-- ---------------------------------------------------------------------------

data ListWorkflowsFilter = ListWorkflowsFilter
  { lwfWorkflowIds        :: !(Maybe [WorkflowId])
  , lwfStatus             :: !(Maybe [WorkflowStatusString])
  , lwfStartTime          :: !(Maybe Text)   -- ISO-8601 string
  , lwfEndTime            :: !(Maybe Text)   -- ISO-8601 string
  , lwfCompletedAfter     :: !(Maybe Text)   -- ISO-8601 string
  , lwfCompletedBefore    :: !(Maybe Text)   -- ISO-8601 string
  , lwfDequeuedAfter      :: !(Maybe Text)   -- ISO-8601 string
  , lwfDequeuedBefore     :: !(Maybe Text)   -- ISO-8601 string
  , lwfName               :: !(Maybe [FunctionName])
  , lwfAppVersion         :: !(Maybe [AppVersion])
  , lwfForkedFrom         :: !(Maybe [WorkflowId])
  , lwfParentWorkflowId   :: !(Maybe [WorkflowId])
  , lwfUser               :: !(Maybe [Text])
  , lwfQueueName          :: !(Maybe [QueueName])
  , lwfLimit              :: !(Maybe Int)
  , lwfOffset             :: !(Maybe Int)
  , lwfSortDesc           :: !Bool
  , lwfWorkflowIdPrefix   :: !(Maybe [Text])
  , lwfLoadInput          :: !Bool
  , lwfLoadOutput         :: !Bool
  , lwfExecutorId         :: !(Maybe [ExecutorId])
  , lwfQueuesOnly         :: !Bool
  , lwfWasForkedFrom      :: !(Maybe Bool)
  , lwfHasParent          :: !(Maybe Bool)
  , lwfAttributes         :: !(Maybe (Map Text Value))
  , lwfScheduleName       :: !(Maybe [ScheduleName])
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Fork
-- ---------------------------------------------------------------------------

data ForkOptions = ForkOptions
  { foApplicationVersion  :: !(Maybe AppVersion)
  , foQueueName           :: !(Maybe QueueName)
  , foQueuePartitionKey   :: !(Maybe Text)
  , foReplacementChildren :: !(Maybe (Map WorkflowId WorkflowId))
  }
  deriving (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Serializer
-- ---------------------------------------------------------------------------
-- Pluggable serialization at the API boundary only.
-- Converts between Haskell Value (Aeson) and the TEXT stored in the DB.
-- Never called inside the query layer — postgresql-types handles Text/ByteString
-- at the DB boundary directly.
--
-- Data flow:
--   enqueue:  args → serializeArgs serializer → Text → postgresql-types Encode Text
--   get_result: postgresql-types Decode Text → Text → deserialize serializer → Value
-- ---------------------------------------------------------------------------

class Serializer s where
  serialize   :: s -> Value -> Text
  deserialize :: s -> Text -> Value

data DefaultSerializer = DefaultSerializer

instance Serializer DefaultSerializer where
  serialize _ = decodeUtf8 . encode                         -- Aeson
  deserialize _ v = fromMaybe Null $ decode (encodeUtf8 v)

-- | Serialize function args for storage. Returns (inputsText, formatName).
serializeArgs
  :: Serializer s
  => s -> Maybe WorkflowSerializationFormat -> [Value] -> Map Text Value
  -> (Text, Text)

-- | Deserialize schedule context from its stored TEXT value.
safeDeserializeScheduleContext
  :: Serializer s
  => s -> Text -> Text -> Value

-- ---------------------------------------------------------------------------
-- SystemDB — KISS: just Hasql Session
-- ---------------------------------------------------------------------------
-- Hasql's Session monad handles pooled vs direct connections:
--   withSession (Pool connStr size) :: Session a -> IO a
-- No wrapper, no typeclass, no record of methods.
-- In-transaction variants take a raw Connection.
--
-- Type conversion happens at the API boundary, not in the query layer.
-- Queries use raw SQL with typed params via Encoders/Decoders.
-- Dynamic queries (list_workflows) concatenate SQL fragments using
-- Encoders.params / Decoders.rows directly.
-- ---------------------------------------------------------------------------

type SystemDB = Session

-- ---------------------------------------------------------------------------
-- Module structure
-- ---------------------------------------------------------------------------
-- DBOS.Client                  — public API (DBOSClient record, re-exports)
-- DBOS.Client.Types            — this file (all domain types, errors, aliases)
-- DBOS.Client.PG               — raw SQL queries, Encoders/Decoders, one module per table:
--   DBOS.Client.PG.WorkflowStatus
--   DBOS.Client.PG.Queue
--   DBOS.Client.PG.Schedule
--   DBOS.Client.PG.Notification
--   DBOS.Client.PG.Event
--   DBOS.Client.PG.OperationOutput
-- DBOS.Client.PG.QueryBuilder  — dynamic WHERE clause assembly for list_workflows
-- DBOS.Client.Polling          — async + STM polling combinators
-- DBOS.Client.Serialize        — Serializer typeclass + instances
-- DBOS.Client.Schedule         — cron parsing (cron package)
-- DBOS.Client.Internal         — DBOSClient record impl, pool lifecycle
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Codecs — postgresql-types scalar instances for every domain newtype
-- ---------------------------------------------------------------------------
--
-- Each domain newtype gets an IsScalar instance that delegates to its carrier
-- type's postgresql-types encoder/decoder. The carrier's IsScalar instance
-- (from the postgresql-types package) provides the full binary+textual codec.
--
-- This replaces the previous hasql-interpolate EncodeValue/DecodeRow approach.
-- Benefits:
--   1. No template Haskell or QuasiQuotes needed
--   2. OID resolution is automatic via the postgresql-types metadata
--   3. Binary encoding is used automatically (faster than text)
--   4. Textual encoding is also available for debugging/logging
--   5. Works with nullable columns via Encoders.nullable/Decoders.nullable
--
-- Usage in a query module:
--   > import Hasql.PostgresqlTypes ()
--   > import qualified Hasql.Mapping.IsScalar as IsScalar
--   > import qualified Hasql.Encoders as Encoders
--   > import qualified Hasql.Decoders as Decoders
--   >
--   > selectStatus :: Statement WorkflowId (Maybe WorkflowStatusString)
--   > selectStatus = Statement.preparedStatement sql encoder decoder True
--   >   where
--   >     sql = "SELECT status FROM dbos.workflow_status WHERE workflow_uuid = $1"
--   >     encoder = Encoders.param (Encoders.nonNullable IsScalar.encoder @WorkflowId)
--   >     decoder = Decoders.rowMaybe (Decoders.column (Decoders.nonNullable IsScalar.encoder @WorkflowStatusString))
--
-- For composite row types (queries that SELECT multiple columns), use
-- Encoders.foldRow / Decoders.rowList with per-column decoders rather than
-- a Row typeclass. Hasql's design favors explicit composition over
-- typeclass-derived rows — which is actually cleaner for our use case since
-- our domain types rarely map 1:1 to a single table.

import Hasql.PostgresqlTypes ()

instance IsScalar.IsScalar WorkflowId where
  encoder = contramap unWorkflowId (IsScalar.encoder @Pt.Text)
  decoder = fmap WorkflowId (IsScalar.decoder @Pt.Text)

instance IsScalar.IsScalar QueueName where
  encoder = contramap unQueueName (IsScalar.encoder @Pt.Text)
  decoder = fmap QueueName (IsScalar.decoder @Pt.Text)

instance IsScalar.IsScalar ScheduleName where
  encoder = contramap unScheduleName (IsScalar.encoder @Pt.Text)
  decoder = fmap ScheduleName (IsScalar.decoder @Pt.Text)

instance IsScalar.IsScalar FunctionId where
  encoder = contramap unFunctionId (IsScalar.encoder @Pt.Int4)
  decoder = fmap FunctionId (IsScalar.decoder @Pt.Int4)

instance IsScalar.IsScalar FunctionName where
  encoder = contramap unFunctionName (IsScalar.encoder @Pt.Text)
  decoder = fmap FunctionName (IsScalar.decoder @Pt.Text)

instance IsScalar.IsScalar AppVersion where
  encoder = contramap unAppVersion (IsScalar.encoder @Pt.Text)
  decoder = fmap AppVersion (IsScalar.decoder @Pt.Text)

instance IsScalar.IsScalar ExecutorId where
  encoder = contramap unExecutorId (IsScalar.encoder @Pt.Text)
  decoder = fmap ExecutorId (IsScalar.decoder @Pt.Text)

instance IsScalar.IsScalar ApplicationId where
  encoder = contramap unApplicationId (IsScalar.encoder @Pt.Text)
  decoder = fmap ApplicationId (IsScalar.decoder @Pt.Text)

instance IsScalar.IsScalar ScheduleId where
  encoder = contramap unScheduleId (IsScalar.encoder @Pt.Text)
  decoder = fmap ScheduleId (IsScalar.decoder @Pt.Text)

instance IsScalar.IsScalar DeduplicationId where
  encoder = contramap unDeduplicationId (IsScalar.encoder @Pt.Text)
  decoder = fmap DeduplicationId (IsScalar.decoder @Pt.Text)

instance IsScalar.IsScalar MessageUuid where
  encoder = contramap unMessageUuid (IsScalar.encoder @Pt.Text)
  decoder = fmap MessageUuid (IsScalar.decoder @Pt.Text)

instance IsScalar.IsScalar OwnerXid where
  encoder = contramap unOwnerXid (IsScalar.encoder @Pt.Text)
  decoder = fmap OwnerXid (IsScalar.decoder @Pt.Text)

instance IsScalar.IsScalar SchemaName where
  encoder = contramap unSchemaName (IsScalar.encoder @Pt.Text)
  decoder = fmap SchemaName (IsScalar.decoder @Pt.Text)

instance IsScalar.IsScalar EpochMs where
  encoder = contramap unEpochMs (IsScalar.encoder @Pt.Int8)
  decoder = fmap EpochMs (IsScalar.decoder @Pt.Int8)

instance IsScalar.IsScalar StepIndex where
  encoder = contramap unStepIndex (IsScalar.encoder @Pt.Int4)
  decoder = fmap StepIndex (IsScalar.decoder @Pt.Int4)

-- WorkflowStatusString maps to Pt.Text with manual rendering.
instance IsScalar.IsScalar WorkflowStatusString where
  encoder = contramap renderStatus (IsScalar.encoder @Pt.Text)
    where
      renderStatus = \case
        StatusPending                    -> "PENDING"
        StatusSuccess                    -> "SUCCESS"
        StatusError                      -> "ERROR"
        StatusMaxRecoveryAttemptsExceeded -> "MAX_RECOVERY_ATTEMPTS_EXCEEDED"
        StatusCancelled                  -> "CANCELLED"
        StatusEnqueued                   -> "ENQUEUED"
        StatusDelayed                    -> "DELAYED"
  decoder = fmap parseStatus (IsScalar.decoder @Pt.Text)
    where
      parseStatus = \case
        "PENDING"                        -> StatusPending
        "SUCCESS"                        -> StatusSuccess
        "ERROR"                          -> StatusError
        "MAX_RECOVERY_ATTEMPTS_EXCEEDED"  -> StatusMaxRecoveryAttemptsExceeded
        "CANCELLED"                      -> StatusCancelled
        "ENQUEUED"                       -> StatusEnqueued
        "DELAYED"                        -> StatusDelayed
        other                            -> error $ "unknown WorkflowStatusString: " <> other
