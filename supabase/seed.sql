begin;

do $synthetic_seed$
begin
  raise notice
    'Synthetic seed entry point is active. Domain inserts are deferred until the first approved domain migration. Canonical fixture: tests/fixtures/synthetic-baseline.v1.json';
end
$synthetic_seed$;

commit;