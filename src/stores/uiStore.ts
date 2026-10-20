import { writable } from 'svelte/store';
import type { ViewMode, TurnItem, EventItem } from '../types';

export const viewMode = writable<ViewMode>('turns');
export const selectedTurnId = writable<number | null>(null);
export const selectedStep = writable<EventItem | null>(null);

export const showTurnsNav = writable<boolean>(true);
export const showInspector = writable<boolean>(true);
export const collapseOverview = writable<boolean>(false);
export const maskSecrets = writable<boolean>(true);

export const toastMessage = writable<string | null>(null);

export const showVaultModal = writable<boolean>(false);
export const vaultReportContent = writable<string | null>(null);
export const vaultReportFilename = writable<string | null>(null);

let toastTimer: any = null;
export function showToast(msg: string, durationMs = 2500) {
  toastMessage.set(msg);
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toastMessage.set(null);
    toastTimer = null;
  }, durationMs);
}

export function selectTurn(turn: TurnItem) {
  if (!turn) return;
  selectedTurnId.set(turn.id);
  const evs = Array.isArray(turn.events) ? turn.events : [];
  if (evs.length > 0) {
    // Prioritize selecting the first flagged step (prompt injection or security alert)
    // so returning to a turn immediately restores and displays the security flag in the inspector!
    const flaggedStep = evs.find((e) => e.injection_finding || (e.risk_level && e.risk_level !== 'safe'));
    selectedStep.set(flaggedStep || evs[evs.length - 1]);
  } else {
    selectedStep.set(null);
  }
}

export function selectStep(step: EventItem) {
  selectedStep.set(step);
}

export function jumpToStep(stepIndex: number, turnId?: number, turnsList?: TurnItem[]) {
  viewMode.set('turns');

  let targetTurn: TurnItem | null = null;
  let targetStep: EventItem | null = null;

  if (turnsList && turnsList.length > 0) {
    if (turnId) {
      targetTurn = turnsList.find((t) => t.id === turnId) || null;
    }
    // Search across all turns to locate step if turnId is missing or not matched
    if (!targetTurn) {
      for (const t of turnsList) {
        if (t.events) {
          const match = t.events.find((e) => e.step === stepIndex);
          if (match) {
            targetTurn = t;
            targetStep = match;
            break;
          }
        }
      }
    }
  }

  if (targetTurn) {
    selectedTurnId.set(targetTurn.id);
    if (!targetStep && targetTurn.events) {
      targetStep = targetTurn.events.find((e) => e.step === stepIndex) || null;
    }
    if (targetStep) {
      selectedStep.set(targetStep);
    } else if (targetTurn.events && targetTurn.events.length > 0) {
      selectedStep.set(targetTurn.events[0]);
    }
    setTimeout(() => {
      const el = document.getElementById(`step-card-${stepIndex}`);
      if (el) {
        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    }, 100);
  }
}
