%% @doc Smart contract registry records (P5-S3 TASK-083).

-record(contract_definition, {
    contract_id      :: binary(),
    name             :: binary(),
    domain           :: binary(),
    owner_role       :: binary(),
    status           :: active | inactive | deprecated,
    active_version   :: binary() | undefined,
    created_at       :: non_neg_integer(),
    updated_at       :: non_neg_integer()
}).

-record(contract_version, {
    version_id       :: binary(),
    contract_id      :: binary(),
    version          :: binary(),
    dsl_version      :: binary(),
    status           :: draft | active | deprecated,
    contract_payload :: map(),
    checksum         :: binary(),
    created_by       :: binary() | undefined,
    created_at       :: non_neg_integer(),
    updated_at       :: non_neg_integer(),
    migration_from   :: binary() | undefined
}).

-record(contract_migration, {
    migration_id     :: binary(),
    contract_id      :: binary(),
    from_version     :: binary(),
    to_version       :: binary(),
    strategy         :: compatible | transform | manual,
    notes            :: binary() | undefined,
    created_by       :: binary() | undefined,
    created_at       :: non_neg_integer()
}).

-record(contract_experiment, {
    experiment_id     :: binary(),
    contract_id       :: binary(),
    name              :: binary(),
    status            :: draft | active | stopped,
    variants          :: [map()],
    allocation_seed   :: binary(),
    created_by        :: binary() | undefined,
    created_at        :: non_neg_integer(),
    updated_at        :: non_neg_integer()
}).

-record(contract_execution_trace, {
    execution_id      :: binary(),
    contract_id       :: binary() | undefined,
    contract_version  :: binary() | undefined,
    request_id        :: term(),
    input_hash        :: binary(),
    decision_hash     :: binary() | undefined,
    result            :: running | ok | error,
    reason            :: atom() | undefined,
    started_at_us     :: non_neg_integer(),
    finished_at_us    :: non_neg_integer() | undefined,
    duration_us       :: non_neg_integer() | undefined,
    context_snapshot  :: map(),
    decision_snapshot :: map() | undefined,
    trace_payload     :: map(),
    created_at        :: non_neg_integer()
}).
