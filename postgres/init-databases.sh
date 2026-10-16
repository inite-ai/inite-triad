#!/bin/sh
# First boot of the Postgres volume only (docker-entrypoint-initdb.d).
#
# One database and one owner role per service — Auth and Billing never share a
# schema or a credential (contract §10: there is no cross-service schema).
set -eu

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<SQL
CREATE ROLE auth LOGIN PASSWORD '${AUTH_DB_PASSWORD}';
CREATE DATABASE auth OWNER auth;
CREATE ROLE billing LOGIN PASSWORD '${BILLING_DB_PASSWORD}';
CREATE DATABASE billing OWNER billing;
SQL

# Billing's migrations run `CREATE EXTENSION IF NOT EXISTS vector` with
# search_path = billing. pgvector is not a trusted extension, so its owner role
# cannot create it; do it here, as the superuser, in the schema the migration
# expects. pg_trgm is trusted and is left to the migration.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname billing <<SQL
CREATE SCHEMA billing AUTHORIZATION billing;
CREATE EXTENSION IF NOT EXISTS vector SCHEMA billing;
SQL
