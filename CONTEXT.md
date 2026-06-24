# DBOS Client — Haskell Port

A standalone client library that connects to a DBOS system database and manages
workflow executions, queues, schedules, messages, events, and streams without
running a DBOS executor.

## Language

**WorkflowFunction**:
The definition of a workflow — its name, class name, and serialization config.
A pure value with no identity or lifecycle.
_Avoid_: Workflow, workflow definition

**WorkflowExecution**:
A single instance of a workflow run. Has a UUID identity, a lifecycle
status, timestamps, inputs, outputs, and parent/fork relationships. At rest,
it is a row in the `workflow_status` table.
_Avoid_: Workflow, workflow instance

**WorkflowHandle**:
A cursor that references a WorkflowExecution by ID and exposes
`getResult`/`getStatus` via polling. Not a distinct domain entity — just an
access pattern.
_Avoid_: Workflow, workflow reference

**WorkflowStatusString**:
The lifecycle of a WorkflowExecution. `ENQUEUED` → `PENDING` → `SUCCESS`
(or `ERROR`/`CANCELLED`). `DELAYED` and `MAX_RECOVERY_ATTEMPTS_EXCEEDED`
are terminal variants.
_Avoid_: Status, state, workflow state

**Queue**:
A named scheduling policy that governs how WorkflowExecutions are dispatched.
Concurrency caps, rate limits, priority, partitioning, and polling intervals.
It is configuration stored in the `queues` table; WorkflowExecutions reference
it by `queueName`, they are not "inside" it.
_Avoid_: Queue (as in FIFO data structure), work queue, job queue

**Enqueue**:
The act of inserting a WorkflowExecution row with status `ENQUEUED`.
The execution is submitted but unclaimed — no worker has picked it up yet.
_Avoid_: Send, submit, schedule

**Schedule**:
A cron expression + WorkflowFunction + config that periodically creates new
WorkflowExecution records. A recurring execution factory, not an execution itself.
_Avoid_: Cron, timer, scheduler

**Fork**:
Create a new WorkflowExecution that starts from a checkpoint taken from an
existing execution at a given step index. The original is marked
`wasForkedFrom = True`. The fork inherits all operation checkpoints, event
history, and streams up to the checkpoint step.
_Avoid_: Branch, clone, copy

**Notification**:
A one-shot push message sent from an external caller to a WorkflowExecution.
Delivery is at-least-once via idempotency key (`messageUuid`). Stored in the
`notifications` table.
_Avoid_: Message, event, signal

**Event**:
A key-value pair set by a WorkflowExecution and read by external callers.
Only the latest value per key is preserved. Stored in the `workflow_events`
table.
_Avoid_: Notification, output, state

**Stream**:
An ordered append-only log of values written by a WorkflowExecution and read
by external callers by offset. Stored in the `streams` table.
_Avoid_: Channel, pipe, log

**Step**:
A single function execution within a WorkflowExecution, recorded in
`operation_outputs` for exactly-once replay. Identified by `functionId` within
the execution.
_Await_: Operation, checkpoint, function execution

**DBOSClientConfig**:
Construction parameters for a DBOSClient — database URLs, pool size, schema
name, serializer. Does not require any DBOS executor or runtime.
_Avoid_: DBOSConfig, config

**WorkflowSerializationFormat**:
The serialization strategy for workflow inputs, outputs, and errors.
`Portable` (JSON) is interoperable across languages; `Native` (pickle) is
Python-only.
_Avoid_: Serialization type, format
