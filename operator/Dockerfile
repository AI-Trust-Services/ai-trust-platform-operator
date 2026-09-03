# Multi-stage build for the AI Trust Platform (subscription) operator.
# It embeds (embed.FS) only a small tenant-provision Job template from ./manifests — per Subscription
# it provisions a TENANT (per-tenant Keycloak realm) in the SHARED app; it does NOT stamp an app copy.
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
COPY manifests ./manifests
RUN CGO_ENABLED=0 GOOS=linux go build -o /operator .

FROM gcr.io/distroless/static:nonroot
COPY --from=build /operator /operator
USER 65532:65532
ENTRYPOINT ["/operator"]
