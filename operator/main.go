package main

// aitrust-operator — ONE operator image, mode-driven by FEDERATION_MODE:
//
//   FEDERATION_MODE=local (default) — SINGLE-CLUSTER provider. Platform Mesh + app + tenants on one
//     cluster. Watches sub.aitrust.msp Subscriptions and provisions each ORG as a tenant IN-CLUSTER
//     (r.remote == r.Client). No fed- prefix; realm gate = direct HTTP to the in-cluster mesh Keycloak;
//     no cross-Keycloak broker / reciprocal SSO. This is the stock single-cluster behaviour.
//
//   FEDERATION_MODE=federated — CENTRAL marketplace cluster. Watches sub.aitrust.remote Subscriptions
//     (published into the Central kcp ws root:providers:ai-trust-remote by the bundled sync-agent) and
//     provisions each ORG as a tenant ON THE PAYLOAD CLUSTER via a mounted scoped SA kubeconfig
//     (r.remote = REMOTE_KUBECONFIG). Federated tenants are namespaced `fed-<org>` on the payload cluster
//     (schema tenant_fed_<org>, CH db tenant_fed_<org>, bucket tenant-fed-<org>, role t_fed_<org>, host
//     ai-trust-fed-<org>.<payload-suffix>) so they never collide with the payload's native tenants. Realm
//     gate = trust the broker Job's success (the payload mesh Keycloak isn't reachable by HTTP from
//     Central); ALSO wires cross-Keycloak SSO (payload realm fed-<org> brokers the Central <org> realm)
//     + the reciprocal client back in the Central <org> realm.
//
// TWO-CLIENT split (both modes): r.Client = the cluster we watch Subscriptions on + write status;
// r.remote = where provisioning happens (== r.Client in local mode; the payload SA client in federated).
// Tenant DATA is never deleted. ONE image, one codebase; deploy it once per role (local: on the single
// cluster; federated: on the Central cluster).

import (
	"embed"
	"fmt"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/tools/clientcmd"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	"sigs.k8s.io/controller-runtime/pkg/manager/signals"
)

//go:embed manifests/*.tmpl
var manifestFS embed.FS

// These are set once at startup from FEDERATION_MODE (see main()). local → sub.aitrust.msp, no prefix;
// federated → sub.aitrust.remote, `fed-` prefix.
var (
	gvk           = schema.GroupVersionKind{Group: "sub.aitrust.msp", Version: "v1alpha1", Kind: "Subscription"}
	finalizer     = "subscription.sub.aitrust.msp/finalizer"
	fedPrefix     = "" // "" in local mode; "fed-" in federated mode
	remoteCluster = "" // status.cluster: empty in local mode; the payload cluster name in federated mode
)

func main() {
	ctrl.SetLogger(zap.New(zap.UseDevMode(true)))
	c := cfg()

	// Mode-derived globals. local → the stock single-cluster provider (sub.aitrust.msp, no prefix);
	// federated → the Central marketplace controller (sub.aitrust.remote, fed- prefix).
	if c.federated {
		gvk = schema.GroupVersionKind{Group: "sub.aitrust.remote", Version: "v1alpha1", Kind: "Subscription"}
		finalizer = "subscription.sub.aitrust.remote/finalizer"
		fedPrefix = "fed-"
		remoteCluster = env("PAYLOAD_CLUSTER_NAME", "ai-trust-1")
	}

	mgr, err := manager.New(ctrl.GetConfigOrDie(), manager.Options{})
	if err != nil {
		panic(err)
	}

	// TWO-CLIENT split. The manager's own client (r.Client) watches Subscriptions + writes status on the
	// cluster this pod runs in. r.remote is where PROVISIONING happens:
	//   local     → r.remote == r.Client (provision in-cluster — the stock behaviour).
	//   federated → r.remote = a client for the PAYLOAD cluster built from the mounted SA kubeconfig.
	var remoteCli client.Client
	if c.federated {
		remoteCfg, err := clientcmd.BuildConfigFromFlags("", c.remoteKubecfg)
		if err != nil {
			panic(fmt.Errorf("load payload kubeconfig %s: %w", c.remoteKubecfg, err))
		}
		if remoteCli, err = client.New(remoteCfg, client.Options{}); err != nil {
			panic(fmt.Errorf("build payload client: %w", err))
		}
	} else {
		remoteCli = mgr.GetClient()
	}

	proto := &unstructured.Unstructured{}
	proto.SetGroupVersionKind(gvk)
	if err := builder.ControllerManagedBy(mgr).For(proto).Complete(&reconciler{
		Client: mgr.GetClient(), remote: remoteCli, cfg: c,
	}); err != nil {
		panic(err)
	}
	mode := "local"
	remoteDesc := "(in-cluster)"
	if c.federated {
		mode = "federated"
		remoteDesc = c.remoteKubecfg
	}
	log.Log.Info("aitrust-operator starting", "mode", mode, "providerNS", c.providerNS,
		"domainSuffix", c.domainSuffix, "gateway", c.gatewayName, "group", gvk.Group, "remoteKubeconfig", remoteDesc)
	if err := mgr.Start(signals.SetupSignalHandler()); err != nil {
		panic(err)
	}
}
