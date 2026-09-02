package main

import (
	"regexp"
	"strings"
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

// ---- dnsSafe ----------------------------------------------------------------

func TestDnsSafe(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{"lowercase", "ACME", "acme"},
		{"spaces to dashes", "Hello World", "hello-world"},
		{"underscores to dashes", "acme_corp", "acme-corp"},
		{"special chars", "acme@corp.eu", "acme-corp-eu"},
		{"leading trailing dashes", "-acme-", "acme"},
		{"empty string", "", ""},
		{"only special chars", "@@@", ""},
		{"already valid", "acme", "acme"},
		{"mixed", "My Org_Name!", "my-org-name"},
		{"long string truncated", strings.Repeat("a", 70), strings.Repeat("a", 60)},
		{"long string no trailing dash", strings.Repeat("a", 59) + "-extra", strings.Repeat("a", 59)},
		{"numbers ok", "org123", "org123"},
		{"fed prefix pattern", "fed-acme", "fed-acme"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := dnsSafe(tt.input)
			if got != tt.want {
				t.Errorf("dnsSafe(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

func TestDnsSafeMaxLength(t *testing.T) {
	input := strings.Repeat("x", 70)
	got := dnsSafe(input)
	if len(got) > 60 {
		t.Errorf("dnsSafe output too long: got %d chars, want <= 60", len(got))
	}
}

func TestDnsSafeOnlyValidChars(t *testing.T) {
	valid := regexp.MustCompile(`^[a-z0-9-]*$`)
	inputs := []string{"Hello World!", "org@corp.eu", "My_Org 123", "UPPER"}
	for _, input := range inputs {
		got := dnsSafe(input)
		if got != "" && !valid.MatchString(got) {
			t.Errorf("dnsSafe(%q) = %q contains invalid chars", input, got)
		}
	}
}

func TestDnsSafeNoLeadingTrailingDash(t *testing.T) {
	inputs := []string{"-leading", "trailing-", "-both-", "mid-dle"}
	for _, input := range inputs {
		got := dnsSafe(input)
		if strings.HasPrefix(got, "-") || strings.HasSuffix(got, "-") {
			t.Errorf("dnsSafe(%q) = %q has leading/trailing dash", input, got)
		}
	}
}

// ---- decodeB64 --------------------------------------------------------------

func TestDecodeB64(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    string
		wantErr bool
	}{
		{"valid base64", "aGVsbG8=", "hello", false},
		{"empty string", "", "", false},
		{"base64 with padding", "dGVzdA==", "test", false},
		{"base64 password", "c2VjcmV0", "secret", false},
		{"invalid base64", "not-base64!", "", true},
		{"plain text is not valid base64", "hello", "", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := decodeB64(tt.input)
			if (err != nil) != tt.wantErr {
				t.Errorf("decodeB64(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
				return
			}
			if !tt.wantErr && got != tt.want {
				t.Errorf("decodeB64(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

// ---- randHex ----------------------------------------------------------------

func TestRandHexLength(t *testing.T) {
	tests := []int{8, 16, 24, 32}
	for _, n := range tests {
		got := randHex(n)
		if len(got) != n*2 {
			t.Errorf("randHex(%d) length = %d, want %d", n, len(got), n*2)
		}
	}
}

func TestRandHexOnlyHexChars(t *testing.T) {
	validHex := regexp.MustCompile(`^[0-9a-f]+$`)
	got := randHex(16)
	if !validHex.MatchString(got) {
		t.Errorf("randHex(16) = %q contains non-hex chars", got)
	}
}

func TestRandHexUnique(t *testing.T) {
	a := randHex(16)
	b := randHex(16)
	if a == b {
		t.Errorf("randHex produced identical values: %q", a)
	}
}

// ---- strOr ------------------------------------------------------------------

func TestStrOr(t *testing.T) {
	tests := []struct {
		name  string
		v     interface{}
		def   string
		want  string
	}{
		{"nil input", nil, "default", "default"},
		{"empty string", "", "default", "default"},
		{"non-empty string", "value", "default", "value"},
		{"non-string type", 42, "default", "default"},
		{"whitespace string is non-empty", "  ", "default", "  "},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := strOr(tt.v, tt.def)
			if got != tt.want {
				t.Errorf("strOr(%v, %q) = %q, want %q", tt.v, tt.def, got, tt.want)
			}
		})
	}
}

// ---- strFrom ----------------------------------------------------------------

func TestStrFrom(t *testing.T) {
	tests := []struct {
		name  string
		input interface{}
		want  string
	}{
		{"nil", nil, ""},
		{"empty string", "", ""},
		{"valid string", "hello", "hello"},
		{"int (not a string)", 42, ""},
		{"bool (not a string)", true, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := strFrom(tt.input)
			if got != tt.want {
				t.Errorf("strFrom(%v) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

// ---- boolStr ----------------------------------------------------------------

func TestBoolStr(t *testing.T) {
	if got := boolStr(true); got != "True" {
		t.Errorf("boolStr(true) = %q, want %q", got, "True")
	}
	if got := boolStr(false); got != "False" {
		t.Errorf("boolStr(false) = %q, want %q", got, "False")
	}
}

// ---- finalizer helpers ------------------------------------------------------

func newTestUnstructured() *unstructured.Unstructured {
	u := &unstructured.Unstructured{}
	u.SetName("test-sub")
	u.SetNamespace("default")
	return u
}

func TestHasFinalizer(t *testing.T) {
	u := newTestUnstructured()

	if hasFinalizer(u) {
		t.Error("hasFinalizer should be false on new object")
	}

	u.SetFinalizers([]string{"other.finalizer/foo"})
	if hasFinalizer(u) {
		t.Error("hasFinalizer should be false when only other finalizers present")
	}

	u.SetFinalizers([]string{"other.finalizer/foo", finalizer})
	if !hasFinalizer(u) {
		t.Error("hasFinalizer should be true when finalizer is present")
	}
}

func TestAddFinalizer(t *testing.T) {
	u := newTestUnstructured()

	addFinalizer(u)
	if !hasFinalizer(u) {
		t.Error("finalizer should be present after addFinalizer")
	}
}

func TestAddFinalizerIdempotent(t *testing.T) {
	u := newTestUnstructured()
	addFinalizer(u)
	addFinalizer(u)

	count := 0
	for _, f := range u.GetFinalizers() {
		if f == finalizer {
			count++
		}
	}
	if count != 1 {
		t.Errorf("addFinalizer is not idempotent: finalizer appears %d times, want 1", count)
	}
}

func TestRemoveFinalizer(t *testing.T) {
	u := newTestUnstructured()
	u.SetFinalizers([]string{"other.io/keep", finalizer, "another.io/keep"})

	removeFinalizer(u)

	if hasFinalizer(u) {
		t.Error("finalizer should be gone after removeFinalizer")
	}

	// Other finalizers must be preserved
	remaining := u.GetFinalizers()
	if len(remaining) != 2 {
		t.Errorf("expected 2 remaining finalizers, got %d: %v", len(remaining), remaining)
	}
	for _, f := range remaining {
		if f == finalizer {
			t.Errorf("our finalizer still present after remove: %v", remaining)
		}
	}
}

func TestRemoveFinalizerNoop(t *testing.T) {
	u := newTestUnstructured()
	u.SetFinalizers([]string{"other.io/keep"})

	removeFinalizer(u) // should not panic or remove anything else

	if len(u.GetFinalizers()) != 1 || u.GetFinalizers()[0] != "other.io/keep" {
		t.Errorf("removeFinalizer modified unrelated finalizers: %v", u.GetFinalizers())
	}
}

// ---- decodeAll --------------------------------------------------------------

func TestDecodeAll(t *testing.T) {
	t.Run("single document", func(t *testing.T) {
		yaml := `
apiVersion: v1
kind: ConfigMap
metadata:
  name: test
`
		objs := decodeAll(yaml)
		if len(objs) != 1 {
			t.Errorf("expected 1 object, got %d", len(objs))
		}
		if objs[0].GetKind() != "ConfigMap" {
			t.Errorf("expected kind ConfigMap, got %q", objs[0].GetKind())
		}
	})

	t.Run("multiple documents", func(t *testing.T) {
		yaml := `
apiVersion: v1
kind: ConfigMap
metadata:
  name: first
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: second
`
		objs := decodeAll(yaml)
		if len(objs) != 2 {
			t.Errorf("expected 2 objects, got %d", len(objs))
		}
	})

	t.Run("empty document skipped", func(t *testing.T) {
		yaml := `---
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: only-one
`
		objs := decodeAll(yaml)
		if len(objs) != 1 {
			t.Errorf("expected 1 object (empty docs skipped), got %d", len(objs))
		}
	})

	t.Run("empty string returns empty slice", func(t *testing.T) {
		objs := decodeAll("")
		if len(objs) != 0 {
			t.Errorf("expected 0 objects for empty input, got %d", len(objs))
		}
	})

	t.Run("invalid yaml returns empty slice without panic", func(t *testing.T) {
		objs := decodeAll("this: is: not: valid: yaml: ::")
		_ = objs // should not panic
	})
}

// ---- render -----------------------------------------------------------------

func TestRender(t *testing.T) {
	r := &reconciler{cfg: cfg()}

	t.Run("nonexistent template returns error", func(t *testing.T) {
		_, err := r.render("does-not-exist.tmpl", nil)
		if err == nil {
			t.Error("expected error for nonexistent template, got nil")
		}
	})

	t.Run("placeholder substitution", func(t *testing.T) {
		// oauth2-proxy-org.tmpl uses __ORG__ — verify substitution works
		doc, err := r.render("oauth2-proxy-org.tmpl", map[string]string{
			"__ORG__":              "testorg",
			"__NS__":               "aitrust-msp",
			"__ORG_HOST__":         "ai-trust-testorg.example.com",
			"__KC_INTERNAL_REALM__": "http://keycloak/realms/testorg",
			"__KC_PUBLIC_REALM__":  "https://keycloak/realms/testorg",
			"__WHITELIST_DOMAIN__": "example.com",
			"__SECRET_NAME__":      "aitrust-oauth2-testorg",
			"__SECRET_KEY__":       "client-secret",
			"__COOKIE_SECRET__":    "abc123",
			"__REPLICAS__":         "1",
			"__GATEWAY_NS__":       "platform-mesh-system",
			"__GATEWAY_NAME__":     "k8sapi-gateway",
			"__GATEWAY_SECTION__":  "terminate-wildstar",
		})
		if err != nil {
			t.Fatalf("render failed: %v", err)
		}
		if strings.Contains(doc, "__ORG__") {
			t.Error("render did not substitute __ORG__ placeholder")
		}
		if !strings.Contains(doc, "testorg") {
			t.Error("render output does not contain substituted value 'testorg'")
		}
	})

	t.Run("unresolved tokens return error", func(t *testing.T) {
		_, err := r.render("oauth2-proxy-org.tmpl", map[string]string{})
		if err == nil {
			t.Error("expected error for unresolved tokens, got nil")
		}
	})
}
