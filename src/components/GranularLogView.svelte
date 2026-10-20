<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { summary } from '../stores/sessionStore';
  import { jumpToStep, showToast, maskSecrets } from '../stores/uiStore';
  import { formatLocalTime, formatFullCommand, copyToClipboard } from '../lib/formatters';
  import { toArray, redactText } from '../lib/security';
  import type { EventItem, TurnItem } from '../types';
  import Icon from './Icon.svelte';

  let logFilter: string = 'all';
  let selectedTurnFilter: number | 'all' = 'all';
  let logSearch: string = '';
  let logDensity: 'compact' | 'detailed' = 'compact';
  let autoScroll = false;
  let logContainer: HTMLElement | null = null;
  let displayLimit = 150;
  let expandedRowSteps = new Set<number>();

  // Available turns for the dropdown
  $: availableTurns = toArray<TurnItem>($summary.turns);

  // Unify events across all turns and recent_events, sorted chronologically
  $: allEvents = (() => {
    const map = new Map<number, EventItem>();
    for (const t of ($summary.turns || [])) {
      for (const ev of toArray<EventItem>(t.events)) {
        if (!ev.turn_id) ev.turn_id = t.id;
        map.set(ev.step, ev);
      }
    }
    for (const ev of toArray<EventItem>($summary.recent_events)) {
      if (!map.has(ev.step)) map.set(ev.step, ev);
    }
    const list = Array.from(map.values());
    list.sort((a, b) => a.step - b.step);
    return list;
  })();

  // Filter pool based on selected turn
  $: turnEventsPool = selectedTurnFilter === 'all'
    ? allEvents
    : allEvents.filter(e => e.turn_id === selectedTurnFilter);

  $: commandCount = turnEventsPool.filter(e => e.category === 'terminal').length;
  $: mutationCount = turnEventsPool.filter(e => e.category === 'mutation').length;
  $: inspectCount = turnEventsPool.filter(e => e.category === 'inspect').length;
  $: thoughtCount = turnEventsPool.filter(e => e.thinking || e.category === 'thought').length;
  $: userPromptCount = turnEventsPool.filter(e => e.category === 'user').length;
  $: flaggedCount = turnEventsPool.filter(e => e.risk_level && e.risk_level !== 'safe').length;

  $: filteredEvents = turnEventsPool.filter((ev: EventItem) => {
    if (logFilter !== 'all') {
      if (logFilter === 'security') {
        if (!ev.risk_level || ev.risk_level === 'safe') return false;
      } else if (logFilter === 'thought') {
        if (ev.category !== 'thought' && !ev.thinking) return false;
      } else if (logFilter === 'user') {
        if (ev.category !== 'user') return false;
      } else if (ev.category !== logFilter) {
        return false;
      }
    }

    if (logSearch.trim()) {
      const q = logSearch.toLowerCase();
      const matchTitle = ev.title && ev.title.toLowerCase().includes(q);
      const matchSummary = ev.summary && ev.summary.toLowerCase().includes(q);
      const matchCmd = ev.command && ev.command.toLowerCase().includes(q);
      const matchTarget = ev.target && ev.target.toLowerCase().includes(q);
      const matchDetails = ev.details && ev.details.toLowerCase().includes(q);
      const matchThought = ev.thinking && ev.thinking.toLowerCase().includes(q);
      const matchStep = ev.step.toString().includes(q);
      return matchTitle || matchSummary || matchCmd || matchTarget || matchDetails || matchThought || matchStep;
    }

    return true;
  });

  $: visibleEvents = filteredEvents.slice(0, displayLimit);

  function setLogFilter(filter: string) {
    logFilter = filter;
    displayLimit = 150;
    if (logContainer) logContainer.scrollTop = 0;
  }

  function setTurnFilter(turn: number | 'all') {
    selectedTurnFilter = turn;
    displayLimit = 150;
    if (logContainer) logContainer.scrollTop = 0;
  }

  function scrollToTop() {
    if (logContainer) logContainer.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function scrollToBottom() {
    if (logContainer) logContainer.scrollTo({ top: logContainer.scrollHeight, behavior: 'smooth' });
  }

  function loadMore() {
    displayLimit += 150;
  }

  function showAll() {
    displayLimit = filteredEvents.length;
  }

  function toggleRowExpand(step: number) {
    if (expandedRowSteps.has(step)) {
      expandedRowSteps.delete(step);
    } else {
      expandedRowSteps.add(step);
    }
    expandedRowSteps = expandedRowSteps;
  }

  function formatCompactSnippet(ev: EventItem): string {
    if (ev.command) return `$ ${ev.command}`;
    if (ev.category === 'terminal' && ev.details) return `$ ${ev.details}`;
    if (ev.category === 'mutation' && ev.target) return `Edit: ${ev.target}`;
    if (ev.category === 'inspect' && ev.target) return `Inspect: ${ev.target}`;
    if (ev.category === 'user') return `User: ${ev.details || ev.summary || ev.title}`;
    if (ev.thinking) return `Thinking: ${ev.thinking.slice(0, 140)}`;
    return ev.summary || ev.title || 'Operation completed';
  }

  async function handleCopy(text: string) {
    const ok = await copyToClipboard(text);
    if (ok) showToast('Command copied');
  }

  function handleJump(step: number, turnId?: number) {
    jumpToStep(step, turnId, $summary.turns);
  }
</script>

<main class="granular-log-layout" aria-label="Granular Log Explorer">
  <!-- Top Navigation & Filter Bar -->
  <div class="log-toolbar">
    <!-- Turn Filter Dropdown & Category Pills -->
    <div class="log-nav-left">
      <div class="turn-dropdown-wrap">
        <label for="turn-select" class="turn-select-label font-mono">TURN:</label>
        <select
          id="turn-select"
          class="turn-select-dropdown"
          bind:value={selectedTurnFilter}
          on:change={() => setTurnFilter(selectedTurnFilter)}
        >
          <option value="all">All Turns ({availableTurns.length})</option>
          {#each availableTurns.slice().reverse() as t}
            <option value={t.id}>Turn #{t.id} ({t.events_count || 0} ops)</option>
          {/each}
        </select>
      </div>

      <div class="filter-pills-scroll">
        <button class="pill-btn" class:active={logFilter === 'all'} on:click={() => setLogFilter('all')}>
          All ({turnEventsPool.length})
        </button>
        <button class="pill-btn" class:active={logFilter === 'user'} on:click={() => setLogFilter('user')}>
          <Icon name="sparkle" size={11} color="#8ab4f8" />
          <span>Prompts ({userPromptCount})</span>
        </button>
        <button class="pill-btn" class:active={logFilter === 'terminal'} on:click={() => setLogFilter('terminal')}>
          <Icon name="terminal" size={11} />
          <span>Commands ({commandCount})</span>
        </button>
        <button class="pill-btn" class:active={logFilter === 'mutation'} on:click={() => setLogFilter('mutation')}>
          <Icon name="edit" size={11} />
          <span>Edits ({mutationCount})</span>
        </button>
        <button class="pill-btn" class:active={logFilter === 'inspect'} on:click={() => setLogFilter('inspect')}>
          <Icon name="search" size={11} />
          <span>Inspects ({inspectCount})</span>
        </button>
        <button class="pill-btn" class:active={logFilter === 'thought'} on:click={() => setLogFilter('thought')}>
          <Icon name="gemini" size={11} />
          <span>Thinking ({thoughtCount})</span>
        </button>
        {#if flaggedCount > 0}
          <button class="pill-btn pill-alert" class:active={logFilter === 'security'} on:click={() => setLogFilter('security')}>
            <Icon name="warning" size={11} color="#f28b82" />
            <span>Alerts ({flaggedCount})</span>
          </button>
        {/if}
      </div>
    </div>

    <!-- Actions & Controls -->
    <div class="log-actions-bar">
      <div class="google-search-wrap log-search-wrap">
        <Icon name="search" size={13} className="search-icon" color="#9aa0a6" />
        <input
          type="text"
          class="input-google-search search-log-input"
          placeholder="Filter logs by command, path..."
          bind:value={logSearch}
        />
        {#if logSearch}
          <button class="search-clear-btn" on:click={() => logSearch = ''}>
            <Icon name="close" size={12} />
          </button>
        {/if}
      </div>

      <!-- Real Density Toggle -->
      <div class="density-toggle" title="Switch between dense single-line and full card view">
        <button
          type="button"
          class="density-btn"
          class:active={logDensity === 'compact'}
          on:click={() => logDensity = 'compact'}
        >
          Compact
        </button>
        <button
          type="button"
          class="density-btn"
          class:active={logDensity === 'detailed'}
          on:click={() => logDensity = 'detailed'}
        >
          Detailed
        </button>
      </div>

      <!-- Quick Jump Buttons -->
      <div class="log-jump-controls">
        <button
          type="button"
          class="btn-log-jump"
          on:click={scrollToTop}
          title="Scroll to beginning of logs"
        >
          <Icon name="chevron-up" size={12} />
          <span>Top</span>
        </button>
        <button
          type="button"
          class="btn-log-jump"
          on:click={scrollToBottom}
          title="Scroll to latest logs"
        >
          <Icon name="chevron-down" size={12} />
          <span>Bottom</span>
        </button>
      </div>
    </div>
  </div>

  <!-- Scrollable Log Stream -->
  <div class="log-stream-scroll" bind:this={logContainer}>
    {#if filteredEvents.length === 0}
      <div class="empty-state-large">
        <Icon name="search" size={32} color="#5f6368" />
        <span class="empty-title">No Log Entries Found</span>
        <p class="empty-sub">
          No operations match the selected filter or search keyword
          {#if selectedTurnFilter !== 'all'} in Turn #{selectedTurnFilter}{/if}.
        </p>
      </div>
    {:else}
      {#each visibleEvents as ev (ev.step)}
        <div
          class="log-row"
          class:log-row-compact={logDensity === 'compact'}
          class:density-detailed={logDensity === 'detailed'}
          class:log-row-user={ev.category === 'user'}
          class:is-expanded={logDensity === 'detailed' || expandedRowSteps.has(ev.step)}
        >
          {#if logDensity === 'compact'}
            <!-- COMPACT VIEW: Ultra-dense single-line row with quick peek -->
            <!-- svelte-ignore a11y-click-events-have-key-events -->
            <!-- svelte-ignore a11y-no-static-element-interactions -->
            <div class="log-compact-row" on:click={() => toggleRowExpand(ev.step)}>
              <button
                type="button"
                class="btn-expand-chevron"
                title={expandedRowSteps.has(ev.step) ? 'Collapse details' : 'Expand details'}
                on:click|stopPropagation={() => toggleRowExpand(ev.step)}
              >
                <Icon name={expandedRowSteps.has(ev.step) ? 'chevron-up' : 'chevron-down'} size={12} />
              </button>

              <span class="cat-tag tag-{ev.category}">{ev.tool || ev.category}</span>

              <button
                type="button"
                class="step-id-link font-mono"
                on:click|stopPropagation={() => handleJump(ev.step, ev.turn_id)}
                title="Inspect step in Turn Timeline"
              >
                #{ev.step}
              </button>

              {#if ev.turn_id}
                <span class="turn-chip-tiny font-mono">T#{ev.turn_id}</span>
              {/if}

              {#if ev.risk_level && ev.risk_level !== 'safe'}
                <span class="risk-badge risk-{ev.risk_level}" title={(ev.risk_reasons || []).join('; ')}>
                  <Icon name="warning" size={10} />
                  {ev.risk_level.toUpperCase()}
                </span>
              {/if}

              <span class="log-compact-text font-mono" title={ev.command || ev.details || ev.summary || ev.title}>
                {formatCompactSnippet(ev)}
              </span>

              <div class="log-compact-right">
                <span class="log-time font-mono">{formatLocalTime(ev.timestamp)}</span>
                <button
                  type="button"
                  class="btn btn-tiny btn-ghost btn-inspect-compact"
                  on:click|stopPropagation={() => handleJump(ev.step, ev.turn_id)}
                  title="Open in Step Inspector"
                >
                  <span>Inspect</span>
                  <Icon name="chevron-right" size={10} />
                </button>
              </div>
            </div>

            {#if expandedRowSteps.has(ev.step)}
              <!-- Expanded output accordion in compact mode -->
              <div class="log-expanded-details">
                <div class="log-summary">
                  {ev.summary}
                </div>

                {#if ev.command || (ev.category === 'terminal' && ev.details)}
                  <div class="log-code-wrapper">
                    <div class="code-box-header">
                      <span class="code-box-title font-mono">$ {ev.tool || 'terminal'}</span>
                      <button class="copy-tiny-btn" on:click={() => handleCopy(ev.command || ev.details)}>
                        <Icon name="copy" size={11} />
                        <span>Copy</span>
                      </button>
                    </div>
                    <pre class="code-box log-details font-mono"><code>{formatFullCommand(redactText(ev.command || ev.details, $maskSecrets))}</code></pre>
                  </div>
                {:else if ev.details && ev.details !== ev.summary}
                  <pre class="code-box log-details font-mono"><code>{redactText(formatFullCommand(ev.details), $maskSecrets)}</code></pre>
                {/if}

                {#if ev.thinking}
                  <div class="thought-inspector-box mt-2">
                    <div class="thought-box-title">
                      <Icon name="gemini" size={12} />
                      <span>Thinking</span>
                    </div>
                    <div class="thought-text">{ev.thinking}</div>
                  </div>
                {/if}
              </div>
            {/if}

          {:else}
            <!-- DETAILED VIEW: Full inspection card with code blocks & thinking -->
            <div class="log-row-header">
              <div class="log-header-left">
                <span class="cat-tag tag-{ev.category}">{ev.tool || ev.category}</span>
                <button
                  type="button"
                  class="step-id-link font-mono"
                  on:click={() => handleJump(ev.step, ev.turn_id)}
                  title="Inspect step in Turn Timeline"
                >
                  #{ev.step}
                </button>
                {#if ev.turn_id}
                  <span class="turn-chip-tiny font-mono">Turn #{ev.turn_id}</span>
                {/if}
                {#if ev.risk_level && ev.risk_level !== 'safe'}
                  <span class="risk-badge risk-{ev.risk_level}" title={(ev.risk_reasons || []).join('; ')}>
                    <Icon name="warning" size={10} />
                    {ev.risk_level.toUpperCase()}
                  </span>
                {/if}
                <span class="log-title">{ev.title}</span>
              </div>
              <div class="log-header-right">
                <span class="log-time font-mono">{formatLocalTime(ev.timestamp)}</span>
                <button type="button" class="btn btn-tiny btn-ghost" on:click={() => handleJump(ev.step, ev.turn_id)}>
                  <span>Inspect</span>
                  <Icon name="chevron-right" size={11} />
                </button>
              </div>
            </div>

            {#if ev.category === 'user'}
              <div class="log-user-prompt-body font-mono">
                {ev.details || ev.summary}
              </div>
            {:else}
              <div class="log-summary">
                {ev.summary}
              </div>

              {#if ev.command || (ev.category === 'terminal' && ev.details)}
                <div class="log-code-wrapper">
                  <div class="code-box-header">
                    <span class="code-box-title font-mono">$ {ev.tool || 'terminal'}</span>
                    <button class="copy-tiny-btn" on:click={() => handleCopy(ev.command || ev.details)}>
                      <Icon name="copy" size={11} />
                      <span>Copy</span>
                    </button>
                  </div>
                  <pre class="code-box log-details font-mono"><code>{formatFullCommand(redactText(ev.command || ev.details, $maskSecrets))}</code></pre>
                </div>
              {:else if ev.details && ev.details !== ev.summary}
                <pre class="code-box log-details font-mono"><code>{redactText(formatFullCommand(ev.details), $maskSecrets)}</code></pre>
              {/if}

              {#if ev.thinking}
                <div class="thought-inspector-box mt-2">
                  <div class="thought-box-title">
                    <Icon name="gemini" size={12} />
                    <span>Thinking</span>
                  </div>
                  <div class="thought-text">{ev.thinking}</div>
                </div>
              {/if}
            {/if}
          {/if}
        </div>
      {/each}
    {/if}
  </div>

  <!-- Bottom Pagination / Limit Bar (When events exceed displayLimit) -->
  {#if filteredEvents.length > 0}
    <div class="log-pagination-bar">
      <span class="pagination-info font-mono">
        Showing <strong>{Math.min(displayLimit, filteredEvents.length)}</strong> of <strong>{filteredEvents.length}</strong> events
        {#if selectedTurnFilter !== 'all'} in Turn #{selectedTurnFilter}{/if}
      </span>
      <div class="log-pagination-actions">
        {#if displayLimit < filteredEvents.length}
          <button type="button" class="btn btn-tiny btn-ghost" on:click={loadMore}>
            <span>Load +150 More</span>
          </button>
          <button type="button" class="btn btn-tiny btn-ghost" on:click={showAll}>
            <span>Show All ({filteredEvents.length})</span>
          </button>
        {/if}
        <button type="button" class="btn btn-tiny btn-ghost" on:click={scrollToTop}>
          <Icon name="chevron-up" size={11} />
          <span>Top</span>
        </button>
      </div>
    </div>
  {/if}
</main>
