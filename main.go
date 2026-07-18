// Command order-service is a minimal stand-in implementation of the
// Go-based order processing service described in task-1 SRE.md. This
// repository is an SRE/infrastructure assessment — the business logic here
// is intentionally a stub. Its job is only to expose the endpoints and
// metrics the rest of the repo (k8s probes, CI/CD smoke tests,
// observability SLOs/alerts) already assumes exist, so the pipeline is
// actually runnable end-to-end.
package main

import (
	"encoding/json"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"sync/atomic"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	httpRequestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Total HTTP requests processed, labeled by status code, path and method.",
	}, []string{"code", "path", "method"})

	httpRequestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "HTTP request latency in seconds.",
		Buckets: []float64{0.05, 0.1, 0.25, 0.5, 1, 2.5, 5},
	}, []string{"path"})

	dbPoolOpenConnections = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "db_pool_open_connections",
		Help: "Current number of open database connections in use.",
	})

	dbPoolMaxConnections = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "db_pool_max_connections",
		Help: "Configured maximum number of database connections.",
	})
)

// ready flips to true once the best-effort dependency check succeeds at
// startup. /readyz reports this — NOT /healthz — so a transient dependency
// blip removes the pod from Service rotation instead of killing it
// (see REVIEW.md issue #4 / ANSWERS.md Q4).
var ready atomic.Bool

type orderResponse struct {
	ID     string `json:"id"`
	Status string `json:"status"`
}

func main() {
	port := getEnv("PORT", "8080")
	maxConns := getEnvInt("DB_MAX_OPEN_CONNS", 20)
	dbPoolMaxConnections.Set(float64(maxConns))

	go runReadinessChecks()

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthzHandler)
	mux.HandleFunc("/readyz", readyzHandler)
	mux.HandleFunc("/orders", ordersHandler)
	mux.Handle("/metrics", promhttp.Handler())

	log.Printf("order-service listening on :%s", port)
	if err := http.ListenAndServe(":"+port, instrument(mux)); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}

// healthzHandler reports process-level liveness only: if this handler runs
// at all, the process is alive. It must never depend on external
// dependencies (DB, billing API).
func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

// readyzHandler reports dependency health: only serve traffic once startup
// checks (DB reachability) have completed successfully.
func readyzHandler(w http.ResponseWriter, r *http.Request) {
	if !ready.Load() {
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = w.Write([]byte("not ready"))
		return
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ready"))
}

// ordersHandler is a minimal stub standing in for real order-processing
// business logic.
func ordersHandler(w http.ResponseWriter, r *http.Request) {
	dbPoolOpenConnections.Set(1)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(orderResponse{ID: "stub-order", Status: "accepted"})
}

// instrument wraps every request with the Prometheus counters/histogram
// consumed by observability/slo.yaml and observability/alerts.yaml.
func instrument(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		duration := time.Since(start).Seconds()
		code := strconv.Itoa(rec.status)
		httpRequestsTotal.WithLabelValues(code, r.URL.Path, r.Method).Inc()
		httpRequestDuration.WithLabelValues(r.URL.Path).Observe(duration)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

// runReadinessChecks performs a best-effort TCP reachability check against
// the configured Postgres host. It never blocks startup indefinitely and
// never crashes the process if the DB is unreachable — it only controls
// what /readyz reports.
func runReadinessChecks() {
	host := os.Getenv("DB_HOST")
	if host == "" {
		// No DB configured (local/dev run) — report ready immediately.
		ready.Store(true)
		return
	}
	for {
		conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, "5432"), 2*time.Second)
		if err == nil {
			_ = conn.Close()
			ready.Store(true)
			return
		}
		time.Sleep(2 * time.Second)
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}
