%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Christopher S. Meiklejohn.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(lasp_simple_server).
-author("Vitor Enes Duarte<vitorenesduarte@gmail.com>").

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-include("lasp.hrl").

-record(state, {}).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Start and link to calling process.
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link(?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @private
-spec init([term()]) -> {ok, #state{}}.
init([]) ->
    lager:info("Simple server initialized."),

    %% Delay for graph connectedness.
    wait_for_connectedness(),
    lasp_instrumentation:experiment_started(),

    %% Track whether simulation has ended or not.
    lasp_config:set(simulation_end, false),

    %% Schedule logging.
    schedule_logging(),

    %% Build DAG.
    ok = build_dag(),

    %% Create instance for simulation status tracking
    {Id, Type} = ?SIM_STATUS_ID,
    {ok, _} = lasp:declare(Id, Type),

    %% Schedule check simulation end
    schedule_check_simulation_end(),

    {ok, #state{}}.

%% @private
-spec handle_call(term(), {pid(), term()}, #state{}) ->
    {reply, term(), #state{}}.
handle_call(Msg, _From, State) ->
    lager:warning("Unhandled messages: ~p", [Msg]),
    {reply, ok, State}.

%% @private
-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
handle_cast(Msg, State) ->
    lager:warning("Unhandled messages: ~p", [Msg]),
    {noreply, State}.

%% @private
-spec handle_info(term(), #state{}) -> {noreply, #state{}}.
handle_info(log, #state{}=State) ->
    lasp_marathon_simulations:log_message_queue_size("log"),

    {ok, Bag} = lasp:query(?SIMPLE_BAG),

    lager:info("Bag size: ~p", [sets:size(Bag)]),
    schedule_logging(),

    {noreply, State};

handle_info(check_simulation_end, #state{}=State) ->
    lasp_marathon_simulations:log_message_queue_size("check_simulation_end"),

    {ok, AdsDisabledAndLogs} = lasp:query(?SIM_STATUS_ID),

    NodesWithLogsPushed = lists:filter(
        fun({_Node, {_AdsDisabled, LogsPushed}}) ->
            LogsPushed
        end,
        AdsDisabledAndLogs
    ),

    NodesWithAdsDisabled = lists:filter(
        fun({_Node, {AdsDisabled, _LogsPushed}}) ->
            AdsDisabled
        end,
        AdsDisabledAndLogs
    ),

    lager:info("Checking for simulation end: ~p nodes disabled and ~p nodes with logs pushed.",
               [length(NodesWithAdsDisabled), length(NodesWithLogsPushed)]),

    case length(NodesWithLogsPushed) == client_number() of
        true ->
            lager:info("All nodes have pushed their logs"),
            log_overcounting_and_convergence(),
            lasp_instrumentation:stop(),
            lasp_support:push_logs(),
            lasp_config:set(simulation_end, true),
            stop_simulation();
        false ->
            schedule_check_simulation_end()
    end,

    {noreply, State};

handle_info(Msg, State) ->
    lager:warning("Unhandled messages: ~p", [Msg]),
    {noreply, State}.

%% @private
-spec terminate(term(), #state{}) -> term().
terminate(_Reason, _State) ->
    ok.

%% @private
-spec code_change(term() | {down, term()}, #state{}, term()) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private
build_dag() ->
    {Id, Type} = ?SIMPLE_BAG,
    {ok, _} = lasp:declare(Id, Type),
    ok.

%% @private
schedule_logging() ->
    timer:send_after(?LOG_INTERVAL, log).

%% @private
schedule_check_simulation_end() ->
    timer:send_after(?STATUS_INTERVAL, check_simulation_end).

%% @private
client_number() ->
    lasp_config:get(client_number, 3).

%% @private
log_overcounting_and_convergence() ->
    case lasp_config:get(instrumentation, false) of
        true ->
            Overcounting = compute_overcounting(),
            lasp_instrumentation:overcounting(Overcounting),
            lasp_instrumentation:convergence();

        false ->
            ok
    end.

%% @private
compute_overcounting() ->
    {ok, Bag} = lasp:query(?SIMPLE_BAG),
    BagElements = sets:size(Bag),
    MaxBagElements = ?MAX_BAG_ELEMENTS,
    Overcounting = (BagElements * 100) / MaxBagElements,
    Overcounting.

%% @private
stop_simulation() ->
    DCOS = os:getenv("DCOS", "false"),

    case list_to_atom(DCOS) of
        false ->
            ok;
        _ ->
            lasp_marathon_simulations:stop()
    end.

%% @private
wait_for_connectedness() ->
    case os:getenv("DCOS", "false") of
        "false" ->
            ok;
        _ ->
            case sprinter:was_connected() of
                {ok, true} ->
                    ok;
                {ok, false} ->
                    timer:sleep(100),
                    wait_for_connectedness()
            end
    end.
