import { writable, get } from "svelte/store";
import { invoke } from "../tauri-bridge";
import type { SummaryData, RadarRepo, ReportItem, TurnItem, SessionInfo } from "../types";
import { normalizeSummary, toArray } from "../lib/security";
import { selectedTurnId, selectedStep, showToast, showVaultModal, vaultReportContent, vaultReportFilename } from "./uiStore";

const initialSummary: SummaryData = {
  total_steps: 0,
  total_turns: 0,
  session_uuid: "",
  category_counts: { terminal: 0, mutation: 0, inspect: 0, thought: 0, user: 0, response: 0 },
  total_thoughts: 0,
  security_alerts_count: 0,
  high_risk_count: 0,
  security_audit: { secrets: [], boundary_escapes: [], network_egress: [], packages: [], injections: [] },
  turns: [],
  active_turn: null,
  files_modified: [],
  recent_events: [],
  workspace_root: ""
};

export const summary = writable<SummaryData>(initialSummary);
export const radar = writable<RadarRepo[]>([]);
export const reports = writable<ReportItem[]>([]);
export const statusMsg = writable<string>("Connecting...");
export const isExporting = writable<boolean>(false);
export const sessions = writable<SessionInfo[]>([]);
export const selectedSessionId = writable<string>("");
export const isLoadingSession = writable<boolean>(false);

let isPolling = false;

export function updateStatus() {
  const s = get(summary);
  const curSel = get(selectedSessionId);
  const sessList = get(sessions);
  const isLatest = sessList.length > 0 && sessList[0].session_uuid === curSel;
  
  if (s.total_steps > 0) {
    statusMsg.set(`${isLatest ? "Live" : "Archive"} • ${s.total_steps} steps`);
  } else {
    statusMsg.set(isLatest ? "Live" : "Ready");
  }
}

function applySummary(rawSummary: any) {
  if (!rawSummary) return;
  const current = get(summary);
  const normalized = normalizeSummary(rawSummary);

  const isSameSession = (current.session_uuid === normalized.session_uuid);

  // Preserve existing cached events ONLY if we stay within the same session
  if (isSameSession && current.turns && current.turns.length > 0) {
    const map = new Map<number, any[]>();
    for (const t of current.turns) {
      if (t.events && t.events.length > 0) map.set(t.id, t.events);
    }
    for (const t of normalized.turns) {
      if (map.has(t.id) && (!t.events || t.events.length === 0)) {
        t.events = map.get(t.id)!;
      }
    }
  }

  summary.set(normalized);

  // Auto-select latest populated turn if none is selected or if session changed
  const curSelectedId = isSameSession ? get(selectedTurnId) : null;
  if ((curSelectedId === null || !normalized.turns.some((t: TurnItem) => t.id === curSelectedId)) && normalized.turns.length > 0) {
    const populated = normalized.turns.filter((t: TurnItem) => (t.events_count > 0 || (t.events && t.events.length > 0)));
    if (populated.length > 0) {
      selectedTurnId.set(populated[populated.length - 1].id);
    } else {
      selectedTurnId.set(normalized.active_turn ? normalized.active_turn.id : normalized.turns[normalized.turns.length - 1].id);
    }
  }

  // Auto-select latest step in the turn
  const updatedSelectedId = get(selectedTurnId);
  const curTurn = normalized.turns.find((t: TurnItem) => t.id === updatedSelectedId) || normalized.active_turn;
  if (curTurn) {
    const evs = toArray(curTurn.events);
    const curStep = get(selectedStep);
    if (evs.length > 0) {
      if (!isSameSession || !curStep || !evs.some(e => e.step === curStep.step)) {
        const flaggedStep = evs.find((e: any) => e.injection_finding || (e.risk_level && e.risk_level !== "safe"));
        selectedStep.set(flaggedStep || evs[evs.length - 1]);
      }
    } else {
      selectedStep.set(null);
    }
  } else {
    selectedStep.set(null);
  }
}

export async function initSession(retryCount = 0): Promise<void> {
  try {
    const initData = await invoke("flight:get_summary");
    if (initData) {
      if (initData.sessions) sessions.set(toArray(initData.sessions));
      const activeId = initData.current_session_id || initData.selected_session || initData.summary?.session_uuid;
      if (activeId) selectedSessionId.set(activeId);
      if (initData.summary) applySummary(initData.summary);
      if (initData.radar) radar.set(toArray(initData.radar));
      if (initData.reports) reports.set(toArray(initData.reports));
      updateStatus();
      return;
    }
  } catch (err: any) {
    if (retryCount < 8) {
      statusMsg.set("Connecting...");
      setTimeout(() => initSession(retryCount + 1), 250);
      return;
    }
    statusMsg.set("Offline");
  }
}

export async function pollSession(): Promise<void> {
  if (isPolling || get(isLoadingSession)) return;
  isPolling = true;
  try {
    const curSummary = get(summary);
    const curSel = get(selectedSessionId);
    if (!curSel) return;

    const res = await invoke("flight:poll_updates", {
      last_step: curSummary.total_steps,
      session_id: curSel
    });
    if (res) {
      if (res.reports) reports.set(toArray(res.reports));
      if (res.has_new_events && res.summary && res.current_session_id === curSel) {
        applySummary(res.summary);
      }
      updateStatus();
    }
  } catch {
    statusMsg.set("Reconnecting...");
  } finally {
    isPolling = false;
  }
}

export async function exportReport(turnId?: number): Promise<void> {
  isExporting.set(true);
  try {
    const res = await invoke("flight:export_report", turnId ? { turn_id: turnId } : {});
    if (res) {
      if (res.reports) reports.set(toArray(res.reports));
      if (res.export && res.export.filename) {
        showToast(`Audit report saved: ${res.export.filename}`);
      } else {
        showToast("Audit report generated successfully");
      }
    }
  } catch (err: any) {
    showToast(`Export failed: ${err?.message || err}`);
  } finally {
    isExporting.set(false);
  }
}

export async function viewReport(filename: string): Promise<void> {
  try {
    const res = await invoke("flight:read_report", { filename });
    if (res && res.content) {
      vaultReportContent.set(res.content);
      vaultReportFilename.set(filename);
      showVaultModal.set(true);
    } else {
      showToast("Could not read report content");
    }
  } catch {
    showToast("Failed to open report");
  }
}

export async function revealReport(filename: string): Promise<void> {
  try {
    const res = await invoke("flight:reveal_report", { filename });
    if (res && res.status === "ok") {
      showToast(`Revealed in Finder: ${filename}`);
    }
  } catch {
    showToast("Failed to reveal file in Finder");
  }
}

export async function fetchSessions(): Promise<void> {
  try {
    const res = await invoke("flight:list_sessions");
    if (res && res.sessions) {
      sessions.set(res.sessions);
    }
  } catch (e) {
    console.error("Failed to list sessions", e);
  }
}

export async function switchSession(targetUuid: string): Promise<void> {
  if (!targetUuid) return;
  selectedSessionId.set(targetUuid);
  isLoadingSession.set(true);

  try {
    const res = await invoke("flight:switch_session", { session_id: targetUuid });
    if (res && res.summary) {
      selectedTurnId.set(null);
      selectedStep.set(null);
      applySummary(res.summary);
      if (res.sessions) sessions.set(toArray(res.sessions));
      selectedSessionId.set(res.current_session_id || res.selected_session || targetUuid);
      updateStatus();
      showToast(`Switched to: ${targetUuid.slice(0, 8)}`);
    } else {
      showToast("No data for this conversation");
    }
  } catch (err: any) {
    showToast(`Switch failed: ${err?.message || err}`);
  } finally {
    isLoadingSession.set(false);
  }
}
