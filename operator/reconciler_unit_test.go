package main

import (
	"context"
	"testing"
	"time"

	"github.com/go-logr/logr"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func init() {
	ctrl.SetLogger(logr.Discard())
}

func newFakeReconciler(objs ...client.Object) *reconciler {
	fc := fake.NewClientBuilder().WithObjects(objs...).Build()
	c := cfg()
	c.providerNS = "default"
	c.meshAdminNS = "default"
	c.meshAdminName = "keycloak-admin"
	return &reconciler{Client: fc, remote: fc, cfg: c}
}

func newSubObj(name, org string) *unstructured.Unstructured {
	u := &unstructured.Unstructured{}
	u.SetGroupVersionKind(gvk)
	u.SetName(name)
	u.SetNamespace("default")
	_ = unstructured.SetNestedField(u.Object, org, "spec", "org")
	return u
}

// TestReconcile_Unit_NotFound: a missing CR returns success (IgnoreNotFound).
func TestReconcile_Unit_NotFound(t *testing.T) {
	r := newFakeReconciler()
	result, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: types.NamespacedName{Namespace: "default", Name: "nonexistent"},
	})
	if err != nil {
		t.Errorf("want nil error for not-found CR, got %v", err)
	}
	if result != (ctrl.Result{}) {
		t.Errorf("want empty result for not-found CR, got %v", result)
	}
}

// TestReconcile_Unit_AddsFinalizer: first reconcile on a new CR adds the finalizer.
func TestReconcile_Unit_AddsFinalizer(t *testing.T) {
	sub := newSubObj("sub-unit-nofinalizer", "acme")
	r := newFakeReconciler(sub)

	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: types.NamespacedName{Namespace: "default", Name: "sub-unit-nofinalizer"},
	}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}

	got := &unstructured.Unstructured{}
	got.SetGroupVersionKind(gvk)
	if err := r.Get(context.Background(), types.NamespacedName{Namespace: "default", Name: "sub-unit-nofinalizer"}, got); err != nil {
		t.Fatalf("get after reconcile: %v", err)
	}
	if !hasFinalizer(got) {
		t.Error("finalizer not added after first reconcile")
	}
}

// TestReconcile_Unit_EmptyOrg_Degrades: a CR with empty spec.org requeues after 30s.
func TestReconcile_Unit_EmptyOrg_Degrades(t *testing.T) {
	sub := newSubObj("sub-unit-emptyorg", "")
	addFinalizer(sub) // skip the finalizer-add step
	r := newFakeReconciler(sub)

	result, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: types.NamespacedName{Namespace: "default", Name: "sub-unit-emptyorg"},
	})
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if result.RequeueAfter != 30*time.Second {
		t.Errorf("want RequeueAfter=30s for empty org, got %v", result.RequeueAfter)
	}
}

// TestReconcile_Unit_Deletion_RemovesFinalizer: deleting a CR with a finalizer removes the finalizer.
// The fake client sets DeletionTimestamp (instead of deleting) when finalizers are present.
func TestReconcile_Unit_Deletion_RemovesFinalizer(t *testing.T) {
	sub := newSubObj("sub-unit-delete", "acme")
	addFinalizer(sub)
	r := newFakeReconciler(sub)

	// Fake client sets DeletionTimestamp when deleting an object that still has finalizers.
	if err := r.Delete(context.Background(), sub); err != nil {
		t.Fatalf("delete: %v", err)
	}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{
		NamespacedName: types.NamespacedName{Namespace: "default", Name: "sub-unit-delete"},
	}); err != nil {
		t.Fatalf("reconcile after delete: %v", err)
	}

	got := &unstructured.Unstructured{}
	got.SetGroupVersionKind(gvk)
	err := r.Get(context.Background(), types.NamespacedName{Namespace: "default", Name: "sub-unit-delete"}, got)
	if err == nil && hasFinalizer(got) {
		t.Error("finalizer should be removed after deletion reconcile")
	}
}
