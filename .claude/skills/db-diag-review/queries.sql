-- db-diag-review diagnostic queries
-- Licensing: alert log, trace files and ADR incidents come from the free V$DIAG_* views.
-- Workload history comes from Statspack (PERFSTAT.STATS$* tables, free on every edition) or,
-- on Oracle Database Free only, from AWR (Diagnostics Pack, included in Free). The two awr_*
-- checks are the only ones touching DBA_HIST_*. Run them only after edition_gate returns
-- is_free = 'Y'. See LICENSING.md.
--
-- Each check is one read-only statement, run separately via the MCP sql_run tool.
-- "-- @check: <id> | <conn> | <title>" marks the start of each check. <conn> is the connection
-- role the check needs:
--   cdb = CDB root (whole-instance alert log / traces), default demo_dbmon_cdb
--   pdb = the PDB that holds Statspack, default demo_dbmon
-- Placeholders, replaced textually before running:
--   {{days}}        look-back window in days (default 7)
--   {{begin_snap}}  {{end_snap}}  Statspack snapshot ids (chosen from sp_snapshots)
--   {{trace_file}}  {{line_from}}  {{line_to}}  for trace_excerpt
-- Every statement carries the /* db-diag-review */ tag.

-- ===================================================================== Alert log (cdb)

-- @check: alert_overview | cdb | Alert log volume by day, container and category
select /* db-diag-review */
       to_char(trunc(originating_timestamp), 'YYYY-MM-DD') as day,
       nvl(container_name, 'CDB$ROOT') as container,
       count(*) as all_lines,
       count(case when message_type = 2 or message_text like '%(incident=%' then 1 end) as incidents,
       count(case when regexp_like(message_text, 'ORA-|TNS-') then 1 end) as ora_tns_lines,
       count(case when message_level = 1 then 1 end) as critical_level,
       count(case when regexp_like(message_text, 'Starting ORACLE instance|Instance shutdown complete|Crash Recovery|Beginning crash recovery') then 1 end) as lifecycle
from v$diag_alert_ext
where originating_timestamp > systimestamp - numtodsinterval({{days}}, 'DAY')
group by trunc(originating_timestamp), nvl(container_name, 'CDB$ROOT')
order by 1, 2;

-- @check: alert_errors | cdb | Distinct error / warning messages (grouped, newest first)
-- Numbers in the message (except ORA-/TNS- codes) are masked so repeats of the same problem group together.
select /* db-diag-review */
       category, container,
       to_char(min(ts), 'YYYY-MM-DD HH24:MI') as first_seen,
       to_char(max(ts), 'YYYY-MM-DD HH24:MI') as last_seen,
       count(*) as occurrences,
       max(trace_file) as example_trace_file,
       msg
from (
  select originating_timestamp as ts,
         nvl(container_name, 'CDB$ROOT') as container,
         case
           when regexp_like(message_text, 'ORA-0*600[^0-9]|ORA-0*7445|ORA-0*4031|ORA-0*1578|ORA-0*1110|corrupt', 'i') then '1-critical'
           when message_type = 2 or message_text like '%(incident=%' then '2-incident'
           when regexp_like(message_text, 'ORA-|TNS-') then '3-error'
           else '4-warning'
         end as category,
         regexp_substr(message_text, '/[^ ]+\.trc') as trace_file,
         substr(regexp_replace(regexp_replace(regexp_replace(message_text,
                  '/[^ ]+\.trc', '<trace>'), '(^|[^-0-9])[0-9]{2,}', '\1N'), '\s+', ' '), 1, 200) as msg
  from v$diag_alert_ext
  where originating_timestamp > systimestamp - numtodsinterval({{days}}, 'DAY')
    and (   message_type = 2
         or message_level = 1
         or regexp_like(message_text,
              'ORA-|TNS-|deadlock|checkpoint not complete|cannot allocate new log|archiver|'
              || 'corrupt|terminating the instance|instance terminated|longer than expected|'
              || 'cannot be elevated|persistent data failure|WARNING|failed|unable to', 'i'))
    -- noise: routine autoextend messages and startup parameter echoes ("LICENSE_SESSIONS_WARNING = 0")
    and not regexp_like(message_text, '^Resize operation completed')
    and not regexp_like(message_text, '^\s*[A-Za-z_]+\s*=\s*\S*\s*$')
)
group by category, container, msg
order by category, max(ts) desc
fetch first 40 rows only;

-- @check: alert_lifecycle | cdb | Instance / PDB lifecycle events (startups, shutdowns, crash recovery)
select /* db-diag-review */
       to_char(originating_timestamp, 'YYYY-MM-DD HH24:MI:SS') as ts,
       nvl(container_name, 'CDB$ROOT') as container,
       substr(regexp_replace(message_text, '\s+', ' '), 1, 150) as event
from v$diag_alert_ext
where originating_timestamp > systimestamp - numtodsinterval({{days}}, 'DAY')
  and regexp_like(message_text,
        'Starting ORACLE instance|Shutting down ORACLE instance|Instance shutdown complete|'
        || 'Beginning crash recovery|Crash Recovery|Shutting down instance \(abort\)|'
        || 'Completed: ALTER DATABASE OPEN|^ALTER PLUGGABLE DATABASE|Pluggable database [A-Z0-9_$]+ (opened|closed)')
order by originating_timestamp
fetch first 60 rows only;

-- ===================================================================== ADR incidents (cdb)

-- @check: adr_problems | cdb | ADR problems (one row per distinct critical error, all time)
-- An ADR "problem" groups repeated incidents of the same critical error. Oracle Support asks
-- for incident packages (adrci "ips pack") when you raise a Service Request.
select /* db-diag-review */
       p.problem_id, p.problem_key,
       to_char(p.firstinc_time, 'YYYY-MM-DD HH24:MI') as first_incident,
       to_char(p.lastinc_time, 'YYYY-MM-DD HH24:MI') as last_incident,
       (select count(*) from v$diag_incident i where i.problem_id = p.problem_id) as incidents,
       (select count(*) from v$diag_incident i where i.problem_id = p.problem_id
          and i.create_time > systimestamp - numtodsinterval({{days}}, 'DAY')) as incidents_in_window,
       p.service_request, p.bug_number
from v$diag_problem p
order by p.lastinc_time desc;

-- @check: adr_incidents | cdb | ADR incidents in the window
select /* db-diag-review */
       incident_id, to_char(create_time, 'YYYY-MM-DD HH24:MI:SS') as created,
       'ORA-' || lpad(error_number, 5, '0') as error, substr(error_arg1, 1, 40) as arg1,
       substr(error_arg2, 1, 40) as arg2, signalling_component, status, flood_controlled, con_id
from v$diag_incident
where create_time > systimestamp - numtodsinterval({{days}}, 'DAY')
order by create_time desc
fetch first 30 rows only;

-- ===================================================================== Trace files (cdb)

-- @check: trace_inventory | cdb | Trace files written in the window, by process type
-- The process name is the middle part of FREE_<process>_<pid>.trc (ora = a user session).
select /* db-diag-review */
       regexp_substr(trace_filename, '^[^_]+_([a-z]+)[0-9a-z]*_', 1, 1, null, 1) as process,
       count(*) as files,
       to_char(max(modify_time), 'YYYY-MM-DD HH24:MI') as latest
from v$diag_trace_file
where modify_time > systimestamp - numtodsinterval({{days}}, 'DAY')
group by regexp_substr(trace_filename, '^[^_]+_([a-z]+)[0-9a-z]*_', 1, 1, null, 1)
order by files desc;

-- @check: trace_signatures | cdb | Serious signatures inside recent trace files
-- Scans only files modified in the window. first_line feeds trace_excerpt.
select /* db-diag-review */
       trace_filename, signature, count(*) as hits, min(line_number) as first_line,
       to_char(max(modify_time), 'YYYY-MM-DD HH24:MI') as file_modified,
       max(container_name) as container
from (
  select c.trace_filename, c.line_number, f.modify_time, c.container_name,
         case
           when regexp_like(c.payload, 'ORA-0*600[^0-9]') then 'ORA-00600 internal error'
           when regexp_like(c.payload, 'ORA-0*7445') then 'ORA-07445 process crash'
           when regexp_like(c.payload, 'ORA-0*4031') then 'ORA-04031 shared memory'
           when regexp_like(c.payload, 'ORA-0*1578|ORA-0*1110|Corrupt block', 'i') then 'block corruption'
           when c.payload like '%DEADLOCK DETECTED%' then 'ORA-00060 deadlock'
           when c.payload like '%ORA-00800%' then 'ORA-00800 soft external error'
           when regexp_like(c.payload, 'ORA-0*1555') then 'ORA-01555 snapshot too old'
           else 'out of space'
         end as signature
  from v$diag_trace_file f
  join v$diag_trace_file_contents c
    on c.adr_home = f.adr_home and c.trace_filename = f.trace_filename
  where f.modify_time > systimestamp - numtodsinterval({{days}}, 'DAY')
    and regexp_like(c.payload, 'ORA-0*600[^0-9]|ORA-0*7445|ORA-0*4031|ORA-0*1578|ORA-0*1110|Corrupt block|'
                             || 'DEADLOCK DETECTED|ORA-00800|ORA-0*1555|ORA-0*1652|ORA-0*1653|ORA-0*1654|ORA-0*1688', 'i')
)
group by trace_filename, signature
order by max(modify_time) desc
fetch first 30 rows only;

-- @check: trace_excerpt | cdb | Excerpt of one trace file (bounded line window)
-- Run once per interesting file from trace_signatures, with line_from = first_line - 15 and
-- line_to = first_line + 120. Never pull a whole trace file: some are tens of thousands of lines.
-- Add the file header (lines 1-40) for session / module context when it's useful.
select /* db-diag-review */
       line_number, substr(payload, 1, 400) as payload
from v$diag_trace_file_contents
where trace_filename = '{{trace_file}}'
  and line_number between {{line_from}} and {{line_to}}
order by line_number;

-- ===================================================================== AWR, Free only (cdb)

-- @check: edition_gate | cdb | Is this Oracle Database Free? (AWR allowed only if is_free = Y)
-- V$VERSION and V$INSTANCE are base views, so this check is safe on any edition.
select /* db-diag-review */
       (select banner_full from v$version where rownum = 1) as banner,
       (select edition from v$instance) as edition,
       case when (select edition from v$instance) = 'FREE'
              or (select banner from v$version where rownum = 1) like '%Free%'
            then 'Y' else 'N' end as is_free
from dual;

-- @check: awr_snapshots | cdb | AWR snapshots (most recent 20). ONLY if edition_gate is_free = Y
select /* db-diag-review */
       snap_id, to_char(begin_interval_time, 'YYYY-MM-DD HH24:MI') as begin_time,
       to_char(end_interval_time, 'YYYY-MM-DD HH24:MI') as end_time,
       to_char(startup_time, 'YYYY-MM-DD HH24:MI:SS') as startup_time,
       snap_flag   -- 0 = automatic, 1 = manual
from dba_hist_snapshot
where dbid = (select dbid from v$database)
order by snap_id desc
fetch first 20 rows only;

-- ===================================================================== Statspack (pdb)

-- @check: sp_snapshots | pdb | Statspack snapshots (most recent 20)
-- Pick begin/end ids from this list: same startup_time (stats reset at every restart), and by
-- default the newest adjacent pair.
select /* db-diag-review */
       s.snap_id, to_char(s.snap_time, 'YYYY-MM-DD HH24:MI:SS') as snap_time,
       to_char(s.startup_time, 'YYYY-MM-DD HH24:MI:SS') as startup_time,
       s.snap_level, s.ucomment,
       round((s.snap_time - lag(s.snap_time) over (order by s.snap_id)) * 86400) as secs_since_prev
from perfstat.stats$snapshot s
order by s.snap_id desc
fetch first 20 rows only;

-- @check: sp_header | pdb | Snapshot pair, elapsed time, DB time and host
with b as (select * from perfstat.stats$snapshot where snap_id = {{begin_snap}}),
     e as (select * from perfstat.stats$snapshot where snap_id = {{end_snap}}),
     tm as (select n.stat_name, en.value - bn.value as delta
            from perfstat.stats$sys_time_model bn
            join perfstat.stats$sys_time_model en on en.stat_id = bn.stat_id and en.snap_id = {{end_snap}}
            join perfstat.stats$time_model_statname n on n.stat_id = bn.stat_id
            where bn.snap_id = {{begin_snap}})
select /* db-diag-review */
       di.db_name, di.instance_name, di.host_name, di.version, di.platform_name,
       sys_context('USERENV', 'CON_NAME') as container,
       to_char(b.snap_time, 'YYYY-MM-DD HH24:MI:SS') as begin_time,
       to_char(e.snap_time, 'YYYY-MM-DD HH24:MI:SS') as end_time,
       round((e.snap_time - b.snap_time) * 86400) as elapsed_s,
       case when b.startup_time = e.startup_time then 'YES' else 'NO - restart between snapshots, deltas invalid' end as same_instance,
       round((select delta from tm where stat_name = 'DB time') / 1e6, 1) as db_time_s,
       round((select delta from tm where stat_name = 'DB CPU') / 1e6, 1) as db_cpu_s,
       round((select delta from tm where stat_name = 'DB time') / 1e6 / nullif((e.snap_time - b.snap_time) * 86400, 0), 2) as avg_active_sessions,
       (select value from perfstat.stats$osstat o join perfstat.stats$osstatname n on n.osstat_id = o.osstat_id
         where o.snap_id = {{end_snap}} and n.stat_name = 'NUM_CPUS') as num_cpus
from b cross join e
join perfstat.stats$database_instance di
  on di.dbid = e.dbid and di.instance_number = e.instance_number and di.startup_time = e.startup_time;

-- @check: sp_load_profile | pdb | Load profile (per second and per transaction)
with d as (
  select en.name, en.value - bn.value as delta
  from perfstat.stats$sysstat bn
  join perfstat.stats$sysstat en on en.name = bn.name and en.snap_id = {{end_snap}}
                                and en.dbid = bn.dbid and en.instance_number = bn.instance_number
  where bn.snap_id = {{begin_snap}}
    and bn.name in ('redo size', 'session logical reads', 'physical reads', 'physical writes',
                    'user calls', 'parse count (total)', 'parse count (hard)', 'execute count',
                    'user commits', 'user rollbacks', 'logons cumulative', 'sorts (disk)',
                    'table scans (long tables)', 'redo synch writes')
),
el as (select (e.snap_time - b.snap_time) * 86400 as secs
       from perfstat.stats$snapshot b, perfstat.stats$snapshot e
       where b.snap_id = {{begin_snap}} and e.snap_id = {{end_snap}}),
tx as (select sum(delta) as n from d where name in ('user commits', 'user rollbacks'))
select /* db-diag-review */
       d.name as statistic, d.delta as total,
       round(d.delta / nullif(el.secs, 0), 1) as per_second,
       round(d.delta / nullif(tx.n, 0), 1) as per_txn
from d cross join el cross join tx
order by d.name;

-- @check: sp_efficiency | pdb | Instance efficiency ratios
with d as (
  select en.name, en.value - bn.value as delta
  from perfstat.stats$sysstat bn
  join perfstat.stats$sysstat en on en.name = bn.name and en.snap_id = {{end_snap}}
                                and en.dbid = bn.dbid and en.instance_number = bn.instance_number
  where bn.snap_id = {{begin_snap}}
),
v as (select max(case when name = 'session logical reads' then delta end) as lio,
             max(case when name = 'physical reads' then delta end) as pio,
             max(case when name = 'physical reads direct' then delta end) as pio_direct,
             max(case when name = 'physical reads direct (lob)' then delta end) as pio_lob,
             max(case when name = 'parse count (total)' then delta end) as parses,
             max(case when name = 'parse count (hard)' then delta end) as hard,
             max(case when name = 'execute count' then delta end) as execs,
             max(case when name = 'sorts (memory)' then delta end) as sort_mem,
             max(case when name = 'sorts (disk)' then delta end) as sort_disk,
             max(case when name = 'redo log space requests' then delta end) as redo_space_req
      from d)
select /* db-diag-review */
       round(100 * (1 - (pio - nvl(pio_direct, 0) - nvl(pio_lob, 0)) / nullif(lio, 0)), 2) as buffer_hit_pct,
       round(100 * (1 - hard / nullif(parses, 0)), 2) as soft_parse_pct,
       round(100 * (1 - parses / nullif(execs, 0)), 2) as execute_to_parse_pct,
       round(100 * sort_mem / nullif(sort_mem + sort_disk, 0), 2) as in_memory_sort_pct,
       redo_space_req as redo_log_space_requests
from v;

-- @check: sp_top_events | pdb | Top foreground timed events (incl. DB CPU)
with w as (
  select en.event, ec.wait_class,
         en.total_waits_fg - nvl(bn.total_waits_fg, 0) as waits,
         (en.time_waited_micro_fg - nvl(bn.time_waited_micro_fg, 0)) / 1e6 as secs
  from perfstat.stats$system_event en
  left join perfstat.stats$system_event bn
    on bn.event_id = en.event_id and bn.snap_id = {{begin_snap}}
   and bn.dbid = en.dbid and bn.instance_number = en.instance_number
  left join v$event_name ec on ec.event_id = en.event_id
  where en.snap_id = {{end_snap}}
    and en.event not in (select event from perfstat.stats$idle_event)
    and nvl(ec.wait_class, 'x') <> 'Idle'
),
cpu as (select (en.value - bn.value) / 1e6 as secs
        from perfstat.stats$sys_time_model bn
        join perfstat.stats$sys_time_model en on en.stat_id = bn.stat_id and en.snap_id = {{end_snap}}
        join perfstat.stats$time_model_statname n on n.stat_id = bn.stat_id
        where bn.snap_id = {{begin_snap}} and n.stat_name = 'DB CPU'),
dbt as (select (en.value - bn.value) / 1e6 as secs
        from perfstat.stats$sys_time_model bn
        join perfstat.stats$sys_time_model en on en.stat_id = bn.stat_id and en.snap_id = {{end_snap}}
        join perfstat.stats$time_model_statname n on n.stat_id = bn.stat_id
        where bn.snap_id = {{begin_snap}} and n.stat_name = 'DB time'),
u as (select event, wait_class, waits, secs from w where waits > 0
      union all
      select 'DB CPU', 'CPU', null, secs from cpu)
select /* db-diag-review */
       u.event, u.wait_class, u.waits, round(u.secs, 2) as time_s,
       round(1000 * u.secs / nullif(u.waits, 0), 2) as avg_ms,
       round(100 * u.secs / nullif(dbt.secs, 0), 1) as pct_db_time
from u cross join dbt
order by u.secs desc
fetch first 12 rows only;

-- @check: sp_time_model | pdb | Time model breakdown
select /* db-diag-review */
       n.stat_name, round((en.value - bn.value) / 1e6, 2) as secs,
       round(100 * (en.value - bn.value) / nullif(max(case when n.stat_name = 'DB time' then en.value - bn.value end) over (), 0), 1) as pct_db_time
from perfstat.stats$sys_time_model bn
join perfstat.stats$sys_time_model en on en.stat_id = bn.stat_id and en.snap_id = {{end_snap}}
join perfstat.stats$time_model_statname n on n.stat_id = bn.stat_id
where bn.snap_id = {{begin_snap}}
  and en.value - bn.value > 0
order by secs desc;

-- @check: sp_top_sql | pdb | Top SQL by elapsed time in the snapshot pair
-- SQL first captured in the end snapshot has no begin row, so its full counters count.
-- Statspack only stores SQL above its capture thresholds, so cheap statements may be absent.
select /* db-diag-review */
       en.sql_id, en.module,
       en.executions - nvl(bn.executions, 0) as execs,
       round((en.elapsed_time - nvl(bn.elapsed_time, 0)) / 1e6, 2) as elapsed_s,
       round((en.cpu_time - nvl(bn.cpu_time, 0)) / 1e6, 2) as cpu_s,
       round((en.user_io_wait_time - nvl(bn.user_io_wait_time, 0)) / 1e6, 2) as io_wait_s,
       round((en.concurrency_wait_time + en.application_wait_time
              - nvl(bn.concurrency_wait_time + bn.application_wait_time, 0)) / 1e6, 2) as lock_conc_wait_s,
       en.buffer_gets - nvl(bn.buffer_gets, 0) as buffer_gets,
       en.disk_reads - nvl(bn.disk_reads, 0) as disk_reads,
       en.parse_calls - nvl(bn.parse_calls, 0) as parses,
       substr(regexp_replace(nvl((select listagg(t.sql_text) within group (order by t.piece)
                                   from perfstat.stats$sqltext t
                                   where t.old_hash_value = en.old_hash_value and t.piece < 4),
                                 en.text_subset), '\s+', ' '), 1, 200) as sql_text
from perfstat.stats$sql_summary en
left join perfstat.stats$sql_summary bn
  on bn.snap_id = {{begin_snap}} and bn.dbid = en.dbid and bn.instance_number = en.instance_number
 and bn.old_hash_value = en.old_hash_value and bn.address = en.address
 and bn.elapsed_time <= en.elapsed_time
where en.snap_id = {{end_snap}}
order by elapsed_s desc
fetch first 10 rows only;

-- @check: sp_file_io | pdb | Tablespace I/O in the snapshot pair
select /* db-diag-review */
       en.tsname,
       sum(en.phyrds - nvl(bn.phyrds, 0)) as reads,
       round(10 * sum(en.readtim - nvl(bn.readtim, 0)) / nullif(sum(en.phyrds - nvl(bn.phyrds, 0)), 0), 2) as avg_read_ms,
       sum(en.phywrts - nvl(bn.phywrts, 0)) as writes,
       sum(en.wait_count - nvl(bn.wait_count, 0)) as buffer_waits
from perfstat.stats$filestatxs en
left join perfstat.stats$filestatxs bn
  on bn.snap_id = {{begin_snap}} and bn.dbid = en.dbid and bn.instance_number = en.instance_number
 and bn.filename = en.filename
where en.snap_id = {{end_snap}}
group by en.tsname
having sum(en.phyrds - nvl(bn.phyrds, 0)) + sum(en.phywrts - nvl(bn.phywrts, 0)) > 0
order by reads + writes desc;

-- @check: sp_host_cpu | pdb | Host CPU in the snapshot pair (from V$OSSTAT samples)
with o as (
  select n.stat_name, en.value - nvl(bn.value, 0) as delta, en.value as end_value
  from perfstat.stats$osstat en
  join perfstat.stats$osstatname n on n.osstat_id = en.osstat_id
  left join perfstat.stats$osstat bn
    on bn.osstat_id = en.osstat_id and bn.snap_id = {{begin_snap}}
   and bn.dbid = en.dbid and bn.instance_number = en.instance_number
  where en.snap_id = {{end_snap}}
)
select /* db-diag-review */
       max(case when stat_name = 'NUM_CPUS' then end_value end) as num_cpus,
       max(case when stat_name = 'LOAD' then end_value end) as load_at_end,
       round(100 * max(case when stat_name = 'BUSY_TIME' then delta end)
             / nullif(max(case when stat_name = 'BUSY_TIME' then delta end)
                      + max(case when stat_name = 'IDLE_TIME' then delta end), 0), 1) as host_busy_pct,
       round(100 * max(case when stat_name = 'IOWAIT_TIME' then delta end)
             / nullif(max(case when stat_name = 'BUSY_TIME' then delta end)
                      + max(case when stat_name = 'IDLE_TIME' then delta end), 0), 1) as host_iowait_pct,
       round(max(case when stat_name = 'PHYSICAL_MEMORY_BYTES' then end_value end) / 1073741824, 1) as host_mem_gb
from o;
