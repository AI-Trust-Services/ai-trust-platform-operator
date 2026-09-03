//go:build integration

package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/go-logr/logr"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/envtest"
)

const testNS = "default"

var (
	k8sClient client.Client
	testEnv   *envtest.Environment
)

func TestMain(m *testing.M) {
	ctrl.SetLogger(logr.Discard())

	crdPath := filepath.Join("..", "charts", "aitrust-app", "crds")
	testEnv = &envtest.Environment{
		CRDDirectoryPaths:     []string{crdPath},
		ErrorIfCRDPathMissing: true,
	}
	restCfg, err := testEnv.Start()
	if err != nil {
		panic("envtest.Start: " + err.Error())
	}
	k8sClient, err = client.New(restCfg, client.Options{})
	if err != nil {
		panic("client.New: " + err.Error())
	}
	code := m.Run()
	_ = testEnv.Stop()
	os.Exit(code)
}

// newTestReconciler returns a reconciler wired to the envtest k8s client.
// providerNS is set to "default" so tests don't need to create extra namespaces.
func newTestReconciler() *reconciler {
	c := cfg()
	c.providerNS = testNS
	c.meshAdminNS = testNS
	c.meshAdminName = "keycloak-admin"
	return &reconciler{Client: k8sClient, remote: k8sClient, cfg: c}
}

func newSub(name, org string) *unstructured.Unstructured {
	return &unstructured.Unstructured{Object: map[string]interface{}{
		"apiVersion": "sub.aitrust.msp/v1alpha1",
		"kind":       "Subscription",
		"metadata": map[string]interface{}{
			"name":      name,
			"namespace": testNS,
		},
		"spec": map[string]interface{}{
			"org": org,
		},
	}}
}

func getSub(t *testing.T, name string) *unstructured.Unstructured {
	t.Helper()
	got := &unstructured.Unstructured{}
	got.SetGroupVersionKind(gvk)
	if err := k8sClient.Get(context.Background(), types.NamespacedName{Namespace: testNS, Name: name}, got); err != nil {
		t.Fatalf("get %s: %v", name, err)
	}
	return got
}

// 2.1 + 2.2: empty spec.org — reconcile adds finalizer then sets Degraded (no Keycloak needed).
func TestReconcile_EmptyOrg_AddsFinalizer_ThenDegrades(t *testing.T) {
	ctx := context.Background()

	sub := newSub("sub-emptyorg", "")
	if err := k8sClient.Create(ctx, sub); err != nil {
		t.Fatalf("create: %v", err)
	}
	t.Cleanup(func() { _ = k8sClient.Delete(ctx, sub) })

	r := newTestReconciler()
	if _, err := r.Reconcile(ctx, ctrl.Request{
		NamespacedName: types.NamespacedName{Namespace: testNS, Name: "sub-emptyorg"},
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := getSub(t, "sub-emptyorg")

	// 2.1: finalizer must be present after first reconcile
	if !hasFinalizer(got) {
		t.Error("2.1: finalizer not added by reconcile")
	}

	// 2.2: status.phase must be Degraded (empty org → no provisioning)
	phase, _, _ := unstructured.NestedString(got.Object, "status", "phase")
	if phase != "Degraded" {
		t.Errorf("2.2: want status.phase=Degraded, got %q", phase)
	}
	conds, _, _ := unstructured.NestedSlice(got.Object, "status", "conditions")
	if len(conds) == 0 {
		t.Error("2.2: want at least one status condition")
	}
}

// 2.3: duplicate org guard — second subscription claiming the same org is Degraded.
// The older subscription is the rightful owner; orgOwner returns it for the newer one.
func TestReconcile_DuplicateOrg_Degrades(t *testing.T) {
	ctx := context.Background()

	subA := newSub("sub-dup-a", "duporg")
	if err := k8sClient.Create(ctx, subA); err != nil {
		t.Fatalf("create sub-a: %v", err)
	}
	t.Cleanup(func() { _ = k8sClient.Delete(ctx, subA) })

	// k8s creationTimestamp has 1-second granularity; sleep ensures sub-A is strictly older.
	time.Sleep(1100 * time.Millisecond)

	subB := newSub("sub-dup-b", "duporg")
	if err := k8sClient.Create(ctx, subB); err != nil {
		t.Fatalf("create sub-b: %v", err)
	}
	t.Cleanup(func() { _ = k8sClient.Delete(ctx, subB) })

	r := newTestReconciler()

	// Reconciling sub-B: orgOwner finds sub-A (older) → sub-B is Degraded as duplicate.
	if _, err := r.Reconcile(ctx, ctrl.Request{
		NamespacedName: types.NamespacedName{Namespace: testNS, Name: "sub-dup-b"},
	}); err != nil {
		t.Fatalf("reconcile sub-b: %v", err)
	}

	got := getSub(t, "sub-dup-b")
	phase, _, _ := unstructured.NestedString(got.Object, "status", "phase")
	if phase != "Degraded" {
		t.Errorf("want Degraded (duplicate guard), got %q", phase)
	}

	// sub-A re-reconcile should NOT Degrade itself (self-exclusion by UID)
	if _, err := r.Reconcile(ctx, ctrl.Request{
		NamespacedName: types.NamespacedName{Namespace: testNS, Name: "sub-dup-a"},
	}); err != nil {
		t.Fatalf("reconcile sub-a: %v", err)
	}
	gotA := getSub(t, "sub-dup-a")
	phaseA, _, _ := unstructured.NestedString(gotA.Object, "status", "phase")
	if phaseA == "Degraded" {
		// Only Degraded for duplicate guard message — check the condition message
		conds, _, _ := unstructured.NestedSlice(gotA.Object, "status", "conditions")
		if len(conds) > 0 {
			if c, ok := conds[0].(map[string]interface{}); ok {
				if msg := strFrom(c["message"]); msg != "" && contains(msg, "already has an active subscription") {
					t.Errorf("sub-A Degraded itself as duplicate (self-exclusion bug): %s", msg)
				}
			}
		}
	}
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || len(s) > 0 && containsStr(s, sub))
}

func containsStr(s, sub string) bool {
	for i := 0; i <= len(s)-len(sub); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}

// 2.6: ensureOrgSecret is idempotent — second call returns the same values as the first.
func TestEnsureOrgSecret_Idempotent(t *testing.T) {
	ctx := context.Background()
	r := newTestReconciler()

	cs1, ck1, err := r.ensureOrgSecret(ctx, "test-oauth2-idempotent", "idempotentorg")
	if err != nil {
		t.Fatalf("first call: %v", err)
	}
	if cs1 == "" || ck1 == "" {
		t.Fatal("first call returned empty secrets")
	}

	cs2, ck2, err := r.ensureOrgSecret(ctx, "test-oauth2-idempotent", "idempotentorg")
	if err != nil {
		t.Fatalf("second call: %v", err)
	}
	if cs1 != cs2 {
		t.Errorf("client-secret changed on second call: %q → %q", cs1, cs2)
	}
	if ck1 != ck2 {
		t.Errorf("cookie-secret changed on second call: %q → %q", ck1, ck2)
	}
}

// 2.10: setPhase writes status.phase, status.ready, and conditions correctly.
func TestSetPhase(t *testing.T) {
	ctx := context.Background()
	r := newTestReconciler()

	sub := newSub("sub-setphase", "phaseorg")
	if err := k8sClient.Create(ctx, sub); err != nil {
		t.Fatalf("create: %v", err)
	}
	t.Cleanup(func() { _ = k8sClient.Delete(ctx, sub) })

	r.setPhase(ctx, sub, "Ready", true,
		"https://ai-trust-phaseorg.example.com", "phaseorg", "phaseorg", "all good")

	got := getSub(t, "sub-setphase")

	phase, _, _ := unstructured.NestedString(got.Object, "status", "phase")
	if phase != "Ready" {
		t.Errorf("status.phase: want Ready, got %q", phase)
	}
	ready, _, _ := unstructured.NestedBool(got.Object, "status", "ready")
	if !ready {
		t.Error("status.ready: want true")
	}
	conds, _, _ := unstructured.NestedSlice(got.Object, "status", "conditions")
	if len(conds) == 0 {
		t.Error("status.conditions: want at least one condition")
	}
	if len(conds) > 0 {
		c, ok := conds[0].(map[string]interface{})
		if !ok {
			t.Fatal("conditions[0] is not a map")
		}
		if strFrom(c["type"]) != "Ready" {
			t.Errorf("conditions[0].type: want Ready, got %q", strFrom(c["type"]))
		}
		if strFrom(c["status"]) != "True" {
			t.Errorf("conditions[0].status: want True, got %q", strFrom(c["status"]))
		}
		if strFrom(c["reason"]) != "Ready" {
			t.Errorf("conditions[0].reason: want Ready, got %q", strFrom(c["reason"]))
		}
	}
}
