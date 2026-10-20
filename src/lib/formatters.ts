export function formatDuration(startStr?: string, endStr?: string): string {
  if (!startStr) return "";
  try {
    const tStart = new Date(startStr).getTime();
    if (isNaN(tStart)) return "";
    const tEnd = endStr ? new Date(endStr).getTime() : Date.now();
    if (isNaN(tEnd) || tEnd < tStart) return "0s";
    const diffSec = Math.floor((tEnd - tStart) / 1000);
    if (diffSec < 60) return `${diffSec}s`;
    const m = Math.floor(diffSec / 60);
    const s = diffSec % 60;
    if (m < 60) return `${m}m ${s}s`;
    const h = Math.floor(m / 60);
    const remM = m % 60;
    return `${h}h ${remM}m`;
  } catch {
    return "";
  }
}

export function formatLocalTime(isoStr: string): string {
  if (!isoStr) return '';
  try {
    const d = new Date(isoStr);
    if (isNaN(d.getTime())) {
      const match = isoStr.match(/(\d{2}:\d{2}:\d{2})/);
      return match ? match[1] : isoStr;
    }
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
  } catch {
    return isoStr;
  }
}

export function formatFullCommand(cmd: string): string {
  if (!cmd) return '';
  return cmd.replace(/\n+/g, '\n').trim();
}

export function truncate(str: string, maxLen: number): string {
  if (!str) return '';
  return str.length > maxLen ? str.slice(0, maxLen) + '...' : str;
}

export async function copyToClipboard(text: string): Promise<boolean> {
  if (!text) return false;
  try {
    if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    document.body.removeChild(ta);
    return true;
  } catch (err) {
    console.error('Clipboard copy failed', err);
    return false;
  }
}
