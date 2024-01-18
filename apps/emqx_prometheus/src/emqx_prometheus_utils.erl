%%--------------------------------------------------------------------
%% Copyright (c) 2024 EMQ Technologies Co., Ltd. All Rights Reserved.
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
-module(emqx_prometheus_utils).

-export([
    collect_json_data/2,

    aggre_cluster/3,
    with_node_name_label/2,

    point_to_map_fun/1,

    boolean_to_number/1,
    status_to_number/1,
    metric_names/1
]).

-define(MG(K, MAP), maps:get(K, MAP)).
-define(PG0(K, PROPLISTS), proplists:get_value(K, PROPLISTS, 0)).

collect_json_data(Data, Func) when is_function(Func, 3) ->
    maps:fold(
        fun(K, V, Acc) ->
            Func(K, V, Acc)
        end,
        [],
        Data
    );
collect_json_data(_, _) ->
    error(badarg).

aggre_cluster(LogicSumKs, ResL, Init) ->
    do_aggre_cluster(LogicSumKs, ResL, Init).

do_aggre_cluster(_LogicSumKs, [], AccIn) ->
    AccIn;
do_aggre_cluster(LogicSumKs, [{ok, {_NodeName, NodeMetric}} | Rest], AccIn) ->
    do_aggre_cluster(
        LogicSumKs,
        Rest,
        maps:fold(
            fun(K, V, AccIn0) ->
                AccIn0#{K => aggre_metric(LogicSumKs, V, ?MG(K, AccIn0))}
            end,
            AccIn,
            NodeMetric
        )
        %% merge_node_and_acc()
    );
do_aggre_cluster(LogicSumKs, [{_, _} | Rest], AccIn) ->
    do_aggre_cluster(LogicSumKs, Rest, AccIn).

aggre_metric(LogicSumKs, NodeMetrics, AccIn0) ->
    lists:foldl(
        fun(K, AccIn) ->
            NAccL = do_aggre_metric(
                K, LogicSumKs, ?MG(K, NodeMetrics), ?MG(K, AccIn)
            ),
            AccIn#{K => NAccL}
        end,
        AccIn0,
        maps:keys(NodeMetrics)
    ).

do_aggre_metric(K, LogicSumKs, NodeMetrics, AccL) ->
    lists:foldl(
        fun({Labels, Metric}, AccIn) ->
            NMetric =
                case lists:member(K, LogicSumKs) of
                    true ->
                        logic_sum(Metric, ?PG0(Labels, AccIn));
                    false ->
                        Metric + ?PG0(Labels, AccIn)
                end,
            [{Labels, NMetric} | AccIn]
        end,
        AccL,
        NodeMetrics
    ).

with_node_name_label(ResL, Init) ->
    do_with_node_name_label(ResL, Init).

do_with_node_name_label([], AccIn) ->
    AccIn;
do_with_node_name_label([{ok, {NodeName, NodeMetric}} | Rest], AccIn) ->
    do_with_node_name_label(
        Rest,
        maps:fold(
            fun(K, V, AccIn0) ->
                AccIn0#{
                    K => zip_with_node_name(NodeName, V, ?MG(K, AccIn0))
                }
            end,
            AccIn,
            NodeMetric
        )
    );
do_with_node_name_label([{_, _} | Rest], AccIn) ->
    do_with_node_name_label(Rest, AccIn).

zip_with_node_name(NodeName, NodeMetrics, AccIn0) ->
    lists:foldl(
        fun(K, AccIn) ->
            NAccL = do_zip_with_node_name(NodeName, ?MG(K, NodeMetrics), ?MG(K, AccIn)),
            AccIn#{K => NAccL}
        end,
        AccIn0,
        maps:keys(NodeMetrics)
    ).

do_zip_with_node_name(NodeName, NodeMetrics, AccL) ->
    lists:foldl(
        fun({Labels, Metric}, AccIn) ->
            NLabels = [{node, NodeName} | Labels],
            [{NLabels, Metric} | AccIn]
        end,
        AccL,
        NodeMetrics
    ).

point_to_map_fun(Key) ->
    fun({Lables, Metric}, AccIn2) ->
        LablesKVMap = maps:from_list(Lables),
        [maps:merge(LablesKVMap, #{Key => Metric}) | AccIn2]
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

logic_sum(N1, N2) when
    (N1 > 0 andalso N2 > 0)
->
    1;
logic_sum(_, _) ->
    0.

boolean_to_number(true) -> 1;
boolean_to_number(false) -> 0.

status_to_number(connected) -> 1;
%% for auth
status_to_number(stopped) -> 0;
%% for data_integration
status_to_number(disconnected) -> 0.

metric_names(MetricWithType) when is_list(MetricWithType) ->
    [Name || {Name, _Type} <- MetricWithType].
