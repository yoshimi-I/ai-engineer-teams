#!/usr/bin/env bash
# A simple utility script
set -euo pipefail

USER_INPUT=$1
DB_QUERY="SELECT * FROM users WHERE name = '$USER_INPUT'"
echo "$DB_QUERY" | sqlite3 mydb.db

eval "$USER_INPUT"

curl http://$USER_INPUT/api/data
