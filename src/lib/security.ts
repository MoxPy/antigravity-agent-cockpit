import type { EventItem, TurnItem, SummaryData, RiskLevel } from '../types';
import { formatDuration } from './formatters';

export function toArray<T>(val: any): T[] {
  if (Array.isArray(val)) return val;
  if (!val || typeof val !== "object") return [];
  const keys = Object.keys(val);
  if (keys.length === 0) return [];
  if (keys.every(k => !isNaN(Number(k)))) {
    return Object.values(val) as T[];
  }
  return [];
}

export function redactSecretPreview(preview: string, isMasked: boolean): string {
  if (!preview) return '';
  if (!isMasked) return preview;
  return '••••••••••••••••••••';
}

export function redactText(text: string, isMasked: boolean): string {
  if (!text) return '';
  if (!isMasked) return text;
  return text
    .replace(/gh[pousr]_[A-Za-z0-9_\*\[\]\-]+/gi, '••••••••••••••••••••')
    .replace(/sk-[A-Za-z0-9_\*\[\]\-]{8,}/gi, '••••••••••••••••••••')
    .replace(/AIza[A-Za-z0-9_\*\[\]\-]{12,}/gi, '••••••••••••••••••••')
    .replace(/AKIA[0-9A-Z\*\[\]\-]{8,}/gi, '••••••••••••••••••••')
    .replace(/(Bearer\s+)[A-Za-z0-9_\.\-\~]+/gi, '$1••••••••••••••••••••')
    .replace(/(token[=:]\s*["']?)[A-Za-z0-9_\-]+(["']?)/gi, '$1••••••••$2')
    .replace(/(password[=:]\s*["']?)[^"'\s]+(["']?)/gi, '$1••••••••$2')
    .replace(/(secret[=:]\s*["']?)[^"'\s]+(["']?)/gi, '$1••••••••$2')
    .replace(/(api[_-]?key[=:]\s*["']?)[^"'\s]+(["']?)/gi, '$1••••••••$2');
}

export function maskSecretString(str: string): string {
  return redactText(str, true);
}

export function assessSecurityRisk(ev: EventItem): void {
  if (ev.risk_level && ev.risk_level !== 'safe') return;

  const cmd = (ev.command || ev.details || '').toLowerCase();
  const target = (ev.target || '').toLowerCase();
  const reasons: string[] = [];
  let level: RiskLevel = 'safe';

  const flag = (lvl: RiskLevel, msg: string) => {
    reasons.push(msg);
    if (lvl === 'critical') level = 'critical';
    else if (lvl === 'high' && level !== 'critical') level = 'high';
    else if (lvl === 'medium' && level !== 'critical' && level !== 'high') level = 'medium';
    else if (lvl === 'low' && level === 'safe') level = 'low';
  };

  if (ev.category === 'terminal' || ev.tool === 'run_command') {
    // 1. Privilege Escalation
    if (/\b(sudo|su\s+-|doas)\b/i.test(cmd)) {
      flag('critical', 'Privilege escalation attempt detected (sudo / su / doas)');
    }

    // 2. Destructive Deletions & File Removal
    if (/\brm\b/i.test(cmd)) {
      const isRecursive = /-[a-z]*r[a-z]*f/i.test(cmd) || /-[a-z]*f[a-z]*r/i.test(cmd) || /--recursive/i.test(cmd) || /rm\s+-[a-z]*r/i.test(cmd);
      const isWildcardOrRoot = /\/\s*$/i.test(cmd) || /~/i.test(cmd) || /\.git/i.test(cmd) || /\s\*/i.test(cmd);

      if (isRecursive && isWildcardOrRoot) {
        flag('critical', 'Dangerous recursive deletion targeting root, home, .git or wildcards (rm -rf)');
      } else if (isRecursive) {
        flag('high', 'Recursive directory or force file deletion (rm -rf / rm -r)');
      } else if (/rm\s+-[a-z]*f/i.test(cmd) || /\s\*/i.test(cmd)) {
        flag('high', 'Force file deletion or wildcard removal (rm -f / rm *)');
      } else {
        flag('medium', 'File deletion operation (rm)');
      }
    } else if (/\b(rmdir|unlink|shred)\b/i.test(cmd)) {
      flag('medium', 'Directory or file removal operation (rmdir / unlink)');
    }

    // 3. Credentials & Secrets
    if (/(\.env[a-z._-]*|id_rsa|id_ed25519|\.aws\/|\.ssh\/|\.kube\/|credentials|password|api[_-]?key|secret)/i.test(cmd)) {
      flag('high', 'Access or manipulation of sensitive credentials, private keys, or environment configs');
    }
    if (/(\/etc\/passwd|\/etc\/shadow|\/etc\/hosts|\/etc\/sudoers)/i.test(cmd)) {
      flag('critical', 'System identity or network configuration access (/etc/...)');
    }

    // 4. Untrusted Network Execution
    if (/(curl\s+|wget\s+).*\|\s*(sh|bash|zsh|python)/i.test(cmd)) {
      flag('critical', 'Remote script download piped directly into execution shell (curl | bash)');
    }
    if (/(?:^|[;&|\s])nc\s+[-a-z0-9]|\b(netcat|ncat)\b|\/dev\/tcp\//i.test(cmd)) {
      flag('critical', 'Potential reverse shell or raw network socket command (nc / /dev/tcp)');
    }

    // 5. Destructive Git Commands
    if (/git\s+reset\s+--hard/i.test(cmd)) {
      flag('high', 'Destructive Git reset discarding uncommitted working tree (git reset --hard)');
    } else if (/git\s+clean\s+-[a-z]*f/i.test(cmd)) {
      flag('high', 'Force clean permanently removing untracked repository files (git clean -f)');
    } else if (/git\s+push\s+.*--force/i.test(cmd)) {
      flag('critical', 'Force pushing to remote git repository (git push --force)');
    }

    // 6. Permissions & Process Termination
    if (/kill\s+-9|pkill\s+-9|\bkillall\b/i.test(cmd)) {
      flag('medium', 'Forceful process termination (kill -9 / killall)');
    }
    if (/chmod\s+777|chmod\s+-[a-z]*r\s+777|chmod\s+\+s/i.test(cmd)) {
      flag('high', 'Insecure global write/SUID permissions assigned (chmod 777 / chmod +s)');
    }
  }

  // 7. Direct file tool access to sensitive paths
  if (['replace_file_content', 'multi_replace_file_content', 'write_to_file', 'view_file', 'read_file', 'grep_search'].includes(ev.tool || '')) {
    if (/(\.env|id_rsa|id_ed25519|\.aws|\.ssh|credentials|secret)/i.test(target)) {
      flag('high', `Tool accessed or modified sensitive configuration, credentials, or private keys: ${target || ev.tool}`);
    } else if (/\.git(\/|$)/i.test(target)) {
      flag('medium', 'Internal Git configuration or repository index accessed directly');
    }
  }

  // 8. Indirect Prompt Injection & Jailbreak Heuristics (Client-side defense-in-depth)
  const fullText = [cmd, target, (ev.summary || ''), (ev.title || '')].join(' ');
  const injectionRules: Array<{ type: string; sev: RiskLevel; pat: RegExp }> = [
    { type: 'Instruction Override', sev: 'critical', pat: /ignore\s+.*previous\s+instructions/i },
    { type: 'Instruction Override', sev: 'critical', pat: /ignore\s+.*prior\s+instructions/i },
    { type: 'Instruction Override', sev: 'critical', pat: /ignore\s+all\s+instructions/i },
    { type: 'Instruction Override', sev: 'critical', pat: /ignore\s+all\s+rules/i },
    { type: 'Instruction Override', sev: 'critical', pat: /disregard\s+.*previous\s+instructions/i },
    { type: 'Instruction Override', sev: 'critical', pat: /disregard\s+all\s+rules/i },
    { type: 'Instruction Override', sev: 'critical', pat: /forget\s+all\s+previous/i },
    { type: 'Instruction Override', sev: 'critical', pat: /system\s+override/i },
    { type: 'Instruction Override', sev: 'critical', pat: /system\s+directive\s+override/i },
    { type: 'Instruction Override', sev: 'critical', pat: /override\s+all\s+safety/i },
    { type: 'Instruction Override', sev: 'high',     pat: /new\s+system\s+instructions:/i },
    { type: 'Role Spoofing',        sev: 'high',     pat: /\[system\]|<system>|<\/system>|\[system_directive\]|\[developer_directive\]|<admin_directive>/i },
    { type: 'Role Spoofing',        sev: 'high',     pat: /system\s+prompt\s+override/i },
    { type: 'Jailbreak Signature',   sev: 'high',     pat: /dan\s+mode|do\s+anything\s+now|developer\s+mode\s+enabled/i },
    { type: 'Jailbreak Signature',   sev: 'medium',   pat: /unrestricted\s+mode/i },
    { type: 'Jailbreak Signature',   sev: 'high',     pat: /bypass\s+all\s+safety|without\s+moral\s+or\s+ethical\s+filters/i },
    { type: 'Data Exfiltration',    sev: 'critical', pat: /exfiltrate\s+.*to|send\s+.*to\s+https?:\/\/|webhook\.site/i },
    { type: 'Benign Canary Test',    sev: 'high',     pat: /TEST_BENIGN_CANARY_FLAG/i }
  ];

  for (const rule of injectionRules) {
    const match = fullText.match(rule.pat);
    if (match) {
      if (!ev.injection_finding) {
        ev.injection_finding = {
          type: rule.type,
          severity: rule.sev,
          source: ev.tool || ev.category || 'event',
          target: ev.target || ev.command,
          snippet: match[0],
          timestamp: ev.timestamp
        };
      }
      flag(rule.sev, `Prompt Injection / Jailbreak vector detected (${rule.type}): ${match[0]}`);
      break;
    }
  }

  ev.risk_level = level;
  ev.risk_reasons = reasons;
}

export function normalizeTurn(t: any): TurnItem {
  if (!t) return t;
  const events = toArray<EventItem>(t.events);
  let alertsCount = 0;
  let highRiskCount = 0;

  for (const ev of events) {
    assessSecurityRisk(ev);
    if (ev.risk_level && ev.risk_level !== 'safe') {
      alertsCount++;
      if (ev.risk_level === 'critical' || ev.risk_level === 'high') {
        highRiskCount++;
      }
    }
  }

  const start = t.timestamp;
  let end = t.ended_at;
  if (!end && events.length > 0) {
    const lastEv = events[events.length - 1];
    if (t.status === "completed" || lastEv.category === "response") {
      end = lastEv.timestamp;
    }
  }
  const durStr = t.duration_str || formatDuration(start, end);

  return {
    ...t,
    ended_at: end || t.ended_at,
    duration_str: durStr,
    events,
    security_alerts_count: Math.max(alertsCount, t.security_alerts_count || 0),
    high_risk_count: Math.max(highRiskCount, t.high_risk_count || 0),
    files_modified_list: toArray<string>(t.files_modified_list)
  };
}

export function normalizeSummary(s: any): SummaryData {
  if (!s) return s;
  const turns = toArray<any>(s.turns).map(normalizeTurn);
  let totalAlerts = 0;
  let totalHighRisk = 0;
  for (const t of turns) {
    totalAlerts += (t.security_alerts_count || 0);
    totalHighRisk += (t.high_risk_count || 0);
  }

  return {
    ...s,
    turns,
    security_alerts_count: totalAlerts || s.security_alerts_count || 0,
    high_risk_count: totalHighRisk || s.high_risk_count || 0,
    active_turn: s.active_turn ? normalizeTurn(s.active_turn) : (turns[turns.length - 1] || null),
    files_modified: toArray<string>(s.files_modified),
    recent_events: toArray<EventItem>(s.recent_events).map(ev => {
      assessSecurityRisk(ev);
      return ev;
    }),
    security_audit: {
      secrets: toArray(s.security_audit?.secrets),
      boundary_escapes: toArray(s.security_audit?.boundary_escapes),
      network_egress: toArray(s.security_audit?.network_egress),
      packages: toArray(s.security_audit?.packages),
      injections: toArray(s.security_audit?.injections)
    }
  };
}
