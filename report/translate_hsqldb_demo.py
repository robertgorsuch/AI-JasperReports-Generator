#!/usr/bin/env python3
"""Translate the JasperReports demo HSQLDB test.script into PostgreSQL DDL+DML.

Emits the demo tables (ORDERS, PRODUCT, POSITIONS, DOCUMENT, ADDRESS, TASKS,
BLOCKS) into the target DB's public schema so the JR Library 'charts' (and other
SQL) samples can run against the existing /datasources/postgis_34_sample.
Handles the two HSQLDB-isms that PostgreSQL rejects: CREATE MEMORY TABLE and
\\uXXXX unicode escapes inside string literals.
"""
import re, sys

SRC = r"C:\Users\rgorsuch\jasperreports-7.0.6\demo\hsqldb\test.script"
OUT = r"C:\Users\rgorsuch\tx-geocoder\report\jrdemo.sql"
TABLES = ["ADDRESS", "PRODUCT", "DOCUMENT", "POSITIONS", "ORDERS", "TASKS"]

uesc = re.compile(r'\\u([0-9a-fA-F]{4})')

def decode_unicode(s):
    return uesc.sub(lambda m: chr(int(m.group(1), 16)), s)

creates, inserts = [], []
with open(SRC, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.rstrip("\n")
        if line.startswith("CREATE MEMORY TABLE PUBLIC."):
            ddl = line.replace("CREATE MEMORY TABLE PUBLIC.", "CREATE TABLE public.")
            if not ddl.rstrip().endswith(";"):
                ddl += ";"
            creates.append(ddl)
        elif line.startswith("INSERT INTO "):
            tbl = line.split()[2]
            if tbl in TABLES:
                ins = decode_unicode(line)
                # qualify table into public schema
                ins = ins.replace(f"INSERT INTO {tbl} ", f"INSERT INTO public.{tbl} ", 1)
                if not ins.rstrip().endswith(";"):
                    ins += ";"
                inserts.append(ins)

with open(OUT, "w", encoding="utf-8") as f:
    f.write("-- JasperReports demo data, translated from HSQLDB to PostgreSQL\n")
    f.write("SET client_encoding = 'UTF8';\nBEGIN;\n")
    for t in TABLES:
        f.write(f"DROP TABLE IF EXISTS public.{t} CASCADE;\n")
    for c in creates:
        f.write(c + "\n")
    for i in inserts:
        f.write(i + "\n")
    f.write("COMMIT;\n")

print(f"wrote {OUT}: {len(creates)} tables, {len(inserts)} inserts")
