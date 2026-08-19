package main

// aitrust-federation — the FEDERATION controller. Runs on ai-trust-PROD, watches sub.aitrust.remote
// Subscription CRs (published into prod kcp ws root:providers:ai-trust-remote by the bundled sync-agent),
// and provisions each customer ORG as a TENANT **on the ai-trust-1 cluster** (via a mounted, scoped SA
// kubeconfig). Fork of the stock aitrust-operator with a TWO-CLIENT split:
//   * r.Client (local) = prod kcp — watch Subscriptions, write status, finalizer, duplicate guard.
//   * r.remote         = ai-trust-1 shoot API — apply/read the per-tenant provisioning (stores Job,
//                        kc-client Job, oauth2-proxy + Service + HTTPRoute + secrets) and teardown.
// Federated tenants are namespaced `fed-<org>` on a1 (schema tenant_fed_<org>, CH db tenant_fed_<org>,
// bucket tenant-fed-<org>, role t_fed_<org>, host ai-trust-fed-<org>.<a1-suffix>) so they never collide
// with a1's native tenants or a same-named prod-local tenant. Tenant DATA is never deleted.

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
	"github.com/go-logr/logr"
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

// The federated provider's CR group (published by the sync-agent into root:providers:ai-trust-remote).
var gvk = schema.GroupVersionKind{Group: "sub.aitrust.remote", Version: "v1alpha1", Kind: "Subscription"}

const finalizer = "subscription.sub.aitrust.remote/finalizer"

// fedPrefix namespaces every federated tenant on a1 so it can't collide with a1's native tenants.
const fedPrefix = "fed-"

// remoteCluster is written to status.cluster so the federated tile shows where the workload lives.
const remoteCluster = "ai-trust-1"

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

type config struct {
	providerNS     string // ns on the shoot for the shared app + per-org proxies
	domainSuffix   string // per-org host = ai-trust-<org>.<domainSuffix>
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
	dbMigrateImage string // image (alembic + ai_trust_persistence) used to provision per-tenant schemas
	chMigrateImage string // image (clickhouse-migrate) used to provision per-tenant ClickHouse databases
	appRole        string // the non-superuser runtime Postgres role granted on each tenant schema
	remoteKubecfg  string // path to the mounted ai-trust-1 SA kubeconfig (provisioning target)
	prodKcPublic   string // PROD public Keycloak base (incl /keycloak) — the realm the a1 IdP brokers
	idpClientID    string // OIDC client id the a1 'prod' IdP uses at prod's Keycloak
	prodKcInternal string // PROD in-cluster mesh Keycloak base (reachable from the controller on prod)
	localNS        string // the controller's OWN namespace on prod (aitrust-remote) — where local Jobs run
	prodMeshAdminNS   string // prod mesh keycloak-admin secret ns
	prodMeshAdminName string // prod mesh keycloak-admin secret name
}

func cfg() config {
	return config{
		providerNS:     env("PROVIDER_NS", "aitrust-msp"),
		domainSuffix:   env("INSTANCE_DOMAIN_SUFFIX", "ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"),
		poolLabel:      env("MSP_WORKER_LABEL", "ai-trust"),
		kcInternal:     env("KC_INTERNAL_URL", "http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak"),
		kcPublic:       env("KC_PUBLIC_URL", "https://ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/keycloak"),
		gatewayNS:      env("GATEWAY_NS", "platform-mesh-system"),
		gatewayName:    env("GATEWAY_NAME", "k8sapi-gateway"),
		gatewaySection: env("GATEWAY_SECTION", "terminate-wildstar"),
		openfgaURL:     env("OPENFGA_URL", "http://openfga.platform-mesh-system.svc.cluster.local:8080"),
		storeID:        env("OPENFGA_STORE_ID", ""),
		meshAdminNS:    env("MESH_KC_ADMIN_NS", "platform-mesh-system"),
		meshAdminName:  env("MESH_KC_ADMIN_SECRET", "keycloak-admin"),
		dbMigrateImage: env("DBMIGRATE_IMAGE", "mirceacraciun795/aitrust-db-migrate:aitrust"),
		chMigrateImage: env("CHMIGRATE_IMAGE", "mirceacraciun795/aitrust-clickhouse-migrate:aitrust"),
		appRole:        env("APP_DB_ROLE", "ai_trust_app"),
		remoteKubecfg:  env("REMOTE_KUBECONFIG", "/etc/a1/kubeconfig"),
		prodKcPublic:   env("PROD_KC_PUBLIC_URL", "https://ai-trust-prod.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/keycloak"),
		idpClientID:    env("IDP_CLIENT_ID", "aitrust-fed-broker"),
		prodKcInternal: env("PROD_KC_INTERNAL_URL", "http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak"),
		localNS:        env("LOCAL_NS", "aitrust-remote"),
		prodMeshAdminNS:   env("PROD_MESH_KC_ADMIN_NS", "platform-mesh-system"),
		prodMeshAdminName: env("PROD_MESH_KC_ADMIN_SECRET", "keycloak-admin"),
	}
}

type reconciler struct {
	client.Client               // LOCAL: prod kcp — Subscription watch, status, finalizer, dup guard.
	remote        client.Client // REMOTE: ai-trust-1 — all provisioning applies/reads + teardown.
	cfg           config
}

func (r *reconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	l := log.FromContext(ctx)
	cr := &unstructured.Unstructured{}
	cr.SetGroupVersionKind(gvk)
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	spec, _, _ := unstructured.NestedMap(cr.Object, "spec")
	display := strOr(spec["displayName"], "AI Trust Platform")
	adminEmail := strOr(spec["adminEmail"], "")
	// suspended (provider action): when true the tenant's oauth2-proxy is stamped with 0 replicas, so
	// its host stops serving (login blocked) while ALL data + resources stay intact. Reversible.
	suspended, _, _ := unstructured.NestedBool(cr.Object, "spec", "suspended")
	proxyReplicas := "1"
	if suspended {
		proxyReplicas = "0"
	}

	// org == the mesh account/realm. spec.org is authoritative. Trim whitespace BEFORE dnsSafe (dnsSafe
	// turns an internal space into '-', which would corrupt the realm name). No cluster-id fallback: an
	// empty org can only Degrade.
	//
	// FEDERATION: every federated tenant is namespaced with the `fed-` prefix on ai-trust-1 so it can
	// never collide with a1's native tenants (fridaytest/martin/…) or a same-named prod-local tenant.
	// This one substitution flows through EVERYTHING derived from org: the a1 Keycloak realm `fed-<org>`
	// (Stage 4 brokers prod's real `<org>` realm INTO it for SSO), the host ai-trust-fed-<org>.<a1-suffix>,
	// the PG schema tenant_fed_<org>, CH db tenant_fed_<org>, bucket tenant-fed-<org>, role t_fed_<org>,
	// and the oauth2-proxy/secret/route names.
	rawOrg := strings.TrimSpace(strOr(spec["org"], ""))
	baseOrg := dnsSafe(rawOrg)
	org := ""
	if baseOrg != "" {
		org = fedPrefix + baseOrg
	}
	tenantID := org
	orgHost := "ai-trust-" + org + "." + r.cfg.domainSuffix
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

	if rawOrg == "" {
		r.setPhase(ctx, cr, "Degraded", false, url, tenantID, org,
			"spec.org is empty — set it to the consumer org / mesh realm name so auth can be wired")
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// ---- GUARD: one subscription per organization. The tenant host/URL and realm are BOTH derived
	//      from org (orgHost above), so two Subscriptions naming the same org would collide on the same
	//      host + tenant data. Policy is one-tenant-per-org, so a duplicate is rejected here (fail-closed,
	//      stamp nothing) rather than clobbering the existing tenant. Deterministic owner = the OLDEST
	//      active (non-deleting) Subscription for that org (by creationTimestamp, uid tie-break), so the
	//      choice is stable across restarts/re-reconciles and a Ready sub never Degrades itself.
	if owner := r.orgOwner(ctx, org, cr); owner != nil {
		ons, _, _ := unstructured.NestedString(owner.Object, "metadata", "namespace")
		oname, _, _ := unstructured.NestedString(owner.Object, "metadata", "name")
		l.Info("duplicate org — another subscription already owns this org; refusing to provision",
			"org", org, "owner", ons+"/"+oname)
		r.setPhase(ctx, cr, "Degraded", false, url, tenantID, org,
			fmt.Sprintf("Only one subscription is allowed per organization. Org '%s' already has an active "+
				"subscription ('%s/%s' at %s). Use the existing subscription, or delete it before creating a new one.",
				org, ons, oname, url))
		return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
	}

	// ---- 0-FED. STAGE 4 — ensure the a1 tenant realm `fed-<org>` exists + brokers PROD's realm -------
	// Federated tenants have no realm on a1 until we make one. Before the realm gate below, stamp a Job
	// on a1 that (a) creates realm `fed-<org>`, (b) registers an OIDC IdP 'prod' brokering prod's realm
	// `<baseOrg>` (Option A SSO), (c) adds a tenant_id mapper. This makes the gate pass, then normal
	// provisioning proceeds. Requires the mesh-admin secret copy + an IdP client secret (reused per-org).
	if err := r.ensureMeshAdminSecret(ctx); err != nil {
		return r.fail(ctx, cr, url, tenantID, org, "ensure mesh admin secret (broker)", err)
	}
	brokerSecret := "aitrust-fedbroker-" + org
	if _, _, err := r.ensureOrgSecret(ctx, brokerSecret, org); err != nil {
		return r.fail(ctx, cr, url, tenantID, org, "ensure broker client secret", err)
	}
	brokerJob := dnsSafe("kc-broker-" + org)
	if !r.jobExists(ctx, r.cfg.providerNS, brokerJob) {
		doc := r.render("keycloak-broker-job.tmpl", map[string]string{
			"__JOB_NAME__": brokerJob, "__NS__": r.cfg.providerNS, "__ORG__": org, "__BASEORG__": baseOrg,
			"__POOL_LABEL__": r.cfg.poolLabel, "__KC_INTERNAL__": r.cfg.kcInternal,
			"__PROD_KC_PUBLIC__": r.cfg.prodKcPublic, "__PROD_CLIENT_ID__": r.cfg.idpClientID,
			"__SECRET_NAME__": brokerSecret, "__SECRET_KEY__": "client-secret",
		})
		if err := r.applyDoc(ctx, doc); err != nil {
			return r.fail(ctx, cr, url, tenantID, org, "stamp kc-broker job", err)
		}
	}
	if !r.jobSucceeded(ctx, r.cfg.providerNS, brokerJob) {
		l.Info("waiting for a1 realm+IdP broker Job", "org", org, "realm", org)
		r.setPhase(ctx, cr, "Provisioning", false, url, tenantID, org,
			fmt.Sprintf("creating a1 realm '%s' + brokering prod realm '%s' (SSO) — not ready yet", org, baseOrg))
		return ctrl.Result{RequeueAfter: 15 * time.Second}, nil
	}

	// ---- 0. REALM: for federated tenants the a1 realm `fed-<org>` is CREATED + brokered by the broker
	//      Job above (which ran ON ai-trust-1 and completed successfully — that success IS the proof the
	//      realm exists). We deliberately do NOT re-check via a direct HTTP call here: the controller runs
	//      on PROD and a1's mesh Keycloak is only reachable by in-cluster DNS FROM a1 (the broker Job's
	//      context), not from the prod controller process. So the broker Job's success gates provisioning.
	l.Info("a1 realm+IdP broker Job succeeded — realm ready, proceeding", "org", org, "brokers", baseOrg)

	// ---- 0b. PER-TENANT STORES (physical isolation across Postgres + ClickHouse + MinIO) --------
	// Provision the tenant's own Postgres schema `tenant_<org>`, ClickHouse database `tenant_<org>`,
	// and MinIO bucket `tenant-<org>` (hyphens→underscores for PG/CH identifiers; hyphens for the S3
	// bucket) via ONE Job (CH+MinIO as init containers, PG as the main container). GATE Ready on the
	// Job succeeding, so the tenant host is never advertised before its stores exist (fail-closed:
	// the Subscription sits in Provisioning until then). Idempotent throughout.
	schemaName := "tenant_" + strings.ReplaceAll(org, "-", "_") // PG schema + CH database
	bucketName := "tenant-" + strings.ToLower(strings.ReplaceAll(org, "_", "-")) // S3 bucket (DNS-safe)
	storesJob := dnsSafe("tenant-stores-" + org)
	if !r.jobExists(ctx, r.cfg.providerNS, storesJob) {
		doc := r.render("tenant-stores-job.tmpl", map[string]string{
			"__JOB_NAME__": storesJob, "__NS__": r.cfg.providerNS, "__ORG__": org,
			"__SCHEMA__": schemaName, "__POOL_LABEL__": r.cfg.poolLabel,
			"__DBMIGRATE_IMAGE__": r.cfg.dbMigrateImage, "__APP_ROLE__": r.cfg.appRole,
			"__CHMIGRATE_IMAGE__": r.cfg.chMigrateImage, "__CH_DB__": schemaName, "__BUCKET__": bucketName,
		})
		if err := r.applyDoc(ctx, doc); err != nil {
			return r.fail(ctx, cr, url, tenantID, org, "stamp tenant-stores job", err)
		}
	}
	if !r.jobSucceeded(ctx, r.cfg.providerNS, storesJob) {
		l.Info("waiting for per-tenant Postgres schema provisioning", "org", org, "schema", schemaName)
		r.setPhase(ctx, cr, "Provisioning", false, url, tenantID, org,
			fmt.Sprintf("provisioning tenant store (Postgres schema '%s') — not ready yet", schemaName))
		return ctrl.Result{RequeueAfter: 15 * time.Second}, nil
	}

	// ---- 1. per-org secret (client secret + cookie secret) ---------------------
	secretName := "aitrust-oauth2-" + org
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
			"__CLIENT_ID__": "aitrust-app", "__SECRET_NAME__": secretName, "__SECRET_KEY__": "client-secret",
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
		"__WHITELIST_DOMAIN__":  r.cfg.domainSuffix,
		"__SECRET_NAME__":       secretName, "__SECRET_KEY__": "client-secret",
		"__COOKIE_SECRET__": cookieSecret, "__REPLICAS__": proxyReplicas,
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

	// ---- 4b. RECIPROCAL SSO CLIENT (Stage 6) — register the OIDC client in PROD's realm <baseOrg> that
	//      a1's `prod` IdP uses, so the browser SSO round-trip completes. Runs as a Job ON PROD (local),
	//      because prod's mesh Keycloak is reachable from the controller here. Uses the SAME per-org secret
	//      value the a1 IdP holds (aitrust-fedbroker-<org>). BEST-EFFORT + non-fatal: if the prod realm
	//      <baseOrg> doesn't exist yet (e.g. a synthetic org), the Job fails and we log it — the federated
	//      tenant is still fully Ready; only the interactive SSO needs this client.
	if err := r.reconcileReciprocalSSO(ctx, l, org, baseOrg); err != nil {
		l.Info("reciprocal prod-side SSO client not wired yet (non-fatal)", "org", org, "baseOrg", baseOrg, "reason", err.Error())
	}

	// ---- 5. status -------------------------------------------------------------
	if suspended {
		r.setPhase(ctx, cr, "Suspended", false, url, tenantID, org,
			fmt.Sprintf("tenant '%s' SUSPENDED by provider: login blocked (oauth2-proxy scaled to 0); data + stores intact. Resume to restore.", tenantID))
		_ = display
		return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
	}
	r.setPhase(ctx, cr, "Ready", true, url, tenantID, org,
		fmt.Sprintf("federated tenant '%s' active ON ai-trust-1: realm '%s' (brokers prod '%s' for SSO) + per-org oauth2-proxy at %s (physical schema/DB/bucket isolation)", tenantID, org, baseOrg, orgHost))
	_ = display
	return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
}

// ensureOrgSecret creates (once) a Secret holding the per-org oauth2-proxy client secret + cookie secret.
// Returns the two values (read back if the secret already exists so the Job + proxy agree).
func (r *reconciler) ensureOrgSecret(ctx context.Context, name, org string) (clientSecret, cookieSecret string, err error) {
	sec := &unstructured.Unstructured{}
	sec.SetGroupVersionKind(schema.GroupVersionKind{Version: "v1", Kind: "Secret"})
	getErr := r.remote.Get(ctx, types.NamespacedName{Namespace: r.cfg.providerNS, Name: name}, sec)
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
			"labels": map[string]interface{}{"app.kubernetes.io/managed-by": "aitrust-federation", "org": org},
		},
		"stringData": map[string]interface{}{"client-secret": clientSecret, "cookie-secret": cookieSecret},
	}}
	if err = r.remote.Create(ctx, sec); err != nil {
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
	if err := r.remote.Get(ctx, types.NamespacedName{Namespace: r.cfg.providerNS, Name: copyName}, dst); err == nil {
		return nil // already copied (on a1)
	}
	src := &unstructured.Unstructured{}
	src.SetGroupVersionKind(schema.GroupVersionKind{Version: "v1", Kind: "Secret"})
	if err := r.remote.Get(ctx, types.NamespacedName{Namespace: r.cfg.meshAdminNS, Name: r.cfg.meshAdminName}, src); err != nil {
		return fmt.Errorf("read mesh admin secret %s/%s: %w", r.cfg.meshAdminNS, r.cfg.meshAdminName, err)
	}
	data, _, _ := unstructured.NestedMap(src.Object, "data") // base64 values, copied verbatim
	copySecret := &unstructured.Unstructured{Object: map[string]interface{}{
		"apiVersion": "v1", "kind": "Secret",
		"metadata": map[string]interface{}{
			"name": copyName, "namespace": r.cfg.providerNS,
			"labels": map[string]interface{}{"app.kubernetes.io/managed-by": "aitrust-federation"},
		},
		"type": "Opaque",
		"data": data,
	}}
	return r.remote.Create(ctx, copySecret)
}

// ---------- LOCAL (prod) helpers for the reciprocal SSO client (Stage 6) -----------------------
// These mirror the remote helpers but use r.Client (the prod cluster), because the prod-side IdP
// client Job runs ON prod (prod's mesh Keycloak is reachable by prod in-cluster DNS).

func (r *reconciler) localApply(ctx context.Context, doc string) error {
	for _, obj := range decodeAll(doc) {
		if obj == nil {
			continue
		}
		if err := r.Patch(ctx, obj, client.Apply, client.ForceOwnership, client.FieldOwner("aitrust-federation")); err != nil {
			return fmt.Errorf("apply(local) %s/%s: %w", obj.GetKind(), obj.GetName(), err)
		}
	}
	return nil
}

func (r *reconciler) localJobExists(ctx context.Context, ns, name string) bool {
	j := &unstructured.Unstructured{}
	j.SetGroupVersionKind(schema.GroupVersionKind{Group: "batch", Version: "v1", Kind: "Job"})
	return r.Get(ctx, types.NamespacedName{Namespace: ns, Name: name}, j) == nil
}

func (r *reconciler) localJobSucceeded(ctx context.Context, ns, name string) bool {
	j := &unstructured.Unstructured{}
	j.SetGroupVersionKind(schema.GroupVersionKind{Group: "batch", Version: "v1", Kind: "Job"})
	if err := r.Get(ctx, types.NamespacedName{Namespace: ns, Name: name}, j); err != nil {
		return false
	}
	s, _, _ := unstructured.NestedInt64(j.Object, "status", "succeeded")
	return s > 0
}

// ensureLocalMeshAdminSecret copies PROD's mesh keycloak-admin into the controller's own ns (local).
func (r *reconciler) ensureLocalMeshAdminSecret(ctx context.Context) error {
	const copyName = "mesh-keycloak-admin"
	dst := &unstructured.Unstructured{}
	dst.SetGroupVersionKind(schema.GroupVersionKind{Version: "v1", Kind: "Secret"})
	if err := r.Get(ctx, types.NamespacedName{Namespace: r.cfg.localNS, Name: copyName}, dst); err == nil {
		return nil
	}
	src := &unstructured.Unstructured{}
	src.SetGroupVersionKind(schema.GroupVersionKind{Version: "v1", Kind: "Secret"})
	if err := r.Get(ctx, types.NamespacedName{Namespace: r.cfg.prodMeshAdminNS, Name: r.cfg.prodMeshAdminName}, src); err != nil {
		return fmt.Errorf("read prod mesh admin secret %s/%s: %w", r.cfg.prodMeshAdminNS, r.cfg.prodMeshAdminName, err)
	}
	data, _, _ := unstructured.NestedMap(src.Object, "data")
	cp := &unstructured.Unstructured{Object: map[string]interface{}{
		"apiVersion": "v1", "kind": "Secret",
		"metadata": map[string]interface{}{"name": copyName, "namespace": r.cfg.localNS,
			"labels": map[string]interface{}{"app.kubernetes.io/managed-by": "aitrust-federation"}},
		"type": "Opaque", "data": data,
	}}
	return r.Create(ctx, cp)
}

// ensureLocalOrgSecret mirrors the a1 per-org broker secret VALUE into the controller's own ns on prod,
// so the prod-side client Job references the SAME client-secret the a1 IdP uses. It reads the value back
// from the a1 (remote) secret and writes it locally. Idempotent.
func (r *reconciler) ensureLocalOrgSecret(ctx context.Context, name, org, clientSecret string) error {
	sec := &unstructured.Unstructured{}
	sec.SetGroupVersionKind(schema.GroupVersionKind{Version: "v1", Kind: "Secret"})
	if err := r.Get(ctx, types.NamespacedName{Namespace: r.cfg.localNS, Name: name}, sec); err == nil {
		return nil // already present locally
	}
	sec = &unstructured.Unstructured{Object: map[string]interface{}{
		"apiVersion": "v1", "kind": "Secret",
		"metadata": map[string]interface{}{"name": name, "namespace": r.cfg.localNS,
			"labels": map[string]interface{}{"app.kubernetes.io/managed-by": "aitrust-federation", "org": org}},
		"stringData": map[string]interface{}{"client-secret": clientSecret},
	}}
	return r.Create(ctx, sec)
}

// readRemoteOrgSecret returns the client-secret value from the a1 (remote) per-org broker secret.
func (r *reconciler) readRemoteOrgSecret(ctx context.Context, name string) (string, error) {
	sec := &unstructured.Unstructured{}
	sec.SetGroupVersionKind(schema.GroupVersionKind{Version: "v1", Kind: "Secret"})
	if err := r.remote.Get(ctx, types.NamespacedName{Namespace: r.cfg.providerNS, Name: name}, sec); err != nil {
		return "", err
	}
	data, _, _ := unstructured.NestedMap(sec.Object, "data")
	return decodeB64(strFrom(data["client-secret"])), nil
}

// reconcileReciprocalSSO stamps (on PROD) the OIDC client in prod realm <baseOrg> that a1's 'prod' IdP
// authenticates against. Best-effort: returns an error the caller logs as non-fatal.
func (r *reconciler) reconcileReciprocalSSO(ctx context.Context, l logr.Logger, org, baseOrg string) error {
	// 1. the shared per-org secret value = the a1 broker secret (so both sides agree).
	brokerSecret := "aitrust-fedbroker-" + org
	sv, err := r.readRemoteOrgSecret(ctx, brokerSecret)
	if err != nil || sv == "" {
		return fmt.Errorf("read a1 broker secret %s: %v", brokerSecret, err)
	}
	// 2. mirror it + the prod mesh-admin into the controller's own ns on prod.
	if err := r.ensureLocalMeshAdminSecret(ctx); err != nil {
		return fmt.Errorf("ensure local prod mesh admin: %w", err)
	}
	localSecret := "aitrust-fedbroker-" + org
	if err := r.ensureLocalOrgSecret(ctx, localSecret, org, sv); err != nil {
		return fmt.Errorf("ensure local broker secret: %w", err)
	}
	// 3. a1's broker callback endpoint (prod's client must allow this redirect).
	//    a1 public Keycloak realm fed-<org> → /broker/prod/endpoint
	redirect := strings.TrimRight(r.cfg.kcPublic, "/") + "/realms/" + org + "/broker/prod/endpoint"
	// 4. stamp the prod-client Job LOCALLY (idempotent). Gate Ready-adjacent on success.
	jobName := dnsSafe("kc-prod-client-" + org)
	if !r.localJobExists(ctx, r.cfg.localNS, jobName) {
		doc := r.render("keycloak-prod-client-job.tmpl", map[string]string{
			"__JOB_NAME__": jobName, "__NS__": r.cfg.localNS, "__ORG__": org, "__BASEORG__": baseOrg,
			"__POOL_LABEL__": r.cfg.poolLabel, "__PROD_KC_INTERNAL__": r.cfg.prodKcInternal,
			"__A1_BROKER_REDIRECT__": redirect, "__CLIENT_ID__": r.cfg.idpClientID,
			"__SECRET_NAME__": localSecret, "__SECRET_KEY__": "client-secret",
		})
		if err := r.localApply(ctx, doc); err != nil {
			return fmt.Errorf("stamp prod-client job: %w", err)
		}
	}
	if !r.localJobSucceeded(ctx, r.cfg.localNS, jobName) {
		return fmt.Errorf("prod-client job %s not yet succeeded (prod realm %s may not exist)", jobName, baseOrg)
	}
	l.Info("reciprocal prod-side SSO client wired", "org", org, "prodRealm", baseOrg, "client", r.cfg.idpClientID)
	return nil
}



// readMeshAdminCreds reads the mesh Keycloak bootstrap-admin username/password directly from the
// SOURCE secret (meshAdminNS/meshAdminName). Used by the realm-existence gate — independent of the
// copy step, so a phantom org is rejected before anything is stamped.
func (r *reconciler) readMeshAdminCreds(ctx context.Context) (user, pass string, err error) {
	src := &unstructured.Unstructured{}
	src.SetGroupVersionKind(schema.GroupVersionKind{Version: "v1", Kind: "Secret"})
	if err = r.remote.Get(ctx, types.NamespacedName{Namespace: r.cfg.meshAdminNS, Name: r.cfg.meshAdminName}, src); err != nil {
		return "", "", fmt.Errorf("read mesh admin secret %s/%s: %w", r.cfg.meshAdminNS, r.cfg.meshAdminName, err)
	}
	data, _, _ := unstructured.NestedMap(src.Object, "data")
	user = decodeB64(strFrom(data["username"]))
	pass = decodeB64(strFrom(data["password"]))
	if user == "" || pass == "" {
		return "", "", fmt.Errorf("mesh admin secret %s/%s missing username/password", r.cfg.meshAdminNS, r.cfg.meshAdminName)
	}
	return user, pass, nil
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
		_ = r.remote.Delete(ctx, o) // REMOTE: teardown happens on ai-trust-1.
	}
	del(schema.GroupVersionKind{Group: "apps", Version: "v1", Kind: "Deployment"}, r.cfg.providerNS, "oauth2-proxy-"+org)
	del(schema.GroupVersionKind{Version: "v1", Kind: "Service"}, r.cfg.providerNS, "oauth2-proxy-"+org)
	del(schema.GroupVersionKind{Group: "gateway.networking.k8s.io", Version: "v1", Kind: "HTTPRoute"}, r.cfg.gatewayNS, "aitrust-"+org)
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
		// REMOTE: provisioning objects are applied on ai-trust-1.
		if err := r.remote.Patch(ctx, obj, client.Apply, client.ForceOwnership, client.FieldOwner("aitrust-federation")); err != nil {
			return fmt.Errorf("apply %s/%s: %w", obj.GetKind(), obj.GetName(), err)
		}
	}
	return nil
}

func (r *reconciler) jobExists(ctx context.Context, ns, name string) bool {
	j := &unstructured.Unstructured{}
	j.SetGroupVersionKind(schema.GroupVersionKind{Group: "batch", Version: "v1", Kind: "Job"})
	return r.remote.Get(ctx, types.NamespacedName{Namespace: ns, Name: name}, j) == nil
}

// jobSucceeded reports whether the named Job has completed successfully (status.succeeded > 0).
// Used to gate a Subscription's Ready state on its per-tenant store provisioning finishing first.
func (r *reconciler) jobSucceeded(ctx context.Context, ns, name string) bool {
	j := &unstructured.Unstructured{}
	j.SetGroupVersionKind(schema.GroupVersionKind{Group: "batch", Version: "v1", Kind: "Job"})
	if err := r.remote.Get(ctx, types.NamespacedName{Namespace: ns, Name: name}, j); err != nil {
		return false
	}
	succeeded, _, _ := unstructured.NestedInt64(j.Object, "status", "succeeded")
	return succeeded > 0
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
		"cluster":            remoteCluster, // federated tile Cluster column — workload lives on ai-trust-1
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

// orgOwner enforces one-subscription-per-org. It returns the Subscription that rightfully OWNS `org`
// when that owner is someone OTHER than `self` (→ caller must Degrade `self` as a duplicate); it returns
// nil when `self` is the rightful owner (or the sole/oldest active sub for the org) → caller proceeds.
//
// Owner = the OLDEST active (non-deleting) Subscription whose normalized spec.org == `org`, by
// metadata.creationTimestamp (RFC3339 UTC strings sort chronologically), uid as a stable tie-break.
// Using oldest-wins (not first-reconciled) keeps the active tenant stable across operator restarts and
// avoids flapping; self-exclusion by uid ensures a Ready sub never Degrades itself on re-reconcile.
func (r *reconciler) orgOwner(ctx context.Context, org string, self *unstructured.Unstructured) *unstructured.Unstructured {
	list := &unstructured.UnstructuredList{}
	list.SetGroupVersionKind(schema.GroupVersionKind{Group: gvk.Group, Version: gvk.Version, Kind: gvk.Kind + "List"})
	if err := r.List(ctx, list); err != nil {
		// Can't verify uniqueness — fail-closed would block ALL provisioning on a transient list error,
		// so instead we log and let the caller proceed (the realm gate + idempotent stamping still apply).
		log.FromContext(ctx).Error(err, "orgOwner: list subscriptions failed — skipping duplicate check")
		return nil
	}
	selfUID := string(self.GetUID())
	var owner *unstructured.Unstructured
	var ownerTS, ownerUID string
	for i := range list.Items {
		it := &list.Items[i]
		if !it.GetDeletionTimestamp().IsZero() {
			continue // being deleted — releases the org
		}
		sp, _, _ := unstructured.NestedMap(it.Object, "spec")
		if dnsSafe(strings.TrimSpace(strOr(sp["org"], ""))) != org {
			continue
		}
		ts := it.GetCreationTimestamp().UTC().Format(time.RFC3339Nano)
		uid := string(it.GetUID())
		if owner == nil || ts < ownerTS || (ts == ownerTS && uid < ownerUID) {
			owner, ownerTS, ownerUID = it, ts, uid
		}
	}
	if owner == nil || ownerUID == selfUID {
		return nil // self is the owner (or no active sub for this org yet)
	}
	return owner
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

	// REMOTE client → ai-trust-1, built from the mounted scoped SA kubeconfig (Stage-1 Secret).
	// All tenant provisioning applies/reads go through this client; the manager's own client (local)
	// stays on prod kcp for the Subscription watch + status.
	remoteCfg, err := clientcmd.BuildConfigFromFlags("", c.remoteKubecfg)
	if err != nil {
		panic(fmt.Errorf("load remote (ai-trust-1) kubeconfig %s: %w", c.remoteKubecfg, err))
	}
	remoteCli, err := client.New(remoteCfg, client.Options{})
	if err != nil {
		panic(fmt.Errorf("build remote (ai-trust-1) client: %w", err))
	}

	proto := &unstructured.Unstructured{}
	proto.SetGroupVersionKind(gvk)
	if err := builder.ControllerManagedBy(mgr).For(proto).Complete(&reconciler{
		Client: mgr.GetClient(), remote: remoteCli, cfg: c,
	}); err != nil {
		panic(err)
	}
	log.Log.Info("aitrust-federation starting", "providerNS(a1)", c.providerNS, "domainSuffix(a1)", c.domainSuffix,
		"gateway(a1)", c.gatewayName, "remoteKubeconfig", c.remoteKubecfg, "group", gvk.Group)
	if err := mgr.Start(signals.SetupSignalHandler()); err != nil {
		panic(err)
	}
}
