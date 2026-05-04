%%%-------------------------------------------------------------------
%% @doc Analytics platform records and types (P5-S1).
%%
%% Covers the four analytics workstreams:
%%   - Feature store with governed pipelines (TASK-074)
%%   - Customer segmentation and product recommendations (TASK-075)
%%   - Churn and anomaly prediction with confidence (TASK-076)
%%   - Model monitoring, drift detection, and retraining triggers (TASK-077)
%%
%% Money is never represented here directly; analytics references entities
%% by uuid() and reads monetary values from the ledger as needed.
%%%-------------------------------------------------------------------

-ifndef(CB_ANALYTICS_HRL).
-define(CB_ANALYTICS_HRL, true).

%% Note: cb_ledger.hrl provides shared types (uuid, timestamp_ms).
%% Callers including this header must also include cb_ledger.hrl
%% before this file (or include cb_ledger.hrl on their own).

%%====================================================================
%% Types
%%====================================================================

%% TASK-074
-type feature_value_type() :: numeric | categorical | boolean | timestamp.
-type pipeline_status()    :: registered | active | retired.

%% TASK-075
-type segment_status()         :: active | retired.
-type recommendation_status()  :: pending | delivered | dismissed | accepted.

%% TASK-076
-type prediction_kind()    :: churn | anomaly.
-type confidence_band()    :: low | medium | high.

%% TASK-077
-type monitor_status()     :: healthy | warning | drifting.
-type drift_severity()     :: info | warning | critical.
-type trigger_status()     :: pending | acknowledged | completed.

%%====================================================================
%% TASK-074: Feature Store + Governed Pipelines
%%====================================================================

%% @doc Definition of a single feature exposed by the feature store.
%%
%% feature_key is a stable string identifier (e.g. <<"party.balance_30d_avg">>).
%% pipeline_id groups features produced by the same governed pipeline.
%% value_type controls how feature values are interpreted at read time.
-record(feature_definition, {
    feature_id   :: uuid(),
    feature_key  :: binary(),
    pipeline_id  :: uuid(),
    description  :: binary(),
    value_type   :: feature_value_type(),
    owner        :: binary(),
    created_at   :: timestamp_ms(),
    updated_at   :: timestamp_ms()
}).

%% @doc A computed feature value for a specific entity at a point in time.
%%
%% entity_id is typically a party_id or account_id.
%% value is stored as a binary so callers can encode any feature_value_type().
-record(feature_value, {
    value_id      :: uuid(),
    feature_key   :: binary(),
    entity_id     :: uuid(),
    value         :: binary(),
    computed_at   :: timestamp_ms()
}).

%% @doc A governed data pipeline that materializes features.
%%
%% schedule_ms is the period between scheduled runs (informational; the
%% scheduler itself is out of scope for this phase).
-record(feature_pipeline, {
    pipeline_id   :: uuid(),
    name          :: binary(),
    description   :: binary(),
    schedule_ms   :: pos_integer(),
    status        :: pipeline_status(),
    last_run_at   :: timestamp_ms() | undefined,
    created_at    :: timestamp_ms()
}).

%%====================================================================
%% TASK-075: Segmentation + Recommendations
%%====================================================================

%% @doc Definition of a customer segment.
%%
%% rule is a free-form descriptor (e.g. <<"balance>=10000 AND tenure_days>=180">>).
%% Evaluation is performed by the calling rule engine at assignment time.
-record(customer_segment, {
    segment_id   :: uuid(),
    name         :: binary(),
    description  :: binary(),
    rule         :: binary(),
    status       :: segment_status(),
    created_at   :: timestamp_ms(),
    updated_at   :: timestamp_ms()
}).

%% @doc Membership of a party in a segment.
-record(segment_membership, {
    membership_id :: uuid(),
    segment_id    :: uuid(),
    party_id      :: uuid(),
    assigned_at   :: timestamp_ms()
}).

%% @doc A product recommendation for a party.
%%
%% rationale captures why the recommendation was produced so it can be
%% surfaced in compliance reviews.
-record(product_recommendation, {
    recommendation_id :: uuid(),
    party_id          :: uuid(),
    product_code      :: binary(),
    score             :: float(),
    rationale         :: binary(),
    status            :: recommendation_status(),
    created_at        :: timestamp_ms(),
    updated_at        :: timestamp_ms()
}).

%%====================================================================
%% TASK-076: Predictions
%%====================================================================

%% @doc A scored prediction (churn or anomaly) for an entity.
%%
%% score is in the range [0.0, 1.0]. confidence is in the same range and
%% derived from feature coverage; band collapses confidence into a coarse
%% bucket suitable for downstream UIs.
-record(prediction_score, {
    prediction_id  :: uuid(),
    kind           :: prediction_kind(),
    entity_id      :: uuid(),
    score          :: float(),
    confidence     :: float(),
    confidence_band :: confidence_band(),
    features_used  :: [binary()],
    computed_at    :: timestamp_ms()
}).

%%====================================================================
%% TASK-077: Model Monitoring + Drift
%%====================================================================

%% @doc A registered monitor for a deployed model.
%%
%% baseline_mean / baseline_stddev describe the reference distribution that
%% live samples are compared against using a population-stability-style
%% drift score.
-record(model_monitor, {
    monitor_id        :: uuid(),
    model_name        :: binary(),
    feature_key       :: binary(),
    baseline_mean     :: float(),
    baseline_stddev   :: float(),
    drift_threshold   :: float(),
    status            :: monitor_status(),
    created_at        :: timestamp_ms(),
    updated_at        :: timestamp_ms()
}).

%% @doc A drift alert raised when an observed sample exceeds the threshold.
-record(drift_alert, {
    alert_id        :: uuid(),
    monitor_id      :: uuid(),
    drift_score     :: float(),
    severity        :: drift_severity(),
    observed_mean   :: float(),
    sample_size     :: non_neg_integer(),
    detected_at     :: timestamp_ms()
}).

%% @doc A retraining trigger raised in response to one or more drift alerts.
-record(retraining_trigger, {
    trigger_id      :: uuid(),
    model_name      :: binary(),
    reason          :: binary(),
    alert_ids       :: [uuid()],
    status          :: trigger_status(),
    created_at      :: timestamp_ms(),
    updated_at      :: timestamp_ms()
}).

-endif.
