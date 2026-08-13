package main

// aitrust-mt-operator (v5) — watches Subscription CRs and onboards each customer ORG as a TENANT of the
// ONE SHARED "AI Trust Platform MT" app. It does NOT stamp an app copy. Per Subscription it:
//   1. resolves the org (spec.org == the org's Platform-Mesh account == its mesh Keycloak realm name),
//   2. ensures a per-org secret (oauth2-proxy client secret + cookie secret),
//   3. stamps a Job that creates the per-org oauth2-proxy OIDC client (+ tenant_id=<org> claim mapper) in
//      the shared MESH Keycloak realm <org>,
//   4. stamps a per-org oauth2-proxy + Service + HTTPRoute + ReferenceGrant on a per-org host
//      (ai-trust-mt-<org>.<suffix>) → the shared app (upstream shell:80),
//   5. seeds the org admin's user→platform_administrator tuple in the ONE shared app OpenFGA store,
//   6. writes the per-org login URL + realm + tenantId to status.
// Tenant DATA isolation is Postgres RLS (tenant_id = the org), enforced inside the shared app by libs/tenancy.
//
// The finalizer best-effort removes the per-org oauth2-proxy/route (by org label); tenant DATA is never
// deleted (append-only inference log).

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

//go:embed manifests/*.tmpl
var manifestFS embed.FS

var gvk = schema.GroupVersionKind{Group: "sub.aitrustmt.msp", Version: "v1alpha1", Kind: "Subscription"}

const finalizer = "subscription.sub.aitrustmt.msp/finalizer"

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

type config struct {
	providerNS     string // ns on the shoot for the shared app + per-org proxies
	domainSuffix   string // per-org host = ai-trust-mt-<org>.<domainSuffix>
	poolLabel      string // worker pool nodeSelector/toleration value
	kcInternal     string // in-cluster mesh keycloak base, incl /keycloak (issuer/redeem/jwks)
	kcPublic       string // public mesh keycloak base, incl /keycloak (browser login-url)
	gatewayNS      string
	gatewayName    string
	gatewaySection string // listener sectionName that terminates *.<domainSuffix>
	openfgaURL     string // shared mesh OpenFGA http endpoint
	storeID        string // the ONE shared app store id (roles seeded at deploy)
	meshAdminNS    string // ns holding the mesh keycloak bootstrap-admin secret
	meshAdminName  string // name of that secret (keys: username/password)
}

func cfg() config {
	return config{
		providerNS:     env("PROVIDER_NS", "aitrust-mt-msp"),
		domainSuffix:   env("INSTANCE_DOMAIN_SUFFIX", "ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"),
		poolLabel:      env("MSP_WORKER_LABEL", "ai-trust-mt"),
		kcInternal:     env("KC_INTERNAL_URL", "http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak"),
		kcPublic:       env("KC_PUBLIC_URL", "https://ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/keycloak"),
		gatewayNS:      env("GATEWAY_NS", "platform-mesh-system"),
		gatewayName:    env("GATEWAY_NAME", "k8sapi-gateway"),
		gatewaySection: env("GATEWAY_SECTION", "terminate-wildstar"),
		openfgaURL:     env("OPENFGA_URL", "http://openfga.platform-mesh-system.svc.cluster.local:8080"),
		storeID:        env("OPENFGA_STORE_ID", ""),
		meshAdminNS:    env("MESH_KC_ADMIN_NS", "platform-mesh-system"),
		meshAdminName:  env("MESH_KC_ADMIN_SECRET", "keycloak-admin"),
	}
}

type reconciler struct {
	client.Client
	cfg config
}

func (r *reconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	l := log.FromContext(ctx)
	cr := &unstructured.Unstructured{}
	cr.SetGroupVersionKind(gvk)
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	spec, _, _ := unstructured.NestedMap(cr.Object, "spec")
	display := strOr(spec["displayName"], "AI Trust Platform MT")
	adminEmail := strOr(spec["adminEmail"], "")

	// org == the mesh account/realm. spec.org is authoritative; fall back to the mirror namespace
	// (consumer cluster id) only so the CR still reconciles — but that is NOT a real realm, so auth
	// won't work until spec.org is set. tenant_id (for RLS) == org.
	org := dnsSafe(strOr(spec["org"], ""))
	if org == "" {
		org = dnsSafe(cr.GetNamespace())
	}
	tenantID := org
	orgHost := "ai-trust-mt-" + org + "." + r.cfg.domainSuffix
	url := "https://" + orgHost

	// ---- finalizer / delete ----------------------------------------------------
	if !cr.GetDeletionTimestamp().IsZero() {
		if hasFinalizer(cr) {
			l.Info("de-provisioning subscription (soft-disable)", "org", org)
			r.deleteOrgResources(ctx, org)
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

	if strOr(spec["org"], "") == "" {
		r.setPhase(ctx, cr, "Degraded", false, url, tenantID, org,
			"spec.org is empty — set it to the consumer org / mesh realm name so auth can be wired")
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// ---- 1. per-org secret (client secret + cookie secret) ---------------------
	secretName := "aitrust-mt-oauth2-" + org
	clientSecret, cookieSecret, err := r.ensureOrgSecret(ctx, secretName, org)
	if err != nil {
		return r.fail(ctx, cr, url, tenantID, org, "ensure secret", err)
	}
	_ = clientSecret // consumed by the Job + proxy via secretKeyRef

	// ---- 2. per-org OIDC client in the mesh realm (idempotent Job) -------------
	// The Job authenticates to the MESH Keycloak, so it needs the mesh bootstrap-admin creds. Copy that
	// secret from the mesh ns into the provider ns once (fresh deploys get it automatically — no manual step).
	if err := r.ensureMeshAdminSecret(ctx); err != nil {
		return r.fail(ctx, cr, url, tenantID, org, "ensure mesh admin secret", err)
	}
	jobName := dnsSafe("kc-client-" + org)
	if !r.jobExists(ctx, r.cfg.providerNS, jobName) {
		doc := r.render("keycloak-client-job.tmpl", map[string]string{
			"__JOB_NAME__": jobName, "__NS__": r.cfg.providerNS, "__ORG__": org,
			"__POOL_LABEL__": r.cfg.poolLabel, "__KC_INTERNAL__": r.cfg.kcInternal,
			"__CB_URL__": url + "/oauth2/callback", "__ORIGIN__": url,
			"__CLIENT_ID__": "aitrust-mt-app", "__SECRET_NAME__": secretName, "__SECRET_KEY__": "client-secret",
		})
		if err := r.applyDoc(ctx, doc); err != nil {
			return r.fail(ctx, cr, url, tenantID, org, "stamp kc-client job", err)
		}
	}

	// ---- 3. per-org oauth2-proxy + Service + HTTPRoute + ReferenceGrant --------
	proxyDoc := r.render("oauth2-proxy-org.tmpl", map[string]string{
		"__ORG__": org, "__NS__": r.cfg.providerNS, "__ORG_HOST__": orgHost,
		"__KC_INTERNAL_REALM__": r.cfg.kcInternal + "/realms/" + org,
		"__KC_PUBLIC_REALM__":   r.cfg.kcPublic + "/realms/" + org,
		"__SECRET_NAME__":       secretName, "__SECRET_KEY__": "client-secret",
		"__COOKIE_SECRET__": cookieSecret,
		"__GATEWAY_NS__":    r.cfg.gatewayNS, "__GATEWAY_NAME__": r.cfg.gatewayName,
		"__GATEWAY_SECTION__": r.cfg.gatewaySection,
	})
	if err := r.applyDoc(ctx, proxyDoc); err != nil {
		return r.fail(ctx, cr, url, tenantID, org, "stamp oauth2-proxy", err)
	}

	// ---- 4. seed the org admin's role tuple in the SHARED store (best-effort) --
	if adminEmail != "" && r.cfg.storeID != "" {
		if err := r.seedAdminTuple(ctx, adminEmail); err != nil {
			l.Info("admin tuple seed failed (non-fatal)", "err", err.Error())
		}
	}

	// ---- 5. status -------------------------------------------------------------
	r.setPhase(ctx, cr, "Ready", true, url, tenantID, org,
		fmt.Sprintf("tenant '%s' active: mesh realm '%s' + per-org oauth2-proxy at %s (data isolated by tenant_id/RLS)", tenantID, org, orgHost))
	_ = display
	return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
}

// ensureOrgSecret creates (once) a Secret holding the per-org oauth2-proxy client secret + cookie secret.
// Returns the two values (read back if the secret already exists so the Job + proxy agree).
func (r *reconciler) ensureOrgSecret(ctx context.Context, name, org string) (clientSecret, cookieSecret string, err error) {
	sec := &unstructured.Unstructured{}
	sec.SetGroupVersionKind(schema.GroupVersionKind{Version: "v1", Kind: "Secret"})
	getErr := r.Get(ctx, types.NamespacedName{Namespace: r.cfg.providerNS, Name: name}, sec)
	if getErr == nil {
		data, _, _ := unstructured.NestedMap(sec.Object, "data")
		// data values are base64 in the API; controller-runtime returns them as base64 strings.
		return decodeB64(strFrom(data["client-secret"])), decodeB64(strFrom(data["cookie-secret"])), nil
	}
	clientSecret = randHex(24)
	cookieSecret = randHex(16) // 32 hex chars = 16 bytes, valid oauth2-proxy cookie secret
	sec = &unstructured.Unstructured{Object: map[string]interface{}{
		"apiVersion": "v1", "kind": "Secret",
		"metadata": map[string]interface{}{
			"name": name, "namespace": r.cfg.providerNS,
			"labels": map[string]interface{}{"app.kubernetes.io/managed-by": "aitrust-mt-operator", "org": org},
		},
		"stringData": map[string]interface{}{"client-secret": clientSecret, "cookie-secret": cookieSecret},
	}}
	if err = r.Create(ctx, sec); err != nil {
		return "", "", err
	}
	return clientSecret, cookieSecret, nil
}

// ensureMeshAdminSecret copies the MESH Keycloak bootstrap-admin secret (username/password) from the mesh
// namespace into the provider namespace as `mesh-keycloak-admin`, so the per-org kc-client Job can auth to
// the mesh Keycloak Admin API. Idempotent: no-op once the copy exists. Makes fresh deploys self-sufficient.
func (r *reconciler) ensureMeshAdminSecret(ctx context.Context) error {
	const copyName = "mesh-keycloak-admin"
	dst := &unstructured.Unstructured{}
	dst.SetGroupVersionKind(schema.GroupVersionKind{Version: "v1", Kind: "Secret"})
	if err := r.Get(ctx, types.NamespacedName{Namespace: r.cfg.providerNS, Name: copyName}, dst); err == nil {
		return nil // already copied
	}
	src := &unstructured.Unstructured{}
	src.SetGroupVersionKind(schema.GroupVersionKind{Version: "v1", Kind: "Secret"})
	if err := r.Get(ctx, types.NamespacedName{Namespace: r.cfg.meshAdminNS, Name: r.cfg.meshAdminName}, src); err != nil {
		return fmt.Errorf("read mesh admin secret %s/%s: %w", r.cfg.meshAdminNS, r.cfg.meshAdminName, err)
	}
	data, _, _ := unstructured.NestedMap(src.Object, "data") // base64 values, copied verbatim
	copySecret := &unstructured.Unstructured{Object: map[string]interface{}{
		"apiVersion": "v1", "kind": "Secret",
		"metadata": map[string]interface{}{
			"name": copyName, "namespace": r.cfg.providerNS,
			"labels": map[string]interface{}{"app.kubernetes.io/managed-by": "aitrust-mt-operator"},
		},
		"type": "Opaque",
		"data": data,
	}}
	return r.Create(ctx, copySecret)
}

// seedAdminTuple writes user:<email> → member → role:platform_administrator to the shared OpenFGA store.
func (r *reconciler) seedAdminTuple(ctx context.Context, email string) error {
	body := fmt.Sprintf(`{"writes":{"tuple_keys":[{"user":"user:%s","relation":"member","object":"role:platform_administrator"}]}}`, email)
	req := r.cfg.openfgaURL + "/stores/" + r.cfg.storeID + "/write"
	return httpPost(ctx, req, body) // ignores 400 already-exists inside
}

// deleteOrgResources best-effort removes the per-org proxy/route/secret on Subscription delete.
func (r *reconciler) deleteOrgResources(ctx context.Context, org string) {
	del := func(gvk schema.GroupVersionKind, ns, name string) {
		o := &unstructured.Unstructured{}
		o.SetGroupVersionKind(gvk)
		o.SetNamespace(ns)
		o.SetName(name)
		_ = r.Delete(ctx, o)
	}
	del(schema.GroupVersionKind{Group: "apps", Version: "v1", Kind: "Deployment"}, r.cfg.providerNS, "oauth2-proxy-"+org)
	del(schema.GroupVersionKind{Version: "v1", Kind: "Service"}, r.cfg.providerNS, "oauth2-proxy-"+org)
	del(schema.GroupVersionKind{Group: "gateway.networking.k8s.io", Version: "v1", Kind: "HTTPRoute"}, r.cfg.gatewayNS, "aitrust-mt-"+org)
	del(schema.GroupVersionKind{Group: "gateway.networking.k8s.io", Version: "v1beta1", Kind: "ReferenceGrant"}, r.cfg.providerNS, "allow-gw-to-oauth2-"+org)
}

// ---------- rendering / apply --------------------------------------------------

func (r *reconciler) render(tmpl string, repl map[string]string) string {
	b, err := manifestFS.ReadFile("manifests/" + tmpl)
	if err != nil {
		return ""
	}
	s := string(b)
	for k, v := range repl {
		s = strings.ReplaceAll(s, k, v)
	}
	return s
}

func (r *reconciler) applyDoc(ctx context.Context, doc string) error {
	for _, obj := range decodeAll(doc) {
		if obj == nil {
			continue
		}
		if err := r.Patch(ctx, obj, client.Apply, client.ForceOwnership, client.FieldOwner("aitrust-mt-operator")); err != nil {
			return fmt.Errorf("apply %s/%s: %w", obj.GetKind(), obj.GetName(), err)
		}
	}
	return nil
}

func (r *reconciler) jobExists(ctx context.Context, ns, name string) bool {
	j := &unstructured.Unstructured{}
	j.SetGroupVersionKind(schema.GroupVersionKind{Group: "batch", Version: "v1", Kind: "Job"})
	return r.Get(ctx, types.NamespacedName{Namespace: ns, Name: name}, j) == nil
}

// ---------- status -------------------------------------------------------------

func (r *reconciler) setPhase(ctx context.Context, cr *unstructured.Unstructured, phase string, ready bool, url, tenantID, realm, msg string) {
	latest := &unstructured.Unstructured{}
	latest.SetGroupVersionKind(gvk)
	if err := r.Get(ctx, types.NamespacedName{Namespace: cr.GetNamespace(), Name: cr.GetName()}, latest); err != nil {
		return
	}
	st := map[string]interface{}{
		"ready": ready, "phase": phase, "url": url, "tenantId": tenantID, "realm": realm,
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

func (r *reconciler) fail(ctx context.Context, cr *unstructured.Unstructured, url, tenantID, realm, step string, err error) (ctrl.Result, error) {
	log.FromContext(ctx).Error(err, "reconcile step failed", "step", step)
	r.setPhase(ctx, cr, "Degraded", false, url, tenantID, realm, fmt.Sprintf("%s: %v", step, err))
	return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
}

// ---------- utils --------------------------------------------------------------

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
func strFrom(v interface{}) string {
	if s, ok := v.(string); ok {
		return s
	}
	return ""
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
	c := cfg()
	proto := &unstructured.Unstructured{}
	proto.SetGroupVersionKind(gvk)
	if err := builder.ControllerManagedBy(mgr).For(proto).Complete(&reconciler{Client: mgr.GetClient(), cfg: c}); err != nil {
		panic(err)
	}
	log.Log.Info("aitrust-mt-operator v5 starting", "providerNS", c.providerNS, "domainSuffix", c.domainSuffix,
		"gateway", c.gatewayName, "storeID", c.storeID != "")
	if err := mgr.Start(signals.SetupSignalHandler()); err != nil {
		panic(err)
	}
}
