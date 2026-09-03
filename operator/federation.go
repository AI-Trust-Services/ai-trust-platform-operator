package main

import (
	"context"
	"fmt"
	"strings"

	"github.com/go-logr/logr"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

// ---------- LOCAL (prod) helpers for the reciprocal SSO client -----------------------
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

// reconcileReciprocalSSO stamps (on PROD) the OIDC client in prod realm <baseOrg> that a1's 'prod' IdP
// authenticates against. Best-effort: returns an error the caller logs as non-fatal.
func (r *reconciler) reconcileReciprocalSSO(ctx context.Context, l logr.Logger, org, baseOrg string) error {
	brokerSecret := "aitrust-fedbroker-" + org
	sv, err := r.readRemoteOrgSecret(ctx, brokerSecret)
	if err != nil || sv == "" {
		return fmt.Errorf("read a1 broker secret %s: %v", brokerSecret, err)
	}
	if err := r.ensureLocalMeshAdminSecret(ctx); err != nil {
		return fmt.Errorf("ensure local prod mesh admin: %w", err)
	}
	localSecret := "aitrust-fedbroker-" + org
	if err := r.ensureLocalOrgSecret(ctx, localSecret, org, sv); err != nil {
		return fmt.Errorf("ensure local broker secret: %w", err)
	}
	// a1's broker callback endpoint (prod's client must allow this redirect).
	// a1 public Keycloak realm fed-<org> → /broker/prod/endpoint
	redirect := strings.TrimRight(r.cfg.kcPublic, "/") + "/realms/" + org + "/broker/prod/endpoint"
	jobName := dnsSafe("kc-prod-client-" + org)
	if !r.localJobExists(ctx, r.cfg.localNS, jobName) {
		doc, err := r.render("keycloak-prod-client-job.tmpl", map[string]string{
			"__JOB_NAME__": jobName, "__NS__": r.cfg.localNS, "__ORG__": org, "__BASEORG__": baseOrg,
			"__POOL_LABEL__": r.cfg.poolLabel, "__PROD_KC_INTERNAL__": r.cfg.prodKcInternal,
			"__A1_BROKER_REDIRECT__": redirect, "__CLIENT_ID__": r.cfg.idpClientID,
			"__SECRET_NAME__": localSecret, "__SECRET_KEY__": "client-secret",
		})
		if err != nil {
			return fmt.Errorf("render prod-client job: %w", err)
		}
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

// seedAdminTuple writes user:<email> → member → role:platform_administrator to the shared OpenFGA store.
func (r *reconciler) seedAdminTuple(ctx context.Context, email string) error {
	body := fmt.Sprintf(`{"writes":{"tuple_keys":[{"user":"user:%s","relation":"member","object":"role:platform_administrator"}]}}`, email)
	req := r.cfg.openfgaURL + "/stores/" + r.cfg.storeID + "/write"
	return httpPost(ctx, req, body)
}
