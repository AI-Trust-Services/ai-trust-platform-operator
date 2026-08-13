package main

import (
	"context"
	"encoding/base64"
	"io"
	"net/http"
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
