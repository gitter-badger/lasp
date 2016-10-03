%% -------------------------------------------------------------------
%%
%% Copyright (c) 2016 Christopher Meiklejohn.  All Rights Reserved.
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
%%

-module(ad_counter_SUITE).
-author("Christopher Meiklejohn <christopher.meiklejohn@gmail.com>").

%% common_test callbacks
-export([%% suite/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2,
         all/0]).

%% tests
-compile([export_all]).

-include("lasp.hrl").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/inet.hrl").

%% ===================================================================
%% common_test callbacks
%% ===================================================================

init_per_suite(_Config) ->
    ct:timetrap(infinity),
    _Config.

end_per_suite(_Config) ->
    _Config.

init_per_testcase(Case, _Config) ->
    ct:pal("Beginning test case ~p", [Case]),

    _Config.

end_per_testcase(Case, _Config) ->
    ct:pal("Ending test case ~p", [Case]),

    _Config.

all() ->
    [
     peer_to_peer_test,
     client_server_test
    ].

%% ===================================================================
%% tests
%% ===================================================================

default_test(_Config) ->
    ok.

%% ===================================================================
%% peer-to-peer
%% ===================================================================

peer_to_peer_test(Config) ->
    PP = [0],
    lists:foreach(
      fun(P) ->
        run_it(Config, partisan_hyparview_peer_service_manager, P)
      end,
      PP
    ).

client_server_test(Config) ->
    PP = [0],
    lists:foreach(
      fun(P) ->
        run_it(Config, partisan_client_server_peer_service_manager, P)
      end,
      PP
    ).


run_it(Config, PeerService, PartitionProbability) ->
    CList = [{4000, 4000}, {4000, 8000}, {8000, 4000}],
    ClientList = [2, 4, 6, 8, 12, 16, 20, 24, 32],
    lists:foreach(
        fun({UpdateInterval, SyncInterval}) ->
            lists:foreach(
                fun(ClientNumber) ->
                    lasp_config:set(update_interval, UpdateInterval),
                    lasp_config:set(sync_interval, SyncInterval),
                    lasp_config:set(client_number, ClientNumber),

                    lasp_simulation_support:run(PeerService,
                        Config,
                        [{mode, state_based},
                         {simulation, ad_counter},
                         {partisan_peer_service_manager, PeerService},
                         {set, orset},
                         {broadcast, false},
                         {partition_probability, PartitionProbability},
                         {evaluation_identifier, whatever}]
                    )
                end,
                ClientList
            )
        end,
        CList
    ),
    ok.

