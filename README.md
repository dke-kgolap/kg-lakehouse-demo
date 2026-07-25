# KG Lakehouse Demo

Instructions for running the Knowledge Graph Lakehouse demonstration on a
local computer, as presented at the ISWC 2026 Posters & Demos track. The
Knowledge Graph Lakehouse ingests raw aeronautical documents, indexes each
document's context, and constructs contextualized knowledge graphs (CKGs) on
demand. Source code and documentation:
[kg-lakehouse](https://github.com/dke-kgolap/kg-lakehouse)
([doi:10.5281/zenodo.21289343](https://doi.org/10.5281/zenodo.21289343)).

Everything runs from published container images; nothing is built locally.

## Prerequisites

- Docker with the Compose plugin. The application images are built for
  linux/amd64 and are pinned to that platform in `docker-compose.yaml`; on
  Apple Silicon they run under emulation (enable *Rosetta for x86_64/amd64
  emulation* in Docker Desktop settings for the best performance), while the
  infrastructure images (Cassandra, Kafka, and the rest) run natively.
- about 8 GB of free memory and 5 GB of disk
- `curl` and `python3` (used by the ingestion script)
- free local ports 3001 (console), 8080 (API), 3000 (Grafana), 9042, 9092,
  9000/9001, 6379

## 1. Start the platform

```shell
docker compose up -d --wait
```

This pulls the released images
([`basharahmad/lakehouse-*:1.0.4`](https://hub.docker.com/u/basharahmad))
and starts the five lakehouse services, the web console, and the backing
infrastructure (Cassandra, Kafka, MinIO, Redis, and the monitoring stack).
The first start downloads images and takes a few minutes; `--wait` returns
when all health checks pass. The three demonstration schemas (`atm`,
`meteo`, `fixm`) are loaded automatically from `config/schemas/`.

## 2. Generate the dataset

```shell
scripts/generate-dataset.sh
```

The dataset is produced by [ATM-GEN](https://github.com/dke-kgolap/atm-gen)
([doi:10.5281/zenodo.21288733](https://doi.org/10.5281/zenodo.21288733)),
a deterministic generator of standards-compliant synthetic ATM data seeded
from the openly licensed Donlon 2022 reference dataset. The script writes
`./dataset`: seven days of operations (2025-01-01 to 2025-01-07) across
eleven flight information regions — 1,436 XML documents in total: 14 AIXM
infrastructure baselines and NOTAM files, 1,212 IWXXM meteorological reports
(METAR, TAF, SIGMET), and 210 FIXM flight plans. Generation is deterministic
in structure and size — every run reproduces the same days, regions, and
document counts; the flight identifiers in the FIXM documents vary between
runs.

## 3. Ingest the dataset

```shell
scripts/ingest-dataset.sh
```

The script uploads every document, routing each format to its schema, then
waits for the asynchronous context extraction to finish. Expect 343 contexts
in total: 175 for `atm`, 126 for `meteo`, and 42 for `fixm`.

## 4. Open the console

Open <http://localhost:3001> and sign in with user `admin`, password
`admin`.

### Default credentials

| Interface | Address | User | Password |
| --- | --- | --- | --- |
| Web console | <http://localhost:3001> | `admin` | `admin` |
| Gateway API (HTTP Basic) | <http://localhost:8080> | `admin` | `admin` |
| Grafana (monitoring) | <http://localhost:3000> | `admin` | `admin` |

The console has no accounts of its own: it forwards the entered credentials
to the gateway on every request, so console and API share the same pair. To
change it, set `LAKEHOUSE_USER` and `LAKEHOUSE_PASSWORD` on the `surface`
service in `docker-compose.yaml` and restart the stack; the ingestion script
then needs the same pair via `USER_AUTH=user:password`. Grafana additionally
allows anonymous read-only viewing.

## Demonstration walkthrough

1. **Ingestion.** The *Ingestion* screen shows the uploaded documents with
   the contexts discovered in each and the per-document processing time.
   Uploading a single additional document here (any file from `./dataset`)
   shows the live path.
2. **Context hierarchies.** The *Schema Explorer* shows, per schema, the
   context dimensions and their levels — for `atm`: time (year, month,
   day), location (territory, flight information region, location), and
   topic (category, family, feature) — together with the extracted context
   and hierarchy counts.
3. **Slice, dice, and roll up.** In the *Query Workspace*, select schema
   `meteo`, open the *DSL* tab, and run:

   ```
   SELECT time_day=2025-01-03 AND location_fir=LOVV
   ```

   The result — the weather reports valid for the Austrian flight
   information region on that day, five contexts — can be viewed as an
   interactive graph, a table, or the raw serialization. Then select schema
   `atm` and run:

   ```
   SELECT topic_category=Navaid ROLLUP ON location_territory
   ```

   which aggregates the navigation-aid contexts (40) up to whole
   territories; inspect it in the cube view. The *Representation* selector
   switches the same query between RDF, labeled property graph, and Spark
   GraphFrame output.
4. **Reasoning.** Re-run the `atm` query with the *Reasoning* switch on.
   Each context is enriched with derived facts — a navigation aid asserted
   as a VOR is now also classified as navaid equipment and as a navaid —
   and the returned graph grows accordingly.
5. **Performance.** The *Performance* screen breaks each query into its
   stages (context resolution, per-context graph construction, merge and
   rollup) and shows the effect of the graph cache: re-running a query
   turns construction into cache hits and visibly shortens the response.

## Tear down

```shell
docker compose down -v
```

removes the containers and all stored data.

## Troubleshooting

- **A port is already in use.** Another service occupies one of the listed
  ports; stop it or edit the port mappings in `docker-compose.yaml`.
- **`docker compose up` times out waiting for health checks.** Cassandra
  can take over a minute on first start; re-run the command — it resumes
  where it left off.
- **Uploads fail with connection errors.** Confirm the gateway is healthy:
  `curl http://localhost:8080/api/health` should return `{"status":"UP"}`.
- **Document counts are higher than expected after ingestion.** A previous
  lakehouse deployment on the same machine may have left data volumes behind
  (the Compose project is named `lakehouse`, so volumes are shared across
  checkouts). Start clean with `docker compose down -v` and repeat the steps.
