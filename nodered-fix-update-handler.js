// Fixed "Handle Install → Exec" function node code
// Replace the content of your upd_fn_route_action function node with this:

if (msg && msg.action === 'install' && msg.target === 'dashboard') {
  const ver = msg.version || flow.get('latest_dashboard_version');
  node.status({fill:'blue',shape:'dot',text:`Installing ${ver}…`});
  
  // FIXED: Remove the extra escaping quotes
  msg.payload = `/opt/scripts/update_dashboard.sh ${ver}`;
  
  return [msg, {payload:`Installing Dashboard ${ver}…` }];
}
return [null, {payload:'No action'}];
