<script lang="ts">
  import { summary } from '../stores/sessionStore';
  import { selectedTurnId, showTurnsNav, selectTurn } from '../stores/uiStore';
  import { formatLocalTime, formatDuration } from '../lib/formatters';
  import { toArray } from '../lib/security';
  import type { TurnItem } from '../types';
  import Icon from './Icon.svelte';

  let turnSearch = '';

  $: filteredTurns = toArray<TurnItem>($summary.turns).filter((t: TurnItem) => {
    if (!turnSearch.trim()) return true;
    const q = turnSearch.toLowerCase();
    const files = toArray<string>(t.files_modified_list);
    return (
      (t.prompt && t.prompt.toLowerCase().includes(q)) ||
      (t.raw_prompt && t.raw_prompt.toLowerCase().includes(q)) ||
      t.id.toString().includes(q) ||
      files.some(f => f.toLowerCase().includes(q))
    );
  }).slice().reverse();
</script>

<aside class="turns-nav-pane" aria-label="Conversation Turns Navigation">
  <div class="pane-header">
    <div class="pane-header-title-group">
      <Icon name="layers" size={14} color="#8ab4f8" />
      <span class="pane-title">Turns</span>
      <span class="pane-counter">{filteredTurns.length}</span>
    </div>
    <button
      class="btn-pane-close"
      on:click={() => $showTurnsNav = false}
      title="Collapse Turns Navigator"
      aria-label="Collapse Turns Navigator"
    >
      <Icon name="chevron-left" size={14} />
    </button>
  </div>

  <div class="search-bar">
    <div class="google-search-wrap">
      <Icon name="search" size={14} className="search-icon" color="#9aa0a6" />
      <input
        type="text"
        class="input-google-search"
        placeholder="Filter turns or files..."
        bind:value={turnSearch}
      />
      {#if turnSearch}
        <button class="search-clear-btn" on:click={() => turnSearch = ''}>
          <Icon name="close" size={12} />
        </button>
      {/if}
    </div>
  </div>

  <div class="turns-scroll-list">
    {#if filteredTurns.length === 0}
      <div class="empty-state">
        <Icon name="search" size={24} color="#5f6368" />
        <span>No conversation turns found.</span>
      </div>
    {:else}
      {#each filteredTurns as turn (turn.id)}
        <!-- svelte-ignore a11y-click-events-have-key-events -->
        <!-- svelte-ignore a11y-no-static-element-interactions -->
        <div
          class="turn-card"
          class:selected={$selectedTurnId === turn.id}
          class:turn-active={turn.status === 'in_progress'}
          on:click={() => selectTurn(turn)}
        >
          <div class="turn-card-top">
            <div class="turn-num-wrap">
              <span class="turn-num">Turn #{turn.id}</span>
              {#if turn.status === 'in_progress'}
                <span class="turn-badge badge-active">
                  <span class="pulse-dot"></span>
                  Active
                </span>
              {:else}
                <span class="turn-badge badge-done">Done</span>
              {/if}
              {#if turn.duration_str || formatDuration(turn.timestamp, turn.ended_at)}
                <span class="turn-badge badge-duration" title="Durata turno: {turn.duration_str || formatDuration(turn.timestamp, turn.ended_at)}">
                  ⏱️ {turn.duration_str || formatDuration(turn.timestamp, turn.ended_at)}
                </span>
              {/if}
            </div>
            <div class="turn-time-group">
              <span class="turn-time">{formatLocalTime(turn.timestamp)}</span>
              {#if turn.ended_at && turn.ended_at !== turn.timestamp}
                <span class="turn-ended-time" title="Finito alle {formatLocalTime(turn.ended_at)}">→ {formatLocalTime(turn.ended_at)}</span>
              {/if}
            </div>
          </div>

          <div class="turn-prompt-preview">
            "{turn.prompt || turn.raw_prompt || 'Empty prompt'}"
          </div>

          <div class="turn-card-meta">
            <span class="meta-chip">
              <Icon name="terminal" size={10} color="#9aa0a6" />
              <span>{turn.events_count} ops</span>
            </span>

            {#if (turn.security_alerts_count && turn.security_alerts_count > 0) || (turn.events && turn.events.some(e => e.injection_finding || (e.risk_level && e.risk_level !== 'safe')))}
              <span class="meta-chip chip-alert" title="{turn.security_alerts_count || 'Security'} security alerts in this turn">
                <Icon name="warning" size={10} color="#f28b82" />
                <span>{turn.security_alerts_count || (turn.events ? turn.events.filter(e => e.injection_finding || (e.risk_level && e.risk_level !== 'safe')).length : 1)}</span>
              </span>
            {/if}

            {#if toArray(turn.files_modified_list).length > 0}
              <span class="meta-chip chip-files">
                <Icon name="edit" size={10} color="#81c995" />
                <span>{toArray(turn.files_modified_list).length}</span>
              </span>
            {/if}

            {#if turn.command_count > 0}
              <span class="meta-chip chip-cmds">
                <span>{turn.command_count} cmds</span>
              </span>
            {/if}
          </div>
        </div>
      {/each}
    {/if}
  </div>
</aside>
