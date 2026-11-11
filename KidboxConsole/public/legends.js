function patchLegends() {
  const setV = (id,v) => { const e=document.getElementById(id); if(e) e.textContent=v; };
  setV('leg-free', document.getElementById('stat-families')?.textContent || '—');
  setV('leg-pro',  document.getElementById('stat-plan-pro')?.textContent || '—');
  setV('leg-max',  document.getElementById('stat-plan-max')?.textContent || '—');
  const ai = document.getElementById('stat-ai-cost')?.textContent || '—';
  const st = document.getElementById('stat-storage-cost')?.textContent || '—';
  setV('leg-ai-cost',      ai);
  setV('leg-storage-cost', st);
  setV('breakdown-ai',     ai);
  setV('breakdown-storage',st);
}
setInterval(patchLegends, 500);
