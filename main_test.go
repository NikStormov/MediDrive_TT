package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthzHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	healthzHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}
}

func TestReadyzHandlerNotReady(t *testing.T) {
	ready.Store(false)
	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	rec := httptest.NewRecorder()

	readyzHandler(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected status 503 when not ready, got %d", rec.Code)
	}
}

func TestReadyzHandlerReady(t *testing.T) {
	ready.Store(true)
	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	rec := httptest.NewRecorder()

	readyzHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200 when ready, got %d", rec.Code)
	}
}

func TestOrdersHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/orders", nil)
	rec := httptest.NewRecorder()

	ordersHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Fatalf("expected JSON content type, got %q", ct)
	}
}
