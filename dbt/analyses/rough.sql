-- Show the database and schema configured for this dbt environment.
select
    '{{ target.database }}' as dbt_target_database,
    '{{ target.schema }}' as dbt_target_schema,
    current_role() as active_role