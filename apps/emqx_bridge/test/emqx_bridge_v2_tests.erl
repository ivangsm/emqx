%%--------------------------------------------------------------------
%% Copyright (c) 2023 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------
-module(emqx_bridge_v2_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("hocon/include/hoconsc.hrl").

%%------------------------------------------------------------------------------
%% Helper fns
%%------------------------------------------------------------------------------

non_deprecated_fields(Fields) ->
    [K || {K, Schema} <- Fields, not hocon_schema:is_deprecated(Schema)].

find_resource_opts_fields(SchemaMod, FieldName) ->
    Fields = hocon_schema:fields(SchemaMod, FieldName),
    case lists:keyfind(resource_opts, 1, Fields) of
        false ->
            undefined;
        {resource_opts, ROSc} ->
            get_resource_opts_subfields(ROSc)
    end.

get_resource_opts_subfields(Sc) ->
    ?R_REF(SchemaModRO, FieldNameRO) = hocon_schema:field_schema(Sc, type),
    ROFields = non_deprecated_fields(hocon_schema:fields(SchemaModRO, FieldNameRO)),
    proplists:get_keys(ROFields).

%%------------------------------------------------------------------------------
%% Testcases
%%------------------------------------------------------------------------------

resource_opts_union_connector_actions_test() ->
    %% The purpose of this test is to ensure we have split `resource_opts' fields
    %% consciouly between connector and actions, in particular when/if we introduce new
    %% fields there.
    AllROFields = non_deprecated_fields(emqx_resource_schema:create_opts([])),
    ActionROFields = non_deprecated_fields(emqx_bridge_v2_schema:resource_opts_fields()),
    ConnectorROFields = non_deprecated_fields(emqx_connector_schema:resource_opts_fields()),
    UnionROFields = lists:usort(ConnectorROFields ++ ActionROFields),
    ?assertEqual(
        lists:usort(AllROFields),
        UnionROFields,
        #{
            missing_fields => AllROFields -- UnionROFields,
            unexpected_fields => UnionROFields -- AllROFields,
            action_fields => ActionROFields,
            connector_fields => ConnectorROFields
        }
    ),
    ok.

connector_resource_opts_test() ->
    %% The purpose of this test is to ensure that all connectors have the `resource_opts'
    %% field with at least some sub-fields that should always be present.
    %% These are used by `emqx_resource_manager' itself to manage the resource lifecycle.
    MinimumROFields = [
        health_check_interval,
        query_mode,
        start_after_created,
        start_timeout
    ],
    ConnectorSchemasRefs =
        lists:map(
            fun({Type, #{type := ?MAP(_, ?R_REF(SchemaMod, FieldName))}}) ->
                {Type, find_resource_opts_fields(SchemaMod, FieldName)}
            end,
            emqx_connector_schema:fields(connectors)
        ),
    ConnectorsMissingRO = [Type || {Type, undefined} <- ConnectorSchemasRefs],
    ConnectorsMissingROSubfields =
        lists:filtermap(
            fun
                ({_Type, undefined}) ->
                    false;
                ({Type, Fs}) ->
                    case MinimumROFields -- Fs of
                        [] ->
                            false;
                        MissingFields ->
                            {true, {Type, MissingFields}}
                    end
            end,
            ConnectorSchemasRefs
        ),
    ?assertEqual(
        #{
            missing_resource_opts_field => #{},
            missing_subfields => #{}
        },
        #{
            missing_resource_opts_field => maps:from_keys(ConnectorsMissingRO, true),
            missing_subfields => maps:from_list(ConnectorsMissingROSubfields)
        }
    ),
    ok.
