-ifndef(CB_INSIGHTS_HRL).
-define(CB_INSIGHTS_HRL, true).

%% Note: cb_ledger.hrl provides shared types (uuid, timestamp_ms).
%% Callers including this header must also include cb_ledger.hrl
%% before this file (or include cb_ledger.hrl on their own).

%% =========================================================================
%% TASK-078 — Conversational Query Gateway
%% =========================================================================

-type nl_intent() ::
        list_segments
      | list_pending_recommendations
      | list_recent_predictions
      | list_drift_alerts
      | feature_latest
      | unknown.

-type nl_status() :: parsed | executed | failed.

-record(nl_query, {
    query_id    :: uuid(),
    submitted_by :: binary(),
    raw_text    :: binary(),
    intent      :: nl_intent(),
    params      :: #{atom() => term()},
    status      :: nl_status(),
    result      :: term() | undefined,
    error       :: undefined | binary(),
    created_at  :: timestamp_ms(),
    updated_at  :: timestamp_ms()
}).

%% =========================================================================
%% TASK-079 — Governed Insight Generation
%% =========================================================================

-type insight_role() :: analyst | operator | risk_officer | admin.

-type insight_kind() ::
        segment_overview
      | recommendation_summary
      | churn_summary
      | drift_summary.

-type sensitivity() :: public | restricted | confidential.

-record(insight, {
    insight_id   :: uuid(),
    kind         :: insight_kind(),
    sensitivity  :: sensitivity(),
    payload      :: map(),
    generated_by :: binary(),
    audience     :: [insight_role()],
    created_at   :: timestamp_ms()
}).

-record(insight_access_log, {
    access_id   :: uuid(),
    insight_id  :: uuid(),
    accessor    :: binary(),
    role        :: insight_role(),
    decision    :: granted | denied,
    reason      :: undefined | atom(),
    accessed_at :: timestamp_ms()
}).

%% =========================================================================
%% TASK-080 — BYOK Encryption Path
%% =========================================================================

-type byok_status() :: pending | active | rotated | revoked.

-record(byok_key, {
    key_id           :: uuid(),
    owner            :: binary(),
    algorithm        :: binary(),
    %% AES-256-GCM key material wrapped with the platform master KEK
    wrapped_material :: binary(),
    iv               :: binary(),
    status           :: byok_status(),
    created_at       :: timestamp_ms(),
    rotated_at       :: timestamp_ms() | undefined,
    revoked_at       :: timestamp_ms() | undefined
}).

-record(byok_access_log, {
    access_id   :: uuid(),
    key_id      :: uuid(),
    accessor    :: binary(),
    purpose     :: binary(),
    operation   :: encrypt | decrypt | rotate | revoke,
    decision    :: granted | denied,
    reason      :: undefined | atom(),
    accessed_at :: timestamp_ms()
}).

-endif.
