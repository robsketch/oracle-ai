-- db-health-check diagnostic queries
-- Licensing: standard V$ / DBA_ views only. Nothing here needs the Diagnostics or Tuning Pack
-- (no DBA_HIST_*, V$ACTIVE_SESSION_HISTORY, ADDM, V$SQL_MONITOR, DBMS_WORKLOAD_REPOSITORY).
-- Each check is one read-only statement, run separately via the MCP sql_run tool.
-- The "-- @check: <id> | <title>" line marks the start of each check. Every statement carries
-- the /* db-health-check */ tag so top_sql can exclude the health check's own queries.

-- @check: instance | Instance and database
select /* db-health-check */
       i.instance_name, i.host_name, i.version_full, i.status, i.database_status,
       to_char(i.startup_time, 'YYYY-MM-DD HH24:MI') as startup_time,
       round(sysdate - i.startup_time, 1) as uptime_days,
       d.name as cdb_name, sys_context('USERENV', 'CON_NAME') as connected_container,
       d.log_mode, d.open_mode, d.database_role, d.force_logging, d.flashback_on,
       (select banner from v$version where rownum = 1) as banner
from v$instance i cross join v$database d;

-- @check: pdbs | Pluggable databases
select /* db-health-check */
       con_id, name, open_mode, restricted, round(total_size / 1048576) as size_mb
from v$pdbs
order by con_id;

-- @check: capacity | Allocated datafile / tempfile space
select /* db-health-check */
       (select round(sum(bytes) / 1048576) from dba_data_files) as datafile_mb,
       (select round(sum(bytes) / 1048576) from dba_data_files
         where tablespace_name not in ('SYSTEM', 'SYSAUX')
           and tablespace_name not in (select tablespace_name from dba_tablespaces where contents = 'UNDO')) as user_datafile_mb,
       (select round(sum(bytes) / 1048576) from dba_temp_files) as tempfile_mb
from dual;

-- @check: tablespaces | Tablespace usage (vs. max size incl. autoextend)
select /* db-health-check */
       m.tablespace_name, t.contents, t.bigfile,
       round(m.used_space * t.block_size / 1048576) as used_mb,
       a.alloc_mb,
       round(m.tablespace_size * t.block_size / 1048576) as max_mb,
       round(m.used_percent, 1) as used_pct_of_max
from dba_tablespace_usage_metrics m
join dba_tablespaces t on t.tablespace_name = m.tablespace_name
left join (select tablespace_name, round(sum(bytes) / 1048576) as alloc_mb from dba_data_files group by tablespace_name
           union all
           select tablespace_name, round(sum(bytes) / 1048576) from dba_temp_files group by tablespace_name) a
       on a.tablespace_name = m.tablespace_name
order by m.used_percent desc;

-- @check: fra | Fast recovery area usage (no rows = no FRA configured)
select /* db-health-check */
       name,
       round(space_limit / 1048576) as limit_mb,
       round(space_used / 1048576) as used_mb,
       round(space_reclaimable / 1048576) as reclaimable_mb,
       round(100 * (space_used - space_reclaimable) / nullif(space_limit, 0), 1) as net_used_pct,
       number_of_files
from v$recovery_file_dest;

-- @check: archiving | Archive destinations and archived redo volume (last 24h)
select /* db-health-check */
       d.dest_id, d.dest_name, d.status, d.destination, d.error,
       (select count(*) from v$archived_log where first_time > sysdate - 1) as archived_logs_24h,
       (select round(sum(blocks * block_size) / 1048576) from v$archived_log where first_time > sysdate - 1) as archived_mb_24h
from v$archive_dest d
where d.status <> 'INACTIVE'
order by d.dest_id;

-- @check: redo | Redo log groups and switch rate (last 24h)
select /* db-health-check */
       l.group#, l.thread#, l.members, round(l.bytes / 1048576) as size_mb, l.status, l.archived,
       (select count(*) from v$log_history h where h.first_time > sysdate - 1) as switches_24h,
       (select max(count(*)) from v$log_history h where h.first_time > sysdate - 1
         group by trunc(h.first_time, 'HH24')) as peak_switches_per_hour
from v$log l
order by l.group#;

-- @check: memory | SGA / PGA usage and memory parameters
select /* db-health-check */ 'SGA total (MB)' as metric, to_char(round(sum(value) / 1048576)) as value from v$sga
union all
select 'PGA allocated (MB)', to_char(round(value / 1048576)) from v$pgastat where name = 'total PGA allocated'
union all
select 'PGA max allocated (MB)', to_char(round(value / 1048576)) from v$pgastat where name = 'maximum PGA allocated'
union all
select 'PGA over-allocation count', to_char(value) from v$pgastat where name = 'over allocation count'
union all
select 'param ' || name, display_value from v$parameter
where name in ('sga_target', 'sga_max_size', 'pga_aggregate_target', 'pga_aggregate_limit', 'memory_target');

-- @check: limits | Process / session counts vs. limits
-- (V$RESOURCE_LIMIT is empty when connected to a PDB, so count directly.)
select /* db-health-check */ 'processes' as resource_name,
       (select count(*) from v$process) as current_count,
       (select to_number(value) from v$parameter where name = 'processes') as limit_value
from dual
union all
select 'sessions',
       (select count(*) from v$session),
       (select to_number(value) from v$parameter where name = 'sessions')
from dual;

-- @check: sessions | Session summary
select /* db-health-check */
       type, status, count(*) as sessions,
       sum(case when type = 'USER' and status = 'ACTIVE' and last_call_et > 300 then 1 else 0 end) as user_active_over_5m
from v$session
group by type, status
order by type, status;

-- @check: blocking | Blocking and blocked sessions (no rows = no blocking)
select /* db-health-check */
       s.sid, s.serial#, s.username, s.program, s.status, s.event,
       s.blocking_session, s.final_blocking_session,
       round(s.wait_time_micro / 1e6) as wait_secs, s.sql_id
from v$session s
where s.blocking_session is not null
   or s.sid in (select blocking_session from v$session where blocking_session is not null)
order by s.final_blocking_session nulls first, s.sid;

-- @check: long_running | Long-running active user calls (> 60s)
select /* db-health-check */
       sid, serial#, username, program, sql_id, event, last_call_et as secs_in_call
from v$session
where type = 'USER' and status = 'ACTIVE' and last_call_et > 60
  and sid <> sys_context('USERENV', 'SID')
order by last_call_et desc
fetch first 10 rows only;

-- @check: top_sql | Top 10 SQL by elapsed time (cumulative, from shared pool)
select /* db-health-check */
       sql_id, parsing_schema_name as schema_name, module, executions,
       round(elapsed_time / 1e6, 1) as elapsed_s,
       round(cpu_time / 1e6, 1) as cpu_s,
       round(elapsed_time / nullif(executions, 0) / 1000, 1) as avg_ms,
       buffer_gets, disk_reads,
       substr(regexp_replace(sql_text, '\s+', ' '), 1, 80) as sql_text
from v$sql
where parsing_schema_name not in ('SYS')
  and sql_text not like '%db-health-check%'
order by elapsed_time desc
fetch first 10 rows only;

-- @check: waits | Top 10 non-idle wait events since startup
select /* db-health-check */
       event, wait_class, total_waits,
       round(time_waited_micro / 1e6, 1) as time_waited_s,
       round(time_waited_micro / nullif(total_waits, 0) / 1000, 2) as avg_wait_ms
from v$system_event
where wait_class <> 'Idle'
order by time_waited_micro desc
fetch first 10 rows only;

-- @check: invalid_objects | Invalid objects by owner/type (no rows = none)
select /* db-health-check */
       o.owner, o.object_type, count(*) as invalid_count, u.oracle_maintained
from dba_objects o
join dba_users u on u.username = o.owner
where o.status = 'INVALID'
group by o.owner, o.object_type, u.oracle_maintained
order by u.oracle_maintained, invalid_count desc;

-- @check: alert_log | Alert log errors in last 24h (no rows = clean)
select /* db-health-check */
       to_char(max(originating_timestamp), 'YYYY-MM-DD HH24:MI') as last_seen,
       count(*) as occurrences,
       substr(regexp_replace(message_text, '\s+', ' '), 1, 150) as message
from v$diag_alert_ext
where originating_timestamp > systimestamp - interval '1' day
  and regexp_like(message_text, 'ORA-|TNS-|error|fatal|deadlock|checkpoint not complete|cannot allocate', 'i')
group by substr(regexp_replace(message_text, '\s+', ' '), 1, 150)
order by occurrences desc
fetch first 20 rows only;

-- @check: backups | RMAN backup jobs (last 7 days; no rows = no backups)
select /* db-health-check */
       to_char(start_time, 'YYYY-MM-DD HH24:MI') as started, input_type, status,
       round(elapsed_seconds / 60, 1) as mins, output_bytes_display
from v$rman_backup_job_details
where start_time > sysdate - 7
order by start_time desc;

-- @check: jobs | Failed scheduler job runs (last 24h; no rows = none)
select /* db-health-check */
       owner, job_name, status, error#,
       to_char(log_date, 'YYYY-MM-DD HH24:MI') as log_date,
       substr(additional_info, 1, 120) as info
from dba_scheduler_job_run_details
where log_date > systimestamp - interval '1' day
  and status <> 'SUCCEEDED'
order by log_date desc
fetch first 20 rows only;

-- @check: users | Non-Oracle accounts locked, expired, or expiring within 14 days (no rows = none)
select /* db-health-check */
       username, account_status,
       to_char(expiry_date, 'YYYY-MM-DD') as expiry_date,
       to_char(lock_date, 'YYYY-MM-DD') as lock_date,
       profile
from dba_users
where oracle_maintained = 'N'
  and (account_status <> 'OPEN' or expiry_date < sysdate + 14)
order by username;

-- @check: stats | Stale or missing optimizer statistics (non-Oracle schemas)
select /* db-health-check */
       s.owner,
       sum(case when s.stale_stats = 'YES' then 1 else 0 end) as stale_tables,
       sum(case when s.last_analyzed is null then 1 else 0 end) as never_analyzed,
       count(*) as total_tables
from dba_tab_statistics s
join dba_users u on u.username = s.owner
where u.oracle_maintained = 'N' and s.object_type = 'TABLE'
group by s.owner
order by s.owner;

-- @check: parameters | Key initialization parameters
select /* db-health-check */
       name, display_value, isdefault
from v$parameter
where name in ('processes', 'sessions', 'open_cursors', 'undo_retention', 'db_recovery_file_dest',
               'db_recovery_file_dest_size', 'statistics_level', 'control_management_pack_access',
               'audit_trail', 'optimizer_features_enable', 'compatible')
order by name;
