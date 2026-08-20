# Build the inference-agent binary
FROM --platform=$BUILDPLATFORM golang:1.25 AS deps

WORKDIR /go/src/github.com/kserve/kserve
COPY go.mod  go.mod
COPY go.sum  go.sum
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# ---- Build stage (parallel with license on BuildKit) ----
FROM deps AS builder

ARG CMD=agent
ARG GOTAGS=""
# TARGET_ARCH is what ci-base's build-with-arch passes for the target platform;
# TARGETARCH is what buildx sets. Without either, the build ignores the target
# and produces a binary for the builder's architecture — which fails at runtime
# with "exec format error" on the other node pool.
ARG TARGETARCH
ARG TARGET_ARCH=${TARGETARCH}
COPY cmd/${CMD}/ cmd/${CMD}/
COPY pkg/    pkg/
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux GOARCH=${TARGET_ARCH} GOFLAGS=-mod=readonly go build -tags "${GOTAGS}" -a -o agent ./cmd/${CMD}

# ---- License stage (parallel with build on BuildKit) ----
FROM deps AS license

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go install github.com/google/go-licenses@v1.6.0

ARG CMD=agent
COPY cmd/${CMD}/ cmd/${CMD}/
COPY pkg/    pkg/
COPY LICENSE LICENSE
RUN --mount=type=cache,target=/go/pkg/mod \
    go-licenses save --save_path /third_party/library ./cmd/${CMD}

# Copy the inference-agent into a thin image
FROM gcr.io/distroless/static:nonroot
COPY --from=license /third_party /third_party
WORKDIR /ko-app
COPY --from=builder /go/src/github.com/kserve/kserve/agent /ko-app/
ENTRYPOINT ["/ko-app/agent"]
