# Licensing and cost note: AWR / Diagnostics Pack

**Status (2026-10-07):** AWR is **enabled for this PoC** because it runs on Oracle AI Database
26ai **Free**, which includes the Diagnostics Pack and Tuning Pack at no cost. **Before this tool
is pointed at any other Oracle edition, read this page.**

## Why it's free here

Oracle's *Database Licensing Information User Manual* (26ai) lists the
**Diagnostics Pack** and **Tuning Pack** as **included** in Oracle AI Database Free (also in
OCI BaseDB EE-HP/EE-EP and Exadata Database Service). Source:
<https://docs.oracle.com/en/database/oracle/oracle-database/26/dblic/Licensing-Information.html>

Free has its own limits (2 CPUs, 2 GB RAM, 12 GB user data) and comes under the Oracle Free Use
Terms, so it isn't a stand-in for a licensed production database.

## What costs money elsewhere

| Target edition | AWR / ASH / ADDM available? | Cost |
|---|---|---|
| Oracle Database **Free** (this PoC) | Yes, included | none |
| **Enterprise Edition** on-prem / customer cloud VMs | Only with the **Diagnostics Pack** (an extra-cost option) | List price about **US$7,500 per processor** or **US$150 per Named User Plus**, plus about 22% a year for support. The **Tuning Pack** (SQL Tuning Advisor, SQL Monitor) costs another ~US$5,000 per processor and needs the Diagnostics Pack. |
| **Standard Edition 2** | **No.** The packs can't be bought for SE2 | Using AWR on SE2 is unlicensed use and can't be fixed by buying the pack. |
| OCI BaseDB EE-HP / EE-EP, ExaDB, Autonomous | Included in the service price | none extra |

Prices are from Oracle's public *Technology Global Price List* as last known. Check the
current list and the customer's own contract, because discounts and ULAs vary.
"Processor" means cores × the core factor (0.5 for Intel/AMD x86), so a 16-core x86 server
counts as 8 processors. At list price that's about **US$60,000 for the Diagnostics Pack plus
~US$13,200 a year in support, for one server**. Standby/DR servers need licensing too.

## How Oracle detects use

Oracle doesn't stop you running AWR on an unlicensed EE database. It records the use:
- `DBA_FEATURE_USAGE_STATISTICS` logs "AWR Report", "Automatic Workload Repository",
  "ADDM" and "Active Session History" whenever they're used. **Just querying `DBA_HIST_*` or
  `V$ACTIVE_SESSION_HISTORY` counts**, as do the SQLcl `awr` command and `awrrpt.sql`.
- Oracle License Management Services audits read this view. A single recorded use can lead to
  a back-licence demand for every processor in the server, plus back support.
- `CONTROL_MANAGEMENT_PACK_ACCESS` defaults to `DIAGNOSTIC+TUNING` even on EE without the
  packs. Setting it to `NONE` stops AWR snapshots, but it doesn't wipe usage that's already
  recorded.

## What this PoC does to stay safe

- `scripts/awr-report.sh` **refuses to run** unless `V$VERSION` says "Free", or the operator
  sets `AWR_LICENSED=1` after confirming the target has the Diagnostics Pack.
- `/db-diag-review` uses AWR only after the same edition check, and otherwise falls back to
  **Statspack** (free on every edition, including SE2). The Statspack path stays in place for
  this reason.
- `/db-health-check` still uses only base `V$`/`DBA_` views, so it's safe on any edition.

## Checklist before onboarding to a licensed (non-Free) Oracle estate

1. Ask the customer which editions they run, and whether **Diagnostics Pack** (and **Tuning
   Pack**) are licensed **on each server**, including standby/DR servers.
2. If they aren't licensed: leave `AWR_LICENSED` unset, and either set
   `control_management_pack_access = NONE` (the customer DBA's decision, not ours) or rely on
   the edition gate. Use Statspack for workload history.
3. If they're licensed: set `AWR_LICENSED=1` for that target only, and record who confirmed
   it and when.
4. Check `DBA_FEATURE_USAGE_STATISTICS` before and after a pilot run, so there's evidence of
   what the tool touched.
5. Budget, if the customer wants AWR-based analysis and isn't licensed: Diagnostics Pack for
   every processor of every target server (see the table above). Statspack-based analysis
   costs nothing.
