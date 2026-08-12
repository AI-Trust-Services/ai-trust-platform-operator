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
