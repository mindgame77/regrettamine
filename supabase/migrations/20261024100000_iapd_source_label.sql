-- Source labels for SEC IAPD pages were stored as the raw host (e.g. 'reports.adviserinfo.sec.gov'), which the
-- /full/ hero showed verbatim (accel). Name them 'SEC IAPD' like a16z. Only rows whose label/publisher equals the
-- host itself are changed, so revert is: set label = domain (fact_sources) / publisher = domain (sources) for these hosts.
update fact_sources fs set label = 'SEC IAPD'
  from sources s
 where s.id = fs.source_id and s.domain in ('reports.adviserinfo.sec.gov', 'files.adviserinfo.sec.gov', 'api.adviserinfo.sec.gov')
   and fs.label = s.domain;
update sources set publisher = 'SEC IAPD'
 where domain in ('reports.adviserinfo.sec.gov', 'files.adviserinfo.sec.gov', 'api.adviserinfo.sec.gov')
   and publisher = domain;
