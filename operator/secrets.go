package main

import (
	"context"
	"fmt"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
)

// ensureOrgSecret creates (once) a Secret holding the per-org oauth2-proxy client secret + cookie secret.
// Returns the two values (read back if the secret already exists so the Job + proxy agree).
func (r *reconciler) ensureOrgSecret(ctx context.Context, name, org string) (clientSecret, cookieSecret string, err error) {
	sec := &unstructured.Unstructured{}
	sec.SetGroupVersionKind(schema.GroupVersionKind{Version: "v1", Kind: "Secret"})
	getErr := r.remote.Get(ctx, types.NamespacedName{Namespace: r.cfg.providerNS, Name: name}, sec)
	if getErr == nil {
		data, _, _ := unstructured.NestedMap(sec.Object, "data")
		// data values are base64 in the API; controller-runtime returns them as base64 strings.
		cs, err := decodeB64(strFrom(data["client-secret"]))
		if err != nil {
			return "", "", fmt.Errorf("decode client-secret for %s: %w", name, err)
		}
		ck, err := decodeB64(strFrom(data["cookie-secret"]))
		if err != nil {
			return "", "", fmt.Errorf("decode cookie-secret for %s: %w", name, err)
		}
		return cs, ck, nil
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
// so the prod-side client Job references the SAME client-secret the a1 IdP uses. Idempotent.
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
	val, err := decodeB64(strFrom(data["client-secret"]))
	if err != nil {
		return "", fmt.Errorf("decode client-secret for %s: %w", name, err)
	}
	return val, nil
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
	user, err = decodeB64(strFrom(data["username"]))
	if err != nil {
		return "", "", fmt.Errorf("decode username from mesh admin secret: %w", err)
	}
	pass, err = decodeB64(strFrom(data["password"]))
	if err != nil {
		return "", "", fmt.Errorf("decode password from mesh admin secret: %w", err)
	}
	if user == "" || pass == "" {
		return "", "", fmt.Errorf("mesh admin secret %s/%s missing username/password", r.cfg.meshAdminNS, r.cfg.meshAdminName)
	}
	return user, pass, nil
}
