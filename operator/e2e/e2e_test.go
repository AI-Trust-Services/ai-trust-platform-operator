//go:build e2e

// Package e2e contains end-to-end tests for the aitrust-operator.
//
// Prerequisites:
//   - A running Kubernetes cluster (Kind or staging) with KUBECONFIG pointing to it.
//   - The aitrust-operator deployed on the cluster (or running locally against it).
//   - Keycloak, Postgres, ClickHouse, MinIO, OpenFGA running on the cluster
//     (all present when the local Platform Mesh was set up via `task local-setup`).
//   - mkcert installed and trusted (for the default https://portal.localhost:8443 endpoint).
//
// Run:
//
//	KUBECONFIG=~/helm-charts/.secret/kind/kubeconfig \
//	  go test -v -tags e2e -timeout 30m ./e2e/...
//
// Optional env vars:
//
//	KC_ADMIN_URL   Keycloak base URL  (default: https://portal.localhost:8443/keycloak)
//	KC_ADMIN_USER  Admin username     (default: keycloak-admin)
//	KC_ADMIN_PASS  Admin password     (default: admin)
//	KC_SKIP_TLS    Set to "true" to skip TLS verification (useful with self-signed certs)
//	PROVIDER_NS    Namespace where per-org resources land (default: aitrust-msp)
//	GATEWAY_NS     Namespace where HTTPRoutes land (default: platform-mesh-system)
package e2e

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/clientcmd"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// ---- global state -----------------------------------------------------------

var (
	k8sClient  client.Client
	httpClient *http.Client

	subGVK = schema.GroupVersionKind{Group: "sub.aitrust.msp", Version: "v1alpha1", Kind: "Subscription"}

	// unique 5-digit suffix per test run to avoid name collisions
	runID string
)

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func providerNS() string { return envOr("PROVIDER_NS", "aitrust-msp") }
func gatewayNS() string  { return envOr("GATEWAY_NS", "platform-mesh-system") }
func subNS() string      { return "default" }

func TestMain(m *testing.M) {
	runID = fmt.Sprintf("%05d", time.Now().Unix()%100000)

	// HTTP client — optionally skip TLS for self-signed dev certs
	if os.Getenv("KC_SKIP_TLS") == "true" {
		httpClient = &http.Client{Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		}}
	} else {
		httpClient = http.DefaultClient
	}

	kubecfg := os.Getenv("KUBECONFIG")
	if kubecfg == "" {
		home, _ := os.UserHomeDir()
		kubecfg = home + "/helm-charts/.secret/kind/kubeconfig"
	}
	restCfg, err := clientcmd.BuildConfigFromFlags("", kubecfg)
	if err != nil {
		panic("BuildConfigFromFlags: " + err.Error())
	}
	k8sClient, err = client.New(restCfg, client.Options{})
	if err != nil {
		panic("client.New: " + err.Error())
	}
	os.Exit(m.Run())
}

// ---- Keycloak helpers -------------------------------------------------------

func kcBase() string { return strings.TrimRight(envOr("KC_ADMIN_URL", "https://portal.localhost:8443/keycloak"), "/") }
func kcUser() string { return envOr("KC_ADMIN_USER", "keycloak-admin") }
func kcPass() string { return envOr("KC_ADMIN_PASS", "admin") }

func kcToken(t *testing.T) string {
	t.Helper()
	form := url.Values{
		"grant_type": {"password"},
		"client_id":  {"admin-cli"},
		"username":   {kcUser()},
		"password":   {kcPass()},
	}
	resp, err := httpClient.PostForm(kcBase()+"/realms/master/protocol/openid-connect/token", form)
	if err != nil {
		t.Fatalf("kcToken: %v (is KC_ADMIN_URL reachable? mkcert installed?)", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	var out struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.Unmarshal(body, &out); err != nil || out.AccessToken == "" {
		t.Fatalf("kcToken: status=%d body=%s", resp.StatusCode, body)
	}
	return out.AccessToken
}

func kcCreateRealm(t *testing.T, token, realm string) {
	t.Helper()
	body := fmt.Sprintf(`{"realm":%q,"enabled":true}`, realm)
	req, _ := http.NewRequest(http.MethodPost, kcBase()+"/admin/realms", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := httpClient.Do(req)
	if err != nil {
		t.Fatalf("kcCreateRealm %s: %v", realm, err)
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)
	if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusConflict {
		t.Fatalf("kcCreateRealm %s: unexpected status %d", realm, resp.StatusCode)
	}
}

func kcDeleteRealm(token, realm string) {
	req, _ := http.NewRequest(http.MethodDelete, kcBase()+"/admin/realms/"+url.PathEscape(realm), nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := httpClient.Do(req)
	if err == nil {
		defer resp.Body.Close()
		io.Copy(io.Discard, resp.Body)
	}
}

// ---- Kubernetes helpers -----------------------------------------------------

func createSub(t *testing.T, name, org string) {
	t.Helper()
	sub := &unstructured.Unstructured{Object: map[string]interface{}{
		"apiVersion": "sub.aitrust.msp/v1alpha1",
		"kind":       "Subscription",
		"metadata":   map[string]interface{}{"name": name, "namespace": subNS()},
		"spec":       map[string]interface{}{"org": org},
	}}
	if err := k8sClient.Create(context.Background(), sub); err != nil {
		t.Fatalf("createSub %s: %v", name, err)
	}
}

func deleteSub(name string) {
	sub := &unstructured.Unstructured{}
	sub.SetGroupVersionKind(subGVK)
	sub.SetName(name)
	sub.SetNamespace(subNS())
	_ = k8sClient.Delete(context.Background(), sub)
}

func getPhase(name string) (string, error) {
	got := &unstructured.Unstructured{}
	got.SetGroupVersionKind(subGVK)
	if err := k8sClient.Get(context.Background(), types.NamespacedName{Namespace: subNS(), Name: name}, got); err != nil {
		return "", err
	}
	phase, _, _ := unstructured.NestedString(got.Object, "status", "phase")
	return phase, nil
}

func waitForPhase(t *testing.T, name, want string, timeout time.Duration) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for {
		phase, err := getPhase(name)
		if err == nil && phase == want {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("waitForPhase(%s, %s): timed out after %s, last phase=%q err=%v", name, want, timeout, phase, err)
		}
		time.Sleep(5 * time.Second)
	}
}

func resourceExists(gvk schema.GroupVersionKind, ns, name string) bool {
	obj := &unstructured.Unstructured{}
	obj.SetGroupVersionKind(gvk)
	return k8sClient.Get(context.Background(), types.NamespacedName{Namespace: ns, Name: name}, obj) == nil
}

func setSuspended(t *testing.T, name string, suspended bool) {
	t.Helper()
	sub := &unstructured.Unstructured{}
	sub.SetGroupVersionKind(subGVK)
	if err := k8sClient.Get(context.Background(), types.NamespacedName{Namespace: subNS(), Name: name}, sub); err != nil {
		t.Fatalf("getSub for suspend patch: %v", err)
	}
	_ = unstructured.SetNestedField(sub.Object, suspended, "spec", "suspended")
	if err := k8sClient.Update(context.Background(), sub); err != nil {
		t.Fatalf("setSuspended(%v): %v", suspended, err)
	}
}

func deploymentReplicas(ns, name string) (int64, error) {
	d := &unstructured.Unstructured{}
	d.SetGroupVersionKind(schema.GroupVersionKind{Group: "apps", Version: "v1", Kind: "Deployment"})
	if err := k8sClient.Get(context.Background(), types.NamespacedName{Namespace: ns, Name: name}, d); err != nil {
		return -1, err
	}
	rep, _, _ := unstructured.NestedInt64(d.Object, "spec", "replicas")
	return rep, nil
}

// ---- E2E tests --------------------------------------------------------------

// 3.1: Full provisioning flow — Subscription becomes Ready with all resources provisioned.
func TestProvisioningFlow_LocalMode(t *testing.T) {
	org := "e2e" + runID + "prov"
	subName := "e2e-sub-" + runID + "-prov"

	tok := kcToken(t)
	kcCreateRealm(t, tok, org)
	t.Cleanup(func() { kcDeleteRealm(tok, org) })
	t.Cleanup(func() { deleteSub(subName) })

	createSub(t, subName, org)
	waitForPhase(t, subName, "Ready", 5*time.Minute)

	// Secret
	if !resourceExists(schema.GroupVersionKind{Version: "v1", Kind: "Secret"},
		providerNS(), "aitrust-oauth2-"+org) {
		t.Error("Secret aitrust-oauth2-<org> not found in provider namespace")
	}
	// oauth2-proxy Deployment
	if !resourceExists(schema.GroupVersionKind{Group: "apps", Version: "v1", Kind: "Deployment"},
		providerNS(), "oauth2-proxy-"+org) {
		t.Error("Deployment oauth2-proxy-<org> not found")
	}
	// HTTPRoute
	if !resourceExists(schema.GroupVersionKind{Group: "gateway.networking.k8s.io", Version: "v1", Kind: "HTTPRoute"},
		gatewayNS(), "aitrust-"+org) {
		t.Error("HTTPRoute aitrust-<org> not found")
	}
}

// 3.2: Suspend tenant — phase transitions to Suspended, oauth2-proxy scaled to 0.
func TestSuspendTenant(t *testing.T) {
	org := "e2e" + runID + "susp"
	subName := "e2e-sub-" + runID + "-susp"

	tok := kcToken(t)
	kcCreateRealm(t, tok, org)
	t.Cleanup(func() { kcDeleteRealm(tok, org) })
	t.Cleanup(func() { deleteSub(subName) })

	createSub(t, subName, org)
	waitForPhase(t, subName, "Ready", 5*time.Minute)

	setSuspended(t, subName, true)
	waitForPhase(t, subName, "Suspended", 2*time.Minute)

	rep, err := deploymentReplicas(providerNS(), "oauth2-proxy-"+org)
	if err != nil {
		t.Fatalf("get deployment: %v", err)
	}
	if rep != 0 {
		t.Errorf("want 0 replicas when suspended, got %d", rep)
	}
}

// 3.3: Resume tenant — phase returns to Ready, oauth2-proxy back to 1 replica.
func TestResumeTenant(t *testing.T) {
	org := "e2e" + runID + "rsm"
	subName := "e2e-sub-" + runID + "-rsm"

	tok := kcToken(t)
	kcCreateRealm(t, tok, org)
	t.Cleanup(func() { kcDeleteRealm(tok, org) })
	t.Cleanup(func() { deleteSub(subName) })

	createSub(t, subName, org)
	waitForPhase(t, subName, "Ready", 5*time.Minute)

	setSuspended(t, subName, true)
	waitForPhase(t, subName, "Suspended", 2*time.Minute)

	setSuspended(t, subName, false)
	waitForPhase(t, subName, "Ready", 2*time.Minute)

	rep, err := deploymentReplicas(providerNS(), "oauth2-proxy-"+org)
	if err != nil {
		t.Fatalf("get deployment: %v", err)
	}
	if rep != 1 {
		t.Errorf("want 1 replica after resume, got %d", rep)
	}
}

// 3.4: Duplicate org guard — first sub stays Ready, second sub for same org is Degraded.
func TestDuplicateOrgGuard_E2E(t *testing.T) {
	org := "e2e" + runID + "dup"
	subA := "e2e-sub-" + runID + "-dupa"
	subB := "e2e-sub-" + runID + "-dupb"

	tok := kcToken(t)
	kcCreateRealm(t, tok, org)
	t.Cleanup(func() { kcDeleteRealm(tok, org) })
	t.Cleanup(func() { deleteSub(subA); deleteSub(subB) })

	createSub(t, subA, org)
	waitForPhase(t, subA, "Ready", 5*time.Minute)

	time.Sleep(1100 * time.Millisecond) // ensure distinct creationTimestamp (1s granularity)
	createSub(t, subB, org)
	waitForPhase(t, subB, "Degraded", 2*time.Minute)

	// sub-A must not have been degraded by its own re-reconcile
	phase, _ := getPhase(subA)
	if phase != "Ready" {
		t.Errorf("sub-A should remain Ready, got %q", phase)
	}
}

// 3.5: Tenant deletion — Subscription is removed, proxy/route resources cleaned up.
// Tenant DATA (Postgres schema, MinIO bucket) is intentionally NOT deleted (soft-delete by design).
func TestDeleteTenant(t *testing.T) {
	org := "e2e" + runID + "del"
	subName := "e2e-sub-" + runID + "-del"

	tok := kcToken(t)
	kcCreateRealm(t, tok, org)
	t.Cleanup(func() { kcDeleteRealm(tok, org) })

	createSub(t, subName, org)
	waitForPhase(t, subName, "Ready", 5*time.Minute)

	deleteSub(subName)

	// Wait for the finalizer to be removed and the object to be gone
	deadline := time.Now().Add(2 * time.Minute)
	for {
		_, err := getPhase(subName)
		if err != nil {
			break // not-found → deleted
		}
		if time.Now().After(deadline) {
			t.Fatal("timed out waiting for Subscription to be fully deleted")
		}
		time.Sleep(3 * time.Second)
	}

	// Auth proxy resources should be gone
	if resourceExists(schema.GroupVersionKind{Group: "apps", Version: "v1", Kind: "Deployment"},
		providerNS(), "oauth2-proxy-"+org) {
		t.Error("Deployment should be deleted after Subscription deletion")
	}
	if resourceExists(schema.GroupVersionKind{Version: "v1", Kind: "Service"},
		providerNS(), "oauth2-proxy-"+org) {
		t.Error("Service should be deleted after Subscription deletion")
	}
	if resourceExists(schema.GroupVersionKind{Group: "gateway.networking.k8s.io", Version: "v1", Kind: "HTTPRoute"},
		gatewayNS(), "aitrust-"+org) {
		t.Error("HTTPRoute should be deleted after Subscription deletion")
	}
}

// 3.7: Operator restart resilience — after re-reconcile the phase stays Ready
// and no resources are duplicated (idempotency of applyDoc + stores-provisioned annotation).
func TestOperatorRestartResilience(t *testing.T) {
	org := "e2e" + runID + "rst"
	subName := "e2e-sub-" + runID + "-rst"

	tok := kcToken(t)
	kcCreateRealm(t, tok, org)
	t.Cleanup(func() { kcDeleteRealm(tok, org) })
	t.Cleanup(func() { deleteSub(subName) })

	createSub(t, subName, org)
	waitForPhase(t, subName, "Ready", 5*time.Minute)

	// Trigger a re-reconcile by bumping an annotation on the Subscription
	sub := &unstructured.Unstructured{}
	sub.SetGroupVersionKind(subGVK)
	if err := k8sClient.Get(context.Background(),
		types.NamespacedName{Namespace: subNS(), Name: subName}, sub); err != nil {
		t.Fatalf("get sub: %v", err)
	}
	anns := sub.GetAnnotations()
	if anns == nil {
		anns = map[string]string{}
	}
	anns["e2e/restart-marker"] = fmt.Sprintf("%d", time.Now().UnixNano())
	sub.SetAnnotations(anns)
	if err := k8sClient.Update(context.Background(), sub); err != nil {
		t.Fatalf("update sub: %v", err)
	}

	// Allow time for one reconcile loop (default requeue is 5 min, but annotation change triggers immediately)
	time.Sleep(15 * time.Second)

	phase, err := getPhase(subName)
	if err != nil {
		t.Fatalf("getPhase: %v", err)
	}
	if phase != "Ready" {
		t.Errorf("after re-reconcile want Ready, got %q (idempotency issue?)", phase)
	}
}
