# Multi-stage build for the AI Trust Platform MT (subscription) operator.
# It embeds (embed.FS) only a small tenant-provision Job template from ./manifests — per Subscription
# it provisions a TENANT (per-tenant Keycloak realm) in the SHARED app; it does NOT stamp an app copy.
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod .
COPY main.go .
COPY helpers.go .
COPY manifests ./manifests
RUN go get sigs.k8s.io/controller-runtime@v0.19.3 && \
    go get k8s.io/apimachinery@v0.31.3 && \
    go get k8s.io/api@v0.31.3 && \
    go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o /operator .

FROM gcr.io/distroless/static:nonroot
COPY --from=build /operator /operator
USER 65532:65532
ENTRYPOINT ["/operator"]
