-- Run this against jhcisdb to discover useful source tables and columns.
-- This script does not read patient rows. It only reads database metadata.

SELECT
  table_name,
  table_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND (
    table_name LIKE '%person%'
    OR table_name LIKE '%patient%'
    OR table_name LIKE '%visit%'
    OR table_name LIKE '%service%'
    OR table_name LIKE '%diag%'
    OR table_name LIKE '%chronic%'
    OR table_name LIKE '%clinic%'
    OR table_name LIKE '%anc%'
    OR table_name LIKE '%vaccine%'
    OR table_name LIKE '%epi%'
    OR table_name LIKE '%home%'
    OR table_name LIKE '%refer%'
    OR table_name LIKE '%er%'
    OR table_name LIKE '%lab%'
  )
ORDER BY table_name;

SELECT
  table_name,
  column_name,
  data_type
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND (
    column_name LIKE '%cid%'
    OR column_name LIKE '%pid%'
    OR column_name LIKE '%hn%'
    OR column_name LIKE '%visit%'
    OR column_name LIKE '%date%'
    OR column_name LIKE '%vst%'
    OR column_name LIKE '%diag%'
    OR column_name LIKE '%icd%'
    OR column_name LIKE '%clinic%'
    OR column_name LIKE '%anc%'
    OR column_name LIKE '%vaccine%'
    OR column_name LIKE '%refer%'
  )
ORDER BY table_name, ordinal_position;
