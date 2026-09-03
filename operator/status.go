package main

import (
	"context"
	"fmt"
	"strings"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

func (r *reconciler) setPhase(ctx context.Context, cr *unstructured.Unstructured, phase string, ready bool, url, tenantID, realm, msg string) {
	latest := &unstructured.Unstructured{}
	latest.SetGroupVersionKind(gvk)
	if err := r.Get(ctx, types.NamespacedName{Namespace: cr.GetNamespace(), Name: cr.GetName()}, latest); err != nil {
		return
	}
	transitionTime := time.Now().UTC().Format(time.RFC3339)
	if existing, _, _ := unstructured.NestedSlice(latest.Object, "status", "conditions"); len(existing) > 0 {
		for _, c := range existing {
			cm, ok := c.(map[string]interface{})
			if !ok {
				continue
			}
			if strFrom(cm["type"]) == "Ready" &&
				strFrom(cm["status"]) == boolStr(ready) &&
				strFrom(cm["reason"]) == phase {
				if t := strFrom(cm["lastTransitionTime"]); t != "" {
					transitionTime = t
				}
				break
			}
		}
	}

	st := map[string]interface{}{
		"ready": ready, "phase": phase, "url": url, "tenantId": tenantID, "realm": realm,
		"cluster":            remoteCluster, // federated tile Cluster column — workload lives on the payload cluster
		"observedGeneration": latest.GetGeneration(),
		"conditions": []interface{}{map[string]interface{}{
			"type": "Ready", "status": boolStr(ready), "reason": phase,
			"message": msg, "lastTransitionTime": transitionTime,
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
