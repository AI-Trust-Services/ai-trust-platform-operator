package main

// aitrust-msp-operator — watches AITrustPlatformInstance CRs and stamps out a FULL copy of the
// AI Trust Platform app (all ~23 workloads + its own postgres/clickhouse/minio/rabbitmq/keycloak)
// into a dedicated namespace per instance. It is a Go port of Standard_Ai_Platform/scripts/3-deploy-app.sh
// + 4-ingress.sh: the embedded manifests (embed.FS) are the SAME gold manifest set, rendered per-CR by
// swapping the namespace, the public URL/domain, a fresh cookie secret, and the image registry/tag.
//
// Isolation model: one full app copy per namespace. Because every in-cluster reference uses short
// service DNS (postgres, keycloak, minio, …) that resolves within-namespace, swapping the namespace
// string is the entire isolation mechanism — dedicated backing stores per instance, no app changes.
//
// Reconcile is idempotent: server-side apply + read-back of the existing secret so a re-reconcile never
// rotates a live DB. A finalizer removes the per-instance HTTPRoutes and deletes the namespace on delete.

import (
	"bytes"
	"context"
	"crypto/rand"
	"embed"
	"encoding/hex"
	"fmt"
	"os"
	"regexp"
	"strings"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	utilyaml "k8s.io/apimachinery/pkg/util/yaml"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	"sigs.k8s.io/controller-runtime/pkg/manager/signals"
)

//go:embed manifests/*.yaml manifests/*.tmpl
var manifestFS embed.FS

var gvk = schema.GroupVersionKind{Group: "trust.aitrust.msp", Version: "v1alpha1", Kind: "AITrustPlatformInstance"}

const finalizer = "aitrustplatforminstance.trust.aitrust.msp/finalizer"

// env-driven config (set on the operator Deployment by the workload chart).
func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func cfg() (domainSuffix, registry, tag, gwNS, gwName, poolLabel string) {
	return env("INSTANCE_DOMAIN_SUFFIX", "ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"),
		env("REGISTRY", "mirceacraciun795"),
		env("TAG", "aitrust-1"),
		env("GATEWAY_NS", "platform-mesh-system"),
		env("GATEWAY_NAME", "k8sapi-gateway"),
		env("MSP_WORKER_LABEL", "msp-aitrust")
}

// the manifest docs to render, in apply order. Jobs are handled specially (node-pinned before apply).
var manifestFiles = []string{
	"00-namespace", "01-cm-ch-config", "01-cm-otelcol", "01-cm-pg-init",
	"10-infra", "30-app", "40-workers-shell-proxy",
}

type reconciler struct{ client.Client }

func (r *reconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	l := log.FromContext(ctx)
	cr := &unstructured.Unstructured{}
	cr.SetGroupVersionKind(gvk)
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	domainSuffix, registry, tag, gwNS, gwName, poolLabel := cfg()

	// per-instance namespace + URL (DNS-safe, unique per consumer namespace + CR name).
	ns := dnsSafe(fmt.Sprintf("aitp-%s-%s", cr.GetNamespace(), cr.GetName()))
	spec, _, _ := unstructured.NestedMap(cr.Object, "spec")
	host := strOr(spec["hostname"], dnsSafe(fmt.Sprintf("%s-%s", cr.GetNamespace(), cr.GetName())))
	if !strings.Contains(host, ".") {
		host = host + "." + domainSuffix
	}
	url := "https://" + host
	if v := strOr(spec["registryOverride"], ""); v != "" {
		registry = v
	}
	if v := strOr(spec["tagOverride"], ""); v != "" {
		tag = v
	}

	// ---- finalizer / delete handling -------------------------------------------------
	if !cr.GetDeletionTimestamp().IsZero() {
		if hasFinalizer(cr) {
			l.Info("deleting instance", "ns", ns, "host", host)
			r.deleteRoutes(ctx, gwNS, ns)
			r.deleteNamespace(ctx, ns)
			removeFinalizer(cr)
			_ = r.Update(ctx, cr)
		}
		return ctrl.Result{}, nil
	}
	if !hasFinalizer(cr) {
		addFinalizer(cr)
		if err := r.Update(ctx, cr); err != nil {
			return ctrl.Result{RequeueAfter: 5 * time.Second}, nil
		}
	}

	// ---- render + apply the manifest set ---------------------------------------------
	// (status is written ONCE at the end — writing mid-reconcile bumps resourceVersion and makes the
	// terminal write conflict.)
	rep := replacer(ns, url, registry, tag, randHex(16))

	// 1) namespace first (so the secret-existence check below can run).
	if err := r.applyMulti(ctx, renderFile(rep, "manifests/00-namespace.yaml")); err != nil {
		return r.fail(ctx, cr, url, ns, "namespace", err)
	}
	// 2) secret/config (from the .tmpl) — apply ONCE. If app-secrets already exists we skip it so a
	//    re-reconcile never rotates the cookie secret / DB creds under a live instance.
	if !secretExists(ctx, r.Client, ns) {
		if err := r.applyDoc(ctx, renderFile(rep, "manifests/02-secret-config.tmpl")); err != nil {
			return r.fail(ctx, cr, url, ns, "secret", err)
		}
	}
	// 3) the ordered manifest files (cms, infra, app, workers) — namespace already applied above.
	for _, f := range manifestFiles {
		if f == "00-namespace" {
			continue
		}
		if err := r.applyMulti(ctx, renderFile(rep, "manifests/"+f+".yaml")); err != nil {
			return r.fail(ctx, cr, url, ns, f, err)
		}
	}
	// 3) Jobs — node-pin each Job podTemplate BEFORE apply (Jobs are immutable), passing APP_URL so the
	//    keycloak-provision Job templates redirect URIs to this instance's host.
	if err := r.applyJobs(ctx, rep, ns, poolLabel, url); err != nil {
		return r.fail(ctx, cr, url, ns, "jobs", err)
	}

	// ---- post-apply patches (verbatim from 3-deploy-app.sh, per-instance url) ---------
	r.pinAll(ctx, ns, poolLabel)
	r.patchKeycloak(ctx, ns, url)
	r.patchOauth2(ctx, ns, url)

	// ---- ingress: one HTTPRoute (+keycloak bypass) + ReferenceGrant per instance ------
	if err := r.wireIngress(ctx, gwNS, gwName, ns, host); err != nil {
		l.Error(err, "ingress wiring failed (will retry)")
		return ctrl.Result{RequeueAfter: 15 * time.Second}, nil
	}

	// ---- status aggregation across all workloads --------------------------------------
	ready, total, avail := r.aggregate(ctx, ns)
	if ready {
		r.setPhase(ctx, cr, "Ready", true, url, ns, fmt.Sprintf("all workloads ready (%d/%d)", avail, total))
		return ctrl.Result{RequeueAfter: 2 * time.Minute}, nil
	}
	r.setPhase(ctx, cr, "Provisioning", false, url, ns, fmt.Sprintf("%d/%d workloads ready", avail, total))
	return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
}

// ---------- rendering ----------------------------------------------------------------

var imgRe = regexp.MustCompile(`image: aitrust/([a-z0-9-]+):kind`)

// replacer builds the sed-equivalent string transform applied to every rendered doc.
func replacer(ns, url, registry, tag, cookie string) func(string) string {
	domain := strings.TrimPrefix(url, "https://")
	return func(s string) string {
		// Swap the app namespace everywhere. The manifests hardcode `ai-trust-app` in both
		// `namespace: ai-trust-app` refs AND the Namespace object's `metadata.name: ai-trust-app`,
		// so a global token replace is required (and safe — that string only ever names the app ns).
		s = strings.ReplaceAll(s, "ai-trust-app", ns)
		s = strings.ReplaceAll(s, "__APP_NS__", ns)
		s = strings.ReplaceAll(s, "__APP_URL__", url)
		s = strings.ReplaceAll(s, "__APP_DOMAIN__", domain)
		s = strings.ReplaceAll(s, "__COOKIE_SECRET__", cookie)
		s = imgRe.ReplaceAllString(s, "image: "+registry+"/aitrust-$1:"+tag)
		return s
	}
}

func renderFile(rep func(string) string, path string) string {
	b, err := manifestFS.ReadFile(path)
	if err != nil {
		return ""
	}
	return rep(string(b))
}

// ---------- apply helpers ------------------------------------------------------------

func (r *reconciler) applyDoc(ctx context.Context, doc string) error { return r.applyMulti(ctx, doc) }

// applyMulti splits a multi-doc YAML string and server-side-applies each object.
func (r *reconciler) applyMulti(ctx context.Context, doc string) error {
	for _, obj := range decodeAll(doc) {
		if obj == nil {
			continue
		}
		if err := r.Patch(ctx, obj, client.Apply, client.ForceOwnership, client.FieldOwner("aitrust-msp-operator")); err != nil {
			return fmt.Errorf("apply %s/%s: %w", obj.GetKind(), obj.GetName(), err)
		}
	}
	return nil
}

// applyJobs renders the Jobs doc, injects nodeSelector+toleration into every Job podTemplate, sets
// APP_URL on the keycloak-provision Job, then applies. (Jobs immutable → must patch before create.)
func (r *reconciler) applyJobs(ctx context.Context, rep func(string) string, ns, poolLabel, url string) error {
	for _, obj := range decodeAll(renderFile(rep, "manifests/20-jobs.yaml")) {
		if obj == nil {
			continue
		}
		if obj.GetKind() == "Job" {
			pinPodSpec(obj, poolLabel)
			setJobEnv(obj, "APP_URL", url)
		}
		// skip if it already exists (Jobs are immutable; a completed Job must not be re-applied)
		existing := obj.DeepCopy()
		if err := r.Get(ctx, types.NamespacedName{Namespace: ns, Name: obj.GetName()}, existing); err == nil {
			continue
		}
		if err := r.Patch(ctx, obj, client.Apply, client.ForceOwnership, client.FieldOwner("aitrust-msp-operator")); err != nil {
			return fmt.Errorf("apply job %s: %w", obj.GetName(), err)
		}
	}
	return nil
}

// ---------- post-apply patches -------------------------------------------------------

func (r *reconciler) pinAll(ctx context.Context, ns, poolLabel string) {
	list := &unstructured.UnstructuredList{}
	list.SetGroupVersionKind(schema.GroupVersionKind{Group: "apps", Version: "v1", Kind: "DeploymentList"})
	if err := r.List(ctx, list, client.InNamespace(ns)); err != nil {
		return
	}
	patch := []byte(fmt.Sprintf(
		`{"spec":{"template":{"spec":{"nodeSelector":{"workload":%q},"tolerations":[{"key":"workload","value":%q,"effect":"NoSchedule"}]}}}}`,
		poolLabel, poolLabel))
	for i := range list.Items {
		d := &list.Items[i]
		_ = r.Patch(ctx, d, client.RawPatch(types.StrategicMergePatchType, patch))
	}
}

func (r *reconciler) patchKeycloak(ctx context.Context, ns, url string) {
	d := deploy(ns, "keycloak")
	// env: KC_HOSTNAME=<url>/keycloak, KC_HOSTNAME_STRICT=false, KC_HTTP_RELATIVE_PATH=/keycloak
	env := fmt.Sprintf(`[{"name":"KC_HOSTNAME","value":%q},{"name":"KC_HOSTNAME_STRICT","value":"false"},{"name":"KC_HTTP_RELATIVE_PATH","value":"/keycloak"}]`, url+"/keycloak")
	p := []byte(fmt.Sprintf(`{"spec":{"template":{"spec":{"containers":[{"name":"keycloak","env":%s}]}}}}`, env))
	_ = r.Patch(ctx, d, client.RawPatch(types.StrategicMergePatchType, p))
	// readiness path → /keycloak/realms/master
	rp := []byte(`[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/keycloak/realms/master"}]`)
	_ = r.Patch(ctx, deploy(ns, "keycloak"), client.RawPatch(types.JSONPatchType, rp))
}

func (r *reconciler) patchOauth2(ctx context.Context, ns, url string) {
	args := []string{
		"--provider=oidc", "--client-id=oauth2-proxy", "--client-secret=$(KEYCLOAK_CLIENT_SECRET)",
		"--oidc-issuer-url=http://keycloak:8080/keycloak/realms/ai-trust",
		"--login-url=" + url + "/keycloak/realms/ai-trust/protocol/openid-connect/auth",
		"--redeem-url=http://keycloak:8080/keycloak/realms/ai-trust/protocol/openid-connect/token",
		"--oidc-jwks-url=http://keycloak:8080/keycloak/realms/ai-trust/protocol/openid-connect/certs",
		"--skip-oidc-discovery=true", "--insecure-oidc-skip-issuer-verification=true",
		"--redirect-url=" + url + "/oauth2/callback", "--upstream=http://shell:80",
		"--http-address=0.0.0.0:4180", "--cookie-secret=$(OAUTH2_PROXY_COOKIE_SECRET)",
		"--cookie-secure=true", "--email-domain=*", "--pass-authorization-header=true",
		"--backend-logout-url=http://keycloak:8080/keycloak/realms/ai-trust/protocol/openid-connect/logout",
	}
	q := make([]string, len(args))
	for i, a := range args {
		q[i] = fmt.Sprintf("%q", a)
	}
	p := []byte(fmt.Sprintf(`[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":[%s]}]`, strings.Join(q, ",")))
	_ = r.Patch(ctx, deploy(ns, "oauth2-proxy"), client.RawPatch(types.JSONPatchType, p))
}

// ---------- ingress ------------------------------------------------------------------

// wireIngress ensures the wildcard listener exists on the shared gateway, then applies the two
// HTTPRoutes (app + keycloak bypass) and a ReferenceGrant for this instance.
func (r *reconciler) wireIngress(ctx context.Context, gwNS, gwName, ns, host string) error {
	section := env("WILDCARD_LISTENER", "terminate-wildstar")
	r.ensureWildcardListener(ctx, gwNS, gwName, section)
	route := func(name, path, svc string, withMatch bool) *unstructured.Unstructured {
		rule := map[string]interface{}{
			"backendRefs": []interface{}{map[string]interface{}{
				"group": "", "kind": "Service", "name": svc, "namespace": ns, "port": int64(8080),
			}},
		}
		if withMatch {
			rule["matches"] = []interface{}{map[string]interface{}{
				"path": map[string]interface{}{"type": "PathPrefix", "value": path},
			}}
		}
		o := &unstructured.Unstructured{Object: map[string]interface{}{
			"apiVersion": "gateway.networking.k8s.io/v1", "kind": "HTTPRoute",
			"metadata": map[string]interface{}{"name": name, "namespace": gwNS},
			"spec": map[string]interface{}{
				"parentRefs": []interface{}{map[string]interface{}{
					"name": gwName, "namespace": gwNS, "sectionName": section,
				}},
				"hostnames": []interface{}{host},
				"rules":     []interface{}{rule},
			},
		}}
		return o
	}
	rg := &unstructured.Unstructured{Object: map[string]interface{}{
		"apiVersion": "gateway.networking.k8s.io/v1beta1", "kind": "ReferenceGrant",
		"metadata": map[string]interface{}{"name": "allow-mesh-gateway-to-app", "namespace": ns},
		"spec": map[string]interface{}{
			"from": []interface{}{map[string]interface{}{"group": "gateway.networking.k8s.io", "kind": "HTTPRoute", "namespace": gwNS}},
			"to":   []interface{}{map[string]interface{}{"group": "", "kind": "Service"}},
		},
	}}
	for _, o := range []*unstructured.Unstructured{
		route(ns+"-keycloak", "/keycloak", "keycloak", true),
		route(ns+"-app", "/", "oauth2-proxy", false),
		rg,
	} {
		if err := r.Patch(ctx, o, client.Apply, client.ForceOwnership, client.FieldOwner("aitrust-msp-operator")); err != nil {
			return err
		}
	}
	return nil
}

// ensureWildcardListener makes sure a wildcard HTTPS listener named `section` exists on the gateway.
// The stock mesh already ships `terminate-wildstar` (hostname *.<mesh-domain>) — if that (or any listener
// named `section`) is present, do nothing. Otherwise add one reusing the mesh `domain-certificate`.
func (r *reconciler) ensureWildcardListener(ctx context.Context, gwNS, gwName, section string) {
	gw := &unstructured.Unstructured{}
	gw.SetGroupVersionKind(schema.GroupVersionKind{Group: "gateway.networking.k8s.io", Version: "v1", Kind: "Gateway"})
	if err := r.Get(ctx, types.NamespacedName{Namespace: gwNS, Name: gwName}, gw); err != nil {
		return
	}
	listeners, _, _ := unstructured.NestedSlice(gw.Object, "spec", "listeners")
	for _, li := range listeners {
		if m, ok := li.(map[string]interface{}); ok && m["name"] == section {
			return // already present (e.g. the stock terminate-wildstar)
		}
	}
	domainSuffix, _, _, _, _, _ := cfg()
	listener := map[string]interface{}{
		"name": section, "hostname": "*." + domainSuffix,
		"port": int64(8443), "protocol": "HTTPS",
		"tls": map[string]interface{}{
			"mode": "Terminate",
			"certificateRefs": []interface{}{map[string]interface{}{
				"group": "", "kind": "Secret", "name": "domain-certificate", "namespace": gwNS,
			}},
		},
		"allowedRoutes": map[string]interface{}{"namespaces": map[string]interface{}{"from": "All"}},
	}
	listeners = append(listeners, listener)
	_ = unstructured.SetNestedSlice(gw.Object, listeners, "spec", "listeners")
	_ = r.Update(ctx, gw)
}

func (r *reconciler) deleteRoutes(ctx context.Context, gwNS, ns string) {
	for _, n := range []string{ns + "-app", ns + "-keycloak"} {
		o := &unstructured.Unstructured{}
		o.SetGroupVersionKind(schema.GroupVersionKind{Group: "gateway.networking.k8s.io", Version: "v1", Kind: "HTTPRoute"})
		o.SetNamespace(gwNS)
		o.SetName(n)
		_ = r.Delete(ctx, o)
	}
}

func (r *reconciler) deleteNamespace(ctx context.Context, ns string) {
	o := &unstructured.Unstructured{}
	o.SetGroupVersionKind(schema.GroupVersionKind{Version: "v1", Kind: "Namespace"})
	o.SetName(ns)
	_ = r.Delete(ctx, o)
}

// ---------- status -------------------------------------------------------------------

// aggregate returns (allReady, total, available) across all Deployments in the instance namespace.
func (r *reconciler) aggregate(ctx context.Context, ns string) (bool, int, int) {
	list := &unstructured.UnstructuredList{}
	list.SetGroupVersionKind(schema.GroupVersionKind{Group: "apps", Version: "v1", Kind: "DeploymentList"})
	if err := r.List(ctx, list, client.InNamespace(ns)); err != nil {
		return false, 0, 0
	}
	total := len(list.Items)
	avail := 0
	for i := range list.Items {
		d := &list.Items[i]
		want, _, _ := unstructured.NestedInt64(d.Object, "spec", "replicas")
		if want == 0 {
			want = 1
		}
		got, _, _ := unstructured.NestedInt64(d.Object, "status", "availableReplicas")
		if got >= want {
			avail++
		}
	}
	return total > 0 && avail == total, total, avail
}

func (r *reconciler) setPhase(ctx context.Context, cr *unstructured.Unstructured, phase string, ready bool, url, ns, msg string) {
	// Refetch the latest version so the status write doesn't conflict with the finalizer Update
	// (or any other in-reconcile change) that bumped resourceVersion.
	latest := &unstructured.Unstructured{}
	latest.SetGroupVersionKind(gvk)
	if err := r.Get(ctx, types.NamespacedName{Namespace: cr.GetNamespace(), Name: cr.GetName()}, latest); err != nil {
		return
	}
	st := map[string]interface{}{
		"ready": ready, "phase": phase, "url": url, "namespace": ns,
		"observedGeneration": latest.GetGeneration(),
		"conditions": []interface{}{map[string]interface{}{
			"type": "Ready", "status": boolStr(ready), "reason": phase,
			"message": msg, "lastTransitionTime": time.Now().UTC().Format(time.RFC3339),
		}},
	}
	_ = unstructured.SetNestedMap(latest.Object, st, "status")
	if err := r.Status().Update(ctx, latest); err != nil {
		log.FromContext(ctx).Error(err, "status update failed")
	}
}

func (r *reconciler) fail(ctx context.Context, cr *unstructured.Unstructured, url, ns, step string, err error) (ctrl.Result, error) {
	log.FromContext(ctx).Error(err, "reconcile step failed", "step", step)
	r.setPhase(ctx, cr, "Degraded", false, url, ns, fmt.Sprintf("%s: %v", step, err))
	return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
}

// ---------- small utils --------------------------------------------------------------

func deploy(ns, name string) *unstructured.Unstructured {
	o := &unstructured.Unstructured{}
	o.SetGroupVersionKind(schema.GroupVersionKind{Group: "apps", Version: "v1", Kind: "Deployment"})
	o.SetNamespace(ns)
	o.SetName(name)
	return o
}

func pinPodSpec(job *unstructured.Unstructured, poolLabel string) {
	ps, _, _ := unstructured.NestedMap(job.Object, "spec", "template", "spec")
	if ps == nil {
		ps = map[string]interface{}{}
	}
	ps["nodeSelector"] = map[string]interface{}{"workload": poolLabel}
	ps["tolerations"] = []interface{}{map[string]interface{}{"key": "workload", "value": poolLabel, "effect": "NoSchedule"}}
	_ = unstructured.SetNestedMap(job.Object, ps, "spec", "template", "spec")
}

func setJobEnv(job *unstructured.Unstructured, k, v string) {
	conts, _, _ := unstructured.NestedSlice(job.Object, "spec", "template", "spec", "containers")
	for i, c := range conts {
		m, ok := c.(map[string]interface{})
		if !ok {
			continue
		}
		envs, _, _ := unstructured.NestedSlice(m, "env")
		envs = append(envs, map[string]interface{}{"name": k, "value": v})
		_ = unstructured.SetNestedSlice(m, envs, "env")
		conts[i] = m
	}
	_ = unstructured.SetNestedSlice(job.Object, conts, "spec", "template", "spec", "containers")
}

func decodeAll(doc string) []*unstructured.Unstructured {
	var out []*unstructured.Unstructured
	dec := utilyaml.NewYAMLOrJSONDecoder(bytes.NewReader([]byte(doc)), 4096)
	for {
		m := map[string]interface{}{}
		if err := dec.Decode(&m); err != nil {
			break
		}
		if len(m) == 0 {
			continue
		}
		out = append(out, &unstructured.Unstructured{Object: m})
	}
	return out
}

func secretExists(ctx context.Context, c client.Client, ns string) bool {
	s := &unstructured.Unstructured{}
	s.SetGroupVersionKind(schema.GroupVersionKind{Version: "v1", Kind: "Secret"})
	err := c.Get(ctx, types.NamespacedName{Namespace: ns, Name: "app-secrets"}, s)
	return err == nil
}

func hasFinalizer(o *unstructured.Unstructured) bool {
	for _, f := range o.GetFinalizers() {
		if f == finalizer {
			return true
		}
	}
	return false
}
func addFinalizer(o *unstructured.Unstructured) { o.SetFinalizers(append(o.GetFinalizers(), finalizer)) }
func removeFinalizer(o *unstructured.Unstructured) {
	var out []string
	for _, f := range o.GetFinalizers() {
		if f != finalizer {
			out = append(out, f)
		}
	}
	o.SetFinalizers(out)
}

func strOr(v interface{}, def string) string {
	if s, ok := v.(string); ok && s != "" {
		return s
	}
	return def
}

var nonDNS = regexp.MustCompile(`[^a-z0-9-]`)

func dnsSafe(s string) string {
	s = strings.ToLower(s)
	s = nonDNS.ReplaceAllString(s, "-")
	s = strings.Trim(s, "-")
	if len(s) > 60 {
		s = strings.Trim(s[:60], "-")
	}
	return s
}

func randHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func boolStr(b bool) string {
	if b {
		return "True"
	}
	return "False"
}

func main() {
	ctrl.SetLogger(zap.New(zap.UseDevMode(true)))
	mgr, err := manager.New(ctrl.GetConfigOrDie(), manager.Options{})
	if err != nil {
		panic(err)
	}
	proto := &unstructured.Unstructured{}
	proto.SetGroupVersionKind(gvk)
	if err := builder.ControllerManagedBy(mgr).For(proto).Complete(&reconciler{mgr.GetClient()}); err != nil {
		panic(err)
	}
	ds, reg, tag, _, _, _ := cfg()
	log.Log.Info("aitrust-msp-operator starting", "domainSuffix", ds, "registry", reg, "tag", tag)
	if err := mgr.Start(signals.SetupSignalHandler()); err != nil {
		panic(err)
	}
}
