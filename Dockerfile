FROM golang:1.23 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY server/ ./server/
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/tvremote ./server

FROM gcr.io/distroless/static-debian12
WORKDIR /app
COPY --from=build /out/tvremote /app/tvremote
COPY client/ /app/client/

EXPOSE 3000

CMD ["/app/tvremote"]
