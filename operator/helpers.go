package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// decodeB64 decodes a base64 secret value (Secret .data values are base64-encoded in the API).
func decodeB64(s string) string {
	if s == "" {
		return ""
	}
	b, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return s // already plain (e.g. from stringData round-trip)
	}
	return string(b)
}

// httpPost writes a tuple to OpenFGA. Treats 200 and 400 (already-exists / duplicate) as success;
// anything else is an error. Used only for best-effort admin-tuple seeding.
func httpPost(ctx context.Context, url, body string) error {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	if resp.StatusCode == http.StatusOK || resp.StatusCode == http.StatusBadRequest {
		return nil // 400 = tuple already present → idempotent success
	}
	return &httpError{code: resp.StatusCode}
}

type httpError struct{ code int }

func (e *httpError) Error() string { return "openfga write http " + itoa(e.code) }

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	return string(b)
}

// ---- mesh Keycloak realm validation (gate before provisioning) ---------------------

type realmCheck int

const (
	realmExists realmCheck = iota
	realmMissing
	realmUnknown // token/network/5xx/parse — inconclusive; caller must fail-closed (not provision)
)

// kcAdminToken gets an admin access token from the mesh Keycloak (master realm), mirroring the
// token flow used by manifests/keycloak-client-job.tmpl. kcBase is e.g.
// http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak
func kcAdminToken(ctx context.Context, kcBase, user, pass string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	form := url.Values{
		"grant_type": {"password"},
		"client_id":  {"admin-cli"},
		"username":   {user},
		"password":   {pass},
	}
	endpoint := strings.TrimRight(kcBase, "/") + "/realms/master/protocol/openid-connect/token"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		_, _ = io.Copy(io.Discard, resp.Body)
		return "", fmt.Errorf("keycloak admin token http %d", resp.StatusCode)
	}
	var out struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", err
	}
	if out.AccessToken == "" {
		return "", fmt.Errorf("keycloak admin token empty")
	}
	return out.AccessToken, nil
}

// checkRealmExists returns whether the mesh Keycloak realm <org> exists. Fail-closed: any
// inconclusive result (transport error, 5xx, unexpected status) → realmUnknown, and the caller
// must NOT provision on realmUnknown.
func checkRealmExists(ctx context.Context, kcBase, token, org string) realmCheck {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	endpoint := strings.TrimRight(kcBase, "/") + "/admin/realms/" + url.PathEscape(org)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return realmUnknown
	}
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return realmUnknown
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	switch resp.StatusCode {
	case http.StatusOK:
		return realmExists
	case http.StatusNotFound:
		return realmMissing
	default:
		return realmUnknown
	}
}
