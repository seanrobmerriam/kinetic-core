%% Domain event record — one row per outbox event.
%% Attributes must match the cb_schema event_outbox table_spec exactly.
-record(event_outbox, {
    event_id     :: binary(),
    event_type   :: binary(),
    payload      :: map(),
    status       :: pending | delivered | failed,
    created_at   :: integer(),
    updated_at   :: integer()
}).

%% Webhook subscription — one row per registered callback.
%% Attributes must match the cb_schema webhook_subscription table_spec exactly.
-record(webhook_subscription, {
    subscription_id :: binary(),
    event_type      :: binary(),   %% specific event type or <<"*">> for all
    callback_url    :: binary(),
    status          :: active | inactive,
    hmac_secret     :: binary(),
    created_at      :: integer(),
    updated_at      :: integer()
}).

%% Webhook delivery attempt — one row per (event, subscription) delivery attempt.
%% Attributes must match the cb_schema webhook_delivery table_spec exactly.
-record(webhook_delivery, {
    delivery_id     :: binary(),
    subscription_id :: binary(),
    event_id        :: binary(),
    attempt_status  :: pending | delivered | failed | dead_letter,
    response_code   :: integer() | undefined,
    created_at      :: integer(),
    updated_at      :: integer()
}).
