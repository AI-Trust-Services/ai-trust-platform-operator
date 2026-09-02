package main

import (
	"log"
	"os"
	"strings"
)

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func mustEnv(k string) string {
	v := os.Getenv(k)
	if v == "" {
		log.Fatalf("required env var %s is not set", k)
	}
	return v
}

type config struct {
	providerNS     string // ns on the shoot for the shared app + per-org proxies
	domainSuffix   string // per-org host = ai-trust-<org>.<domainSuffix>
	poolLabel      string // worker pool nodeSelector/toleration value
	kcInternal     string // in-cluster mesh keycloak base, incl /keycloak (issuer/redeem/jwks)
	kcPublic       string // public mesh keycloak base, incl /keycloak (browser login-url)
	gatewayNS      string
	gatewayName    string
	gatewaySection string // listener sectionName that terminates *.<domainSuffix>
	openfgaURL     string // shared mesh OpenFGA http endpoint
	storeID        string // the ONE shared app store id (roles seeded at deploy)
	meshAdminNS    string // ns holding the mesh keycloak bootstrap-admin secret
	meshAdminName  string // name of that secret (keys: username/password)
	dbMigrateImage string // image (alembic + ai_trust_persistence) used to provision per-tenant schemas
	chMigrateImage string // image (clickhouse-migrate) used to provision per-tenant ClickHouse databases
	appRole        string // the non-superuser runtime Postgres role granted on each tenant schema
	remoteKubecfg  string // path to the mounted ai-trust-1 SA kubeconfig (provisioning target)
	prodKcPublic   string // PROD public Keycloak base (incl /keycloak) — the realm the a1 IdP brokers
	idpClientID    string // OIDC client id the a1 'prod' IdP uses at prod's Keycloak
	prodKcInternal string // PROD in-cluster mesh Keycloak base (reachable from the controller on prod)
	localNS        string // the controller's OWN namespace on prod (aitrust-remote) — where local Jobs run
	prodMeshAdminNS   string // prod mesh keycloak-admin secret ns
	prodMeshAdminName string // prod mesh keycloak-admin secret name
	federated         bool   // FEDERATION_MODE=federated → cross-cluster; false → single-cluster (local)
}

func cfg() config {
	federated := strings.ToLower(strings.TrimSpace(os.Getenv("FEDERATION_MODE"))) == "federated"
	remoteKubecfg := env("REMOTE_KUBECONFIG", "")
	if federated && remoteKubecfg == "" {
		log.Fatalf("required env var REMOTE_KUBECONFIG is not set (required in federated mode)")
	}
	return config{
		federated:         federated,
		providerNS:        env("PROVIDER_NS", "aitrust-msp"),
		domainSuffix:      env("INSTANCE_DOMAIN_SUFFIX", "ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu"),
		poolLabel:         env("MSP_WORKER_LABEL", "ai-trust"),
		kcInternal:        env("KC_INTERNAL_URL", "http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak"),
		kcPublic:          env("KC_PUBLIC_URL", "https://ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/keycloak"),
		gatewayNS:         env("GATEWAY_NS", "platform-mesh-system"),
		gatewayName:       env("GATEWAY_NAME", "k8sapi-gateway"),
		gatewaySection:    env("GATEWAY_SECTION", "terminate-wildstar"),
		openfgaURL:        env("OPENFGA_URL", "http://openfga.platform-mesh-system.svc.cluster.local:8080"),
		storeID:           mustEnv("OPENFGA_STORE_ID"),
		meshAdminNS:       env("MESH_KC_ADMIN_NS", "platform-mesh-system"),
		meshAdminName:     env("MESH_KC_ADMIN_SECRET", "keycloak-admin"),
		dbMigrateImage:    env("DBMIGRATE_IMAGE", "mirceacraciun795/aitrust-db-migrate:aitrust"),
		chMigrateImage:    env("CHMIGRATE_IMAGE", "mirceacraciun795/aitrust-clickhouse-migrate:aitrust"),
		appRole:           env("APP_DB_ROLE", "ai_trust_app"),
		remoteKubecfg:     remoteKubecfg,
		prodKcPublic:      env("PROD_KC_PUBLIC_URL", "https://ai-trust-prod.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu/keycloak"),
		idpClientID:       env("IDP_CLIENT_ID", "aitrust-fed-broker"),
		prodKcInternal:    env("PROD_KC_INTERNAL_URL", "http://keycloak-service.platform-mesh-system.svc.cluster.local:8080/keycloak"),
		localNS:           env("LOCAL_NS", "aitrust-remote"),
		prodMeshAdminNS:   env("PROD_MESH_KC_ADMIN_NS", "platform-mesh-system"),
		prodMeshAdminName: env("PROD_MESH_KC_ADMIN_SECRET", "keycloak-admin"),
	}
}
