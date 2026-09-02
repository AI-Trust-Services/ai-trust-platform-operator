package main

import (
	"context"
	"fmt"
	"strings"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func (r *reconciler) render(tmpl string, repl map[string]string) (string, error) {
	b, err := manifestFS.ReadFile("manifests/" + tmpl)
	if err != nil {
		return "", err
	}
	s := string(b)
	for k, v := range repl {
		s = strings.ReplaceAll(s, k, v)
	}
	if i := strings.Index(s, "__"); i >= 0 {
		rest := s[i+2:]
		if j := strings.Index(rest, "__"); j >= 0 {
			return "", fmt.Errorf("render %s: unresolved token %q", tmpl, s[i:i+2+j+2])
		}
	}
	return s, nil
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

// markProvisioned stamps a durable annotation on the (local, Central) Subscription recording that its
// per-tenant stores on the payload cluster have been provisioned, so the controller never re-stamps the
// TTL-deleted tenant-stores Job for an already-provisioned tenant. Uses the LOCAL client (the Subscription
// lives on Central). Refetches latest to avoid a stale-write conflict.
func (r *reconciler) markProvisioned(ctx context.Context, cr *unstructured.Unstructured, ann string) error {
	latest := &unstructured.Unstructured{}
	latest.SetGroupVersionKind(gvk)
	if err := r.Get(ctx, types.NamespacedName{Namespace: cr.GetNamespace(), Name: cr.GetName()}, latest); err != nil {
		return err
	}
	anns := latest.GetAnnotations()
	if anns == nil {
		anns = map[string]string{}
	}
	if anns[ann] == "true" {
		return nil
	}
	anns[ann] = "true"
	latest.SetAnnotations(anns)
	if err := r.Update(ctx, latest); err != nil {
		return err
	}
	cr.SetAnnotations(anns)
	return nil
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
