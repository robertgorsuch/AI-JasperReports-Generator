SELECT
  f.uri || '/' || r.name AS dashboard_uri,
  r.label,
  COALESCE(own.user_id, la.first_user, 'n/a') AS owner,
  r.creation_date AS created,
  r.update_date AS last_modified,
  la.last_accessed,
  COALESCE(la.last_accessed_by, '-') AS last_accessed_by,
  COALESCE(la.access_count, 0) AS access_count
FROM jiresource r
JOIN jiresourcefolder f ON r.parent_folder = f.id
LEFT JOIN (
  SELECT resource_uri,
         MAX(event_date) AS last_accessed,
         COUNT(*) AS access_count,
         (array_agg(user_id ORDER BY event_date DESC))[1] AS last_accessed_by,
         (array_agg(user_id ORDER BY event_date ASC))[1]  AS first_user
  FROM jiaccessevent
  GROUP BY resource_uri
) la ON la.resource_uri = f.uri || '/' || r.name
LEFT JOIN (
  SELECT DISTINCT ON (resource_uri) resource_uri, user_id
  FROM jiaccessevent
  WHERE updating = true
  ORDER BY resource_uri, event_date ASC
) own ON own.resource_uri = f.uri || '/' || r.name
WHERE r.resourcetype = 'com.jaspersoft.ji.dashboard.DashboardModelResource'
ORDER BY la.last_accessed DESC NULLS LAST, r.label
