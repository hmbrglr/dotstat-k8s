#!/bin/bash
set -e

echo "Cleaning DotStat databases..."

# Clean SQL Server mapping database
echo "  Cleaning SQL Server (dotstat-mapping)..."
kubectl exec deployment/sqlserver -n dotstat -- /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'P@ssw0rd!' -C -Q "
USE [dotstat-mapping];
DELETE FROM ARTEFACT;
DELETE FROM LOCALISED_STRING;
" > /dev/null 2>&1

# Clean MongoDB
echo "  Cleaning MongoDB (dotstat)..."
kubectl exec deployment/mongo -n dotstat -- mongosh dotstat --quiet --eval "
db.structures.deleteMany({});
db.dataflows.deleteMany({});
db.categorisations.deleteMany({});
db.datasets.deleteMany({});
" > /dev/null 2>&1

echo "Databases cleaned successfully!"
echo ""
echo "You can now import fresh data:"
echo "  1. Upload all_in_one_structure.xml"
echo "  2. Upload dataflows.xml"
echo "  3. Upload example_data.csv"
