// main template for rabbitmq-operator
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.rabbitmq_operator;

local clusterBasePath = 'rabbitmq-cluster-operator/manifests/operator/' + params.manifest_version + '/cluster-operator.yml';
local clusterAltPath = 'dependencies/rabbitmq-cluster-operator/manifests/operator/' + params.manifest_version + '/cluster-operator.yml';
local clusterManifestPath = if kap.file_exists(clusterBasePath).exists then clusterBasePath else clusterAltPath;

local mtoBasePath = 'rabbitmq-messaging-topology-operator/manifests/operator/' + params.messaging_topology_manifest_version + '/messaging-topology-operator.yaml';
local mtoAltPath = 'dependencies/rabbitmq-messaging-topology-operator/manifests/operator/' + params.messaging_topology_manifest_version + '/messaging-topology-operator.yaml';
local mtoManifestPath = if kap.file_exists(mtoBasePath).exists then mtoBasePath else mtoAltPath;

local manifests = std.parseJson(kap.yaml_load_stream(clusterManifestPath)) + std.parseJson(kap.yaml_load_stream(mtoManifestPath));
local filtered = std.filter(function(o) o != null && o.kind != 'Namespace', manifests);
local isClusterScoped(kind) = std.member([ 'CustomResourceDefinition', 'ClusterRole', 'ClusterRoleBinding', 'MutatingWebhookConfiguration', 'ValidatingWebhookConfiguration' ], kind);
local isWebhook(kind) = std.member([ 'MutatingWebhookConfiguration', 'ValidatingWebhookConfiguration' ], kind);
local patchNS(o) =
  local base = if isClusterScoped(o.kind) then o else o { metadata+: { namespace: params.namespace } };
  if std.objectHas(base, 'subjects') then
    base { subjects: [ s { namespace: params.namespace } for s in base.subjects ] }
  else
    base;
local patchWebhooks(o) =
  if isWebhook(o.kind) then
    o {
      webhooks: [ w { clientConfig+: { service+: { namespace: params.namespace } } } for w in o.webhooks ],
      metadata+: {
        annotations+: {
          'cert-manager.io/inject-ca-from': params.namespace + '/' + std.split(o.metadata.annotations['cert-manager.io/inject-ca-from'], '/')[1],
        },
      },
    }
  else
    o;
local patchCertificates(o) =
  if o.kind == 'Certificate' then
    local srcNS = o.metadata.namespace;
    o { spec+: { dnsNames: [ std.strReplace(d, srcNS, params.namespace) for d in o.spec.dnsNames ] } }
  else
    o;
local objects = [ patchNS(patchWebhooks(patchCertificates(o))) for o in filtered ];

{
  '00_namespace': kube.Namespace(params.namespace),
}
+ std.foldl(
  function(acc, obj) acc { ['10_' + std.asciiLower(obj.kind)]+: [ obj ] },
  objects,
  {}
)
