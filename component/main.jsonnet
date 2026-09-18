// main template for rabbitmq-operator
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rabbitmq_operator;

local basePath = 'rabbitmq-cluster-operator/manifests/operator/' + params.manifest_version + '/cluster-operator.yml';
local altPath = 'dependencies/rabbitmq-cluster-operator/manifests/operator/' + params.manifest_version + '/cluster-operator.yml';
local manifestPath = if kap.file_exists(basePath).exists then basePath else altPath;
local manifests = std.parseJson(kap.yaml_load_stream(manifestPath));
local filtered = std.filter(function(o) o != null && o.kind != 'Namespace', manifests);
local isClusterScoped(kind) = std.member([ 'CustomResourceDefinition', 'ClusterRole', 'ClusterRoleBinding' ], kind);
local patchNS(o) =
  local base = if isClusterScoped(o.kind) then o else o { metadata+: { namespace: params.namespace } };
  if std.objectHas(base, 'subjects') then
    base { subjects: [ s { namespace: params.namespace } for s in base.subjects ] }
  else
    base;
local objects = [ patchNS(o) for o in filtered ];

{
  '00_namespace': kube.Namespace(params.namespace),
}
+ std.foldl(
  function(acc, obj) acc { ['10_' + std.asciiLower(obj.kind)]+: [ obj ] },
  objects,
  {}
)
