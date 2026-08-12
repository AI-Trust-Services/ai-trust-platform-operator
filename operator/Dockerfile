# Multi-stage build for the AI Trust MSP operator.
# The app manifests are embedded (embed.FS) from ./manifests, so the image is self-contained:
# it renders + applies the full app stack per AITrustPlatformInstance CR.
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod .
COPY main.go .
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
