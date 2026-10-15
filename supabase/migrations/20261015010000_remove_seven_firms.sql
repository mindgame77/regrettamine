-- Alex removed Accel, Bain Capital Ventures, Battery Ventures, Bessemer Venture Partners,
-- Insight Partners, Khosla Ventures and Lux Capital on Oct 14, 2026. Their rows were deleted on
-- live (backup: toxybase/backups/2026-10-14-delete-7). This keeps fresh databases in step:
-- the rank-row name strings that only those firms used are dropped.
delete from public.ui_strings where key in (
  'report.insight_partners', 'report.bessemer_venture_partners', 'report.battery_ventures',
  'report.bain_capital_ventures', 'report.khosla_ventures', 'report.lux_capital'
);
