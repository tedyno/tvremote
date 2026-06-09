FROM --platform=$BUILDPLATFORM golang:1.23 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY server/ ./server/
# TARGETOS/TARGETARCH are set by buildx for multi-arch; empty on a plain build
# (then Go targets the host), so this works for both.
ARG TARGETOS TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -ldflags="-s -w" -o /out/tvremote ./server

FROM gcr.io/distroless/static-debian12
WORKDIR /app
COPY --from=build /out/tvremote /app/tvremote
COPY client/ /app/client/

EXPOSE 3000

CMD ["/app/tvremote"]
