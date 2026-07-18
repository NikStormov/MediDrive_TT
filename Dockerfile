# --- Build stage ---
FROM golang:1.23-alpine AS builder
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/order-service .

# --- Runtime stage: distroless, non-root, no shell ---
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/order-service /order-service

USER nonroot:nonroot
EXPOSE 8080

ENTRYPOINT ["/order-service"]
