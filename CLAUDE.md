# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

IX Metaverse Contract Management System — manages "consent-based interactions" (contracts) between users in a metaverse platform. Phase 0 runs entirely off-chain on Supabase (PostgreSQL). Future phases migrate to MegaETH smart contracts.

## Architecture

- **Database**: Supabase self-hosted via Docker Compose (`supabase-local/`)
- **Schema**: 6 tables in PostgreSQL with ENUM types, triggers, RLS policies, and a `public_ledger` view
- **API**: Auto-generated REST API via PostgREST (no custom backend code yet)
- **Docs**: Requirements and schema specs in `doc/`

Key design constraint: DB schema must map 1:1 to Phase 1 smart contract state (MegaETH).

## Supabase Local Commands

```bash
# Start all services
cd supabase-local && docker compose up -d

# Stop (keep data)
docker compose down

# Stop and destroy all data
docker compose down -v

# Check service health
docker compose ps --format "table {{.Name}}\t{{.Status}}"

# Apply schema
cat doc/references/phase0-schema.sql | docker exec -i supabase-db psql -U postgres -d postgres

# Apply seed data
cat doc/references/phase0-seed.sql | docker exec -i supabase-db psql -U postgres -d postgres

# Run arbitrary SQL
docker exec -i supabase-db psql -U postgres -d postgres -c "SELECT ..."

# View service logs
docker logs supabase-db
docker logs supabase-pooler
```

## Access URLs

| URL | Purpose |
|-----|---------|
| http://localhost:8000 | Supabase Studio (admin: `supabase` / check `.env` for password) |
| http://localhost:8888 | Swagger UI (REST API spec) |
| http://localhost:8889 | API Docs (all APIs) |
| localhost:5432 | PostgreSQL session mode |
| localhost:6543 | PostgreSQL pooled mode |

## Database Schema (Phase 0)

6 tables with contract lifecycle: `Created → Active → Completed → Settled` (with `Disputed → Resolved` branch).

- `contract_templates` — Admin-managed templates with blockchain recording policy
- `contract_instances` — Concrete contract between parties
- `contract_parties` — Participants + escrow amounts
- `contract_results` — Event outcomes
- `contract_settlements` — Point transfers (reward/fee/refund)
- `contract_consents` — Consent/dispute from parties

System UUIDs: Escrow=`00000000-...-000000000000`, Treasury=`00000000-...-000000000001`.

Custom ENUM types map to Solidity enums: `contract_type`, `contract_status`, `payment_type`, `point_type`, `chain_record_policy`, `result_source`.

## Key Files

- `doc/requement.md` — Full requirements spec (Phase 0–3)
- `doc/agent_content.md` — Supabase setup guide + Phase 0 schema reference
- `doc/references/phase0-schema.sql` — Complete SQL schema (tables, triggers, RLS, views, realtime)
- `doc/references/phase0-seed.sql` — Sample template data (4 templates)
- `supabase-local/docker-compose.yml` — Docker Compose for all Supabase services
- `supabase-local/.env` — Environment config (secrets, ports)

## API Authentication

All REST API calls require `apikey` header. Keys are in `supabase-local/.env`:
- `ANON_KEY` — Client-side, respects RLS
- `SERVICE_ROLE_KEY` — Server-side, bypasses RLS (admin operations)

These are JWT tokens signed with `JWT_SECRET`, not random strings.
