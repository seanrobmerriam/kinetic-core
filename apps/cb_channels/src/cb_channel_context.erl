-module(cb_channel_context).

-include("../../cb_ledger/include/cb_ledger.hrl").

-export([
    get_context/2
]).

-spec get_context(uuid(), channel_type()) -> {ok, map()} | {error, not_found}.
get_context(PartyId, Channel) ->
    case mnesia:dirty_read(party, PartyId) of
        [] ->
            {error, not_found};
        [Party] ->
            Accounts = mnesia:dirty_index_read(account, PartyId, party_id),
            Sessions = [S || S <- mnesia:dirty_index_read(channel_session, PartyId, party_id),
                             S#channel_session.channel =:= Channel,
                             S#channel_session.status =:= active],
            Prefs = mnesia:dirty_index_read(notification_preference, PartyId, party_id),
            Limits = mnesia:dirty_match_object(
                channel_limit,
                #channel_limit{limit_key = {Channel, '_'}, daily_limit = '_',
                               per_txn_limit = '_', updated_at = '_'}
            ),
            Context = #{
                party_id => PartyId,
                channel => Channel,
                party => party_to_map(Party),
                accounts => [account_to_map(A) || A <- Accounts],
                active_sessions => length(Sessions),
                notification_prefs => [pref_to_map(P) || P <- Prefs],
                limits => [limits_to_map(L) || L <- Limits]
            },
            {ok, Context}
    end.

party_to_map(#party{party_id = Id, full_name = Name, status = Status, email = Email}) ->
    #{party_id => Id, full_name => Name, status => Status, email => Email}.

account_to_map(#account{account_id = Id, currency = Cur, balance = Bal, status = Status}) ->
    #{account_id => Id, currency => Cur, balance => Bal, status => Status}.

pref_to_map(#notification_preference{channel = Ch, event_types = ETs, enabled = En}) ->
    #{channel => Ch, event_types => ETs, enabled => En}.

limits_to_map(#channel_limit{limit_key = {_Ch, Cur}, daily_limit = D, per_txn_limit = T}) ->
    #{currency => Cur, daily_limit => D, per_txn_limit => T}.

