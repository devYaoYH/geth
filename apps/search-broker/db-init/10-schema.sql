CREATE TABLE search_requests (
  id UUID PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  idempotency_key TEXT,
  query_text TEXT,
  query_sha256 CHAR(64),
  requested_results SMALLINT,
  state TEXT NOT NULL CHECK (state IN ('pending', 'completed', 'failed', 'denied', 'legacy')),
  upstream_status INTEGER,
  provider_response JSONB,
  response_bytes INTEGER,
  duration_ms INTEGER,
  result_count SMALLINT,
  cost_dollars NUMERIC(12, 6),
  failure_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX search_requests_tenant_idempotency_key
  ON search_requests (tenant_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;
CREATE INDEX search_requests_created_at_idx ON search_requests (created_at DESC);
CREATE INDEX search_requests_tenant_created_at_idx ON search_requests (tenant_id, created_at DESC);
CREATE INDEX search_requests_query_sha256_idx ON search_requests (query_sha256);

CREATE TABLE search_results (
  request_id UUID NOT NULL REFERENCES search_requests(id) ON DELETE RESTRICT,
  rank SMALLINT NOT NULL CHECK (rank > 0),
  title TEXT,
  url TEXT,
  published_date TEXT,
  author TEXT,
  highlights JSONB NOT NULL DEFAULT '[]'::jsonb,
  PRIMARY KEY (request_id, rank)
);

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
