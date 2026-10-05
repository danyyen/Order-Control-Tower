select
    source_filename,
    source_file_row_number,
    snapshot_date,
    production_date,
    best_before_date
from {{ source('order_intelligence_raw', 'inventory') }}
where pallet_number is not null
  and (
      snapshot_date is null
      or snapshot_date <> trunc(snapshot_date)
      or not regexp_like(snapshot_date::varchar, '[0-9]{8}')
      or try_to_date(snapshot_date::varchar, 'YYYYMMDD') is null

      or (
          production_date is not null
          and (
              production_date <> trunc(production_date)
              or not regexp_like(
                  trunc(production_date)::varchar, '[0-9]{8}'
              )
              or try_to_date(
                  trunc(production_date)::varchar, 'YYYYMMDD'
              ) is null
          )
      )

      or (
          best_before_date is not null
          and (
              best_before_date <> trunc(best_before_date)
              or not regexp_like(
                  trunc(best_before_date)::varchar, '[0-9]{8}'
              )
              or try_to_date(
                  trunc(best_before_date)::varchar, 'YYYYMMDD'
              ) is null
          )
      )
  )