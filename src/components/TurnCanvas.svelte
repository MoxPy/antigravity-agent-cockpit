<script lang="ts">
  import { summary, exportReport, isExporting } from '../stores/sessionStore';
  import { selectedTurnId, selectedStep, showTurnsNav, showInspector, collapseOverview, selectStep, showToast, maskSecrets } from '../stores/uiStore';
  import { formatLocalTime, formatFullCommand, formatDuration, copyToClipboard } from '../lib/formatters';
  import { toArray, redactText } from '../lib/security';
  import type { TurnItem, EventItem } from '../types';
  import Icon from './Icon.svelte';

  let stepperFilter: 'all' | 'terminal' | 'mutation' | 'inspect' | 'security' = 'all';
  let stepSearch = '';
  let stepViewDensity: 'compact' | 'detailed' = 'compact';
  let showFullThought = false;
  let expandedSteps = new Set<number>();

  function toggleStepExpand(step: number) {
    if (expandedSteps.has(step)) {
      expandedSteps.delete(step);
    } else {
      expandedSteps.add(step);
    }
    expandedSteps = expandedSteps;
  }

  function formatCompactSnippet(ev: EventItem): string {
    if (ev.command) return `$ ${ev.command.trim().replace(/\n+/g, " ")}`;
    if (ev.category === 'terminal' && ev.details) return `$ ${ev.details.trim().split("\n")[0]}`;
    if (ev.category === 'mutation' && ev.target) return `Edit: ${ev.target}`;
    if (ev.category === 'inspect' && ev.target) return `Inspect: ${ev.target}`;
    if (ev.category === 'user') return `User: ${(ev.details || ev.summary || '').trim().split("\n")[0]}`;
    if (ev.thinking) return `Thinking: ${ev.thinking.trim().slice(0, 100)}`;
    return ev.summary || ev.title || 'Step completed';
  }

  $: selectedTurn = ($summary.turns || []).find((t: TurnItem) => t.id === $selectedTurnId) || $summary.active_turn || null;
  $: turnEvents = toArray<EventItem>(selectedTurn?.events);
  $: turnFiles = toArray<string>(selectedTurn?.files_modified_list);

  $: turnSecurityAlertsCount = turnEvents.filter((e) => e.risk_level && e.risk_level !== 'safe').length;

  $: cleanTurnPrompt = (
    (selectedTurn?.prompt && selectedTurn.prompt.trim() !== '')
      ? selectedTurn.prompt
      : (selectedTurn?.raw_prompt && selectedTurn.raw_prompt.trim() !== '')
        ? selectedTurn.raw_prompt
        : 'Waiting for execution...'
  );

  $: filteredTurnEvents = turnEvents.filter((ev: EventItem) => {
    if (stepperFilter === 'terminal' && ev.category !== 'terminal') return false;
    if (stepperFilter === 'mutation' && ev.category !== 'mutation') return false;
    if (stepperFilter === 'inspect' && ev.category !== 'inspect') return false;
    if (stepperFilter === 'security' && (!ev.risk_level || ev.risk_level === 'safe')) return false;

    if (stepSearch.trim()) {
      const q = stepSearch.toLowerCase();
      const matchTitle = ev.title && ev.title.toLowerCase().includes(q);
      const matchSummary = ev.summary && ev.summary.toLowerCase().includes(q);
      const matchCmd = ev.command && ev.command.toLowerCase().includes(q);
      const matchTarget = ev.target && ev.target.toLowerCase().includes(q);
      const matchDetails = ev.details && ev.details.toLowerCase().includes(q);
      const matchStep = ev.step.toString().includes(q);
      return matchTitle || matchSummary || matchCmd || matchTarget || matchDetails || matchStep;
    }
    return true;
  });

  $: alertEvents = turnEvents.filter((e) => e.injection_finding || (e.risk_level && e.risk_level !== 'safe'));
  $: currentAlertIndex = alertEvents.findIndex((e) => e.step === $selectedStep?.step);

  function scrollToStep(stepNum: number) {
    setTimeout(() => {
      const el = document.getElementById(`step-card-${stepNum}`);
      if (el) {
        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    }, 60);
  }

  function handleSelectStepWithScroll(ev: EventItem) {
    selectStep(ev);
    scrollToStep(ev.step);
  }

  function toggleSecurityFilter() {
    if (stepperFilter === 'security') {
      stepperFilter = 'all';
    } else {
      stepperFilter = 'security';
      stepSearch = '';
      if (alertEvents.length > 0) {
        handleSelectStepWithScroll(alertEvents[0]);
      }
    }
  }

  function navigateAlert(direction: 'next' | 'prev') {
    if (alertEvents.length === 0) return;
    if (stepperFilter !== 'all' && stepperFilter !== 'security') {
      stepperFilter = 'security';
    }
    let nextIdx = 0;
    if (currentAlertIndex === -1) {
      nextIdx = direction === 'next' ? 0 : alertEvents.length - 1;
    } else {
      if (direction === 'next') {
        nextIdx = (currentAlertIndex + 1) % alertEvents.length;
      } else {
        nextIdx = (currentAlertIndex - 1 + alertEvents.length) % alertEvents.length;
      }
    }
    const target = alertEvents[nextIdx];
    if (target) {
      handleSelectStepWithScroll(target);
    }
  }

  async function handleCopyCmd(cmd: string) {
    const ok = await copyToClipboard(cmd);
    if (ok) showToast('Command copied');
  }
</script>

<section class="turn-canvas-pane" aria-label="Turn Execution Situation">
  {#if !selectedTurn}
    <div class="empty-state-large">
      <Icon name="layers" size={36} color="#5f6368" />
      <span class="empty-title">No Turn Selected</span>
      <p class="empty-sub">Select a turn from the left navigator to inspect its execution steps.</p>
    </div>
  {:else}
    <!-- Canvas Top Edge Toolbar for collapsed panels -->
    {#if !$showTurnsNav || !$showInspector}
      <div class="canvas-edge-bar">
        {#if !$showTurnsNav}
          <button class="btn-edge-toggle" on:click={() => $showTurnsNav = true}>
            <Icon name="sidebar" size={13} />
            <span>Show Turns</span>
          </button>
        {/if}
        <div class="canvas-edge-spacer"></div>
        {#if !$showInspector}
          <button class="btn-edge-toggle" on:click={() => $showInspector = true}>
            <span>Show Inspector</span>
            <Icon name="tune" size={13} />
          </button>
        {/if}
      </div>
    {/if}

    <!-- Pinned Turn Overview Section -->
    <div class="turn-overview-section" class:is-collapsed={$collapseOverview}>
      {#if $collapseOverview}
        <div class="overview-collapsed-bar">
          <div class="collapsed-left">
            <span class="turn-headline">Turn #{selectedTurn.id}</span>
            <span class="turn-badge" class:badge-active={selectedTurn.status === 'in_progress'} class:badge-done={selectedTurn.status === 'completed'}>
              {selectedTurn.status === 'in_progress' ? 'Running' : 'Done'}
            </span>
            <span class="block-time" title="Started at">{formatLocalTime(selectedTurn.timestamp)}</span>
            {#if selectedTurn.status === 'completed'}
              <span class="time-sep">→</span>
              <span class="block-time" title="Finished at">{formatLocalTime(selectedTurn.ended_at || (turnEvents[turnEvents.length - 1] && turnEvents[turnEvents.length - 1].timestamp) || selectedTurn.timestamp)}</span>
              {#if selectedTurn.duration_str || formatDuration(selectedTurn.timestamp, selectedTurn.ended_at)}
                <span class="duration-badge font-mono" title="Turn duration">{selectedTurn.duration_str || formatDuration(selectedTurn.timestamp, selectedTurn.ended_at)}</span>
              {/if}
            {:else}
              <span class="duration-badge live-duration font-mono" title="Running duration">{formatDuration(selectedTurn.timestamp)}</span>
            {/if}
            <span class="collapsed-prompt">"{cleanTurnPrompt}"</span>
          </div>
          <div class="collapsed-right">
            <div class="turn-counters-strip">
              <span class="counter-item"><b>{selectedTurn.events_count}</b> ops</span>
              <span class="counter-item text-blue"><b>{selectedTurn.command_count}</b> cmds</span>
              <span class="counter-item text-green"><b>{selectedTurn.mutation_count}</b> edits</span>
              <span class="counter-item text-purple"><b>{selectedTurn.inspect_count}</b> inspects</span>
              {#if (selectedTurn.security_alerts_count || turnSecurityAlertsCount) > 0}
                <button
                  type="button"
                  class="counter-item chip-alert btn-chip-clickable"
                  title="Filter flagged security operations"
                  on:click={() => {
                    stepperFilter = 'security';
                    const alertEv = turnEvents.find(e => e.injection_finding || (e.risk_level && e.risk_level !== 'safe'));
                    if (alertEv) selectStep(alertEv);
                  }}
                >
                  <Icon name="warning" size={11} color="#f28b82" />
                  <b>{selectedTurn.security_alerts_count || turnSecurityAlertsCount}</b> alerts
                </button>
              {/if}
            </div>
            <button
              class="btn-export-turn"
              disabled={$isExporting}
              on:click={() => exportReport(selectedTurn.id)}
              title="Export Turn #{selectedTurn.id} audit report"
            >
              <Icon name="download" size={12} />
              <span>Export</span>
            </button>
            <button class="btn-collapse-toggle" on:click={() => $collapseOverview = false} title="Expand Overview">
              <Icon name="chevron-down" size={13} />
              <span>Expand</span>
            </button>
          </div>
        </div>
      {:else}
        <div class="overview-header-row">
          <div class="overview-left-meta">
            <div class="turn-title-row">
              <span class="turn-headline">Turn #{selectedTurn.id}</span>
              <span class="turn-badge" class:badge-active={selectedTurn.status === 'in_progress'} class:badge-done={selectedTurn.status === 'completed'}>
                {#if selectedTurn.status === 'in_progress'}
                  <span class="pulse-dot"></span>
                  Running
                {:else}
                  Completed
                {/if}
              </span>
              <div class="turn-timing-group">
                <span class="timing-chip" title="Started at">
                  <Icon name="clock" size={11} color="#9aa0a6" />
                  <span>Iniziato: <b>{formatLocalTime(selectedTurn.timestamp)}</b></span>
                </span>
                {#if selectedTurn.status === 'completed'}
                  <span class="time-arrow">→</span>
                  <span class="timing-chip ended-chip" title="Finished at">
                    <Icon name="check" size={11} color="#81c995" />
                    <span>Finito: <b>{formatLocalTime(selectedTurn.ended_at || (turnEvents[turnEvents.length - 1] && turnEvents[turnEvents.length - 1].timestamp) || selectedTurn.timestamp)}</b></span>
                  </span>
                  {#if selectedTurn.duration_str || formatDuration(selectedTurn.timestamp, selectedTurn.ended_at)}
                    <span class="duration-badge font-mono" title="Turn duration">
                      ⏱️ {selectedTurn.duration_str || formatDuration(selectedTurn.timestamp, selectedTurn.ended_at)}
                    </span>
                  {/if}
                {:else}
                  <span class="duration-badge live-duration font-mono" title="Running duration">
                    ⏱️ in corso ({formatDuration(selectedTurn.timestamp)})
                  </span>
                {/if}
              </div>
            </div>
            <div class="turn-counters-strip">
              <span class="counter-item"><b>{selectedTurn.events_count}</b> ops</span>
              <span class="counter-item text-blue"><b>{selectedTurn.command_count}</b> cmds</span>
              <span class="counter-item text-green"><b>{selectedTurn.mutation_count}</b> edits</span>
              <span class="counter-item text-purple"><b>{selectedTurn.inspect_count}</b> inspects</span>
              {#if (selectedTurn.security_alerts_count || turnSecurityAlertsCount) > 0}
                <button
                  type="button"
                  class="counter-item chip-alert btn-chip-clickable"
                  title="Filter flagged security operations"
                  on:click={() => {
                    stepperFilter = 'security';
                    const alertEv = turnEvents.find(e => e.injection_finding || (e.risk_level && e.risk_level !== 'safe'));
                    if (alertEv) selectStep(alertEv);
                  }}
                >
                  <Icon name="warning" size={11} color="#f28b82" />
                  <b>{selectedTurn.security_alerts_count || turnSecurityAlertsCount}</b> alerts
                </button>
              {/if}
            </div>
          </div>
          <div class="overview-right-actions">
            <button
              class="btn-export-turn"
              disabled={$isExporting}
              on:click={() => exportReport(selectedTurn.id)}
              title="Export markdown report for Turn #{selectedTurn.id}"
            >
              <Icon name="download" size={12} />
              <span>Export Turn #{selectedTurn.id}</span>
            </button>
            <button class="btn-collapse-toggle" on:click={() => $collapseOverview = true} title="Collapse Overview">
              <Icon name="chevron-up" size={13} />
              <span>Collapse</span>
            </button>
          </div>
        </div>

        <div class="user-instruction-card">
          <div class="instruction-label-row">
            <Icon name="sparkle" size={13} color="#8ab4f8" />
            <span class="instruction-label">USER REQUEST</span>
          </div>
          <div class="instruction-content">
            {cleanTurnPrompt}
          </div>
        </div>

        {#if (selectedTurn.security_alerts_count || turnSecurityAlertsCount) > 0}
          <div class="turn-security-banner">
            <div class="banner-left">
              <Icon name="shield-alert" size={15} color="#f28b82" />
              <div class="banner-text-group">
                <span class="banner-text">
                  <strong>{alertEvents.length || selectedTurn.security_alerts_count || turnSecurityAlertsCount} security finding{(alertEvents.length || selectedTurn.security_alerts_count || turnSecurityAlertsCount) > 1 ? 's' : ''}</strong> flagged in this turn
                  {#if turnEvents.some(e => e.injection_finding)}
                    &bull; <span class="inj-tag">Prompt Injection Vector Detected</span>
                  {/if}
                </span>
                {#if alertEvents.length > 1}
                  <span class="banner-subtext">Isolate findings with the filter or navigate step-by-step</span>
                {/if}
              </div>
            </div>

            <div class="banner-right-controls">
              <!-- Filter All Findings Button -->
              <button
                type="button"
                class="btn-banner-action"
                class:btn-banner-active={stepperFilter === 'security'}
                on:click={toggleSecurityFilter}
                title={stepperFilter === 'security' ? 'Show all steps' : 'Filter timeline to show only flagged findings'}
              >
                <Icon name={stepperFilter === 'security' ? 'layers' : 'search'} size={11} />
                <span>{stepperFilter === 'security' ? `Show all ${turnEvents.length} steps` : `Filter ${alertEvents.length} findings`}</span>
              </button>

              <!-- Step-Through Pager (when multiple findings exist) -->
              {#if alertEvents.length > 1}
                <div class="banner-alert-pager">
                  <span class="pager-label">
                    {#if currentAlertIndex !== -1}
                      Finding {currentAlertIndex + 1} of {alertEvents.length}
                    {:else}
                      {alertEvents.length} findings
                    {/if}
                  </span>
                  <div class="pager-buttons">
                    <button
                      type="button"
                      class="btn-pager"
                      on:click={() => navigateAlert('prev')}
                      title="Previous security finding"
                      aria-label="Previous security finding"
                    >
                      <Icon name="chevron-left" size={12} />
                    </button>
                    <button
                      type="button"
                      class="btn-pager"
                      on:click={() => navigateAlert('next')}
                      title="Next security finding"
                      aria-label="Next security finding"
                    >
                      <Icon name="chevron-right" size={12} />
                    </button>
                  </div>
                </div>
              {/if}
            </div>
          </div>
        {/if}

        {#if turnFiles.length > 0}
          <div class="turn-files-bar">
            <span class="turn-files-title">Files modified ({turnFiles.length}):</span>
            <div class="turn-files-tags">
              {#each turnFiles as file}
                <span class="file-tag" title={file}>
                  <Icon name="edit" size={10} color="#81c995" />
                  <span>{file}</span>
                </span>
              {/each}
            </div>
          </div>
        {/if}

        {#if selectedTurn.latest_thought}
          <div class="agent-thought-card">
            <div
              class="thought-header"
              role="button"
              tabindex="0"
              on:click={() => showFullThought = !showFullThought}
              on:keydown={(e) => { if (e.key === 'Enter' || e.key === ' ') showFullThought = !showFullThought; }}
            >
              <div class="thought-title-group">
                <Icon name="gemini" size={14} color="#c58af9" />
                <span class="thought-label">Thinking</span>
                {#if selectedTurn.thought_count > 1}
                  <span class="thought-badge">{selectedTurn.thought_count} passes</span>
                {/if}
              </div>
              <button
                type="button"
                class="btn-thought-toggle"
                on:click|stopPropagation={() => showFullThought = !showFullThought}
                title={showFullThought ? "Hide Thinking details" : "View Thinking details"}
              >
                <span>{showFullThought ? 'Hide Thinking' : 'View Thinking'}</span>
                <Icon name={showFullThought ? "chevron-up" : "chevron-down"} size={12} />
              </button>
            </div>
            {#if showFullThought}
              <div class="thought-body">
                {selectedTurn.latest_thought}
              </div>
            {/if}
          </div>
        {/if}
      {/if}
    </div>

    <!-- Execution Timeline Stepper -->
    <div class="execution-flow-wrapper">
      <div class="stepper-toolbar">
        <div class="stepper-filters-row">
          <span class="flow-title">Execution Steps</span>
          <div class="flow-filter-pills">
            <button class="flow-pill" class:active={stepperFilter === 'all'} on:click={() => stepperFilter = 'all'}>
              All ({turnEvents.length})
            </button>
            <button class="flow-pill" class:active={stepperFilter === 'terminal'} on:click={() => stepperFilter = 'terminal'}>
              <Icon name="terminal" size={11} />
              <span>Commands ({selectedTurn.command_count})</span>
            </button>
            <button class="flow-pill" class:active={stepperFilter === 'mutation'} on:click={() => stepperFilter = 'mutation'}>
              <Icon name="edit" size={11} />
              <span>Edits ({selectedTurn.mutation_count})</span>
            </button>
            <button class="flow-pill" class:active={stepperFilter === 'inspect'} on:click={() => stepperFilter = 'inspect'}>
              <Icon name="search" size={11} />
              <span>Inspects ({selectedTurn.inspect_count})</span>
            </button>
            {#if (selectedTurn.security_alerts_count || turnSecurityAlertsCount) > 0}
              <button class="flow-pill pill-alert" class:active={stepperFilter === 'security'} on:click={() => stepperFilter = 'security'}>
                <Icon name="warning" size={11} color="#f28b82" />
                <span>Alerts ({selectedTurn.security_alerts_count || turnSecurityAlertsCount})</span>
              </button>
            {/if}
          </div>
        </div>

        <div class="stepper-controls-row">
          <div class="google-search-wrap step-search-wrap">
            <Icon name="search" size={13} className="search-icon" color="#9aa0a6" />
            <input
              type="text"
              class="input-google-search search-step-input"
              placeholder="Search steps..."
              bind:value={stepSearch}
            />
            {#if stepSearch}
              <button class="search-clear-btn" on:click={() => stepSearch = ''}>
                <Icon name="close" size={12} />
              </button>
            {/if}
          </div>
          <div class="density-toggle">
            <button class="density-btn" class:active={stepViewDensity === 'compact'} on:click={() => stepViewDensity = 'compact'}>
              Compact
            </button>
            <button class="density-btn" class:active={stepViewDensity === 'detailed'} on:click={() => stepViewDensity = 'detailed'}>
              Detailed
            </button>
          </div>
        </div>
      </div>

      <div class="flow-cards-scroll">
        {#if filteredTurnEvents.length === 0}
          <div class="empty-state-flow">
            <Icon name="search" size={28} color="#5f6368" />
            <span>No steps match the active filter.</span>
          </div>
        {:else}
          {#each filteredTurnEvents as ev, i (ev.step)}
            <!-- svelte-ignore a11y-click-events-have-key-events -->
            <!-- svelte-ignore a11y-no-static-element-interactions -->
            <div
              id={`step-card-${ev.step}`}
              class="step-flow-card"
              class:step-selected={$selectedStep?.step === ev.step}
              class:density-compact={stepViewDensity === 'compact'}
              class:density-detailed={stepViewDensity === 'detailed'}
              class:is-expanded={stepViewDensity === 'detailed' || expandedSteps.has(ev.step)}
              on:click={() => handleSelectStepWithScroll(ev)}
            >
              <div class="step-spine">
                <div class="step-dot" class:dot-active={i === filteredTurnEvents.length - 1 && selectedTurn.status === 'in_progress'}>
                  {#if ev.category === 'terminal'}
                    <Icon name="terminal" size={11} color="#8ab4f8" />
                  {:else if ev.category === 'mutation'}
                    <Icon name="edit" size={11} color="#81c995" />
                  {:else if ev.category === 'inspect'}
                    <Icon name="search" size={11} color="#c58af9" />
                  {:else if ev.category === 'user'}
                    <Icon name="sparkle" size={11} color="#8ab4f8" />
                  {:else if ev.risk_level && ev.risk_level !== 'safe'}
                    <Icon name="warning" size={11} color="#f28b82" />
                  {:else}
                    <Icon name="sparkle" size={11} color="#fdd663" />
                  {/if}
                </div>
                {#if i < filteredTurnEvents.length - 1}
                  <div class="step-line"></div>
                {/if}
              </div>

              <div class="step-card-content">
                <div class="step-top-row">
                  <div class="step-top-left">
                    {#if stepViewDensity === 'compact'}
                      <button
                        type="button"
                        class="btn-expand-chevron"
                        on:click|stopPropagation={() => toggleStepExpand(ev.step)}
                        title={expandedSteps.has(ev.step) ? 'Collapse details' : 'Expand details'}
                      >
                        <Icon name={expandedSteps.has(ev.step) ? 'chevron-down' : 'chevron-right'} size={11} />
                      </button>
                    {/if}
                    <span class="step-idx">#{ev.step}</span>
                    <span class="cat-tag tag-{ev.category}">{ev.tool || ev.category}</span>
                    {#if ev.risk_level && ev.risk_level !== 'safe'}
                      <span class="risk-badge risk-{ev.risk_level}">
                        <Icon name="warning" size={10} />
                        {ev.risk_level.toUpperCase()}
                      </span>
                    {/if}
                    {#if ev.injection_finding}
                      <span class="risk-badge risk-critical" title={ev.injection_finding.snippet}>
                        <Icon name="shield-alert" size={10} />
                        INJECTION
                      </span>
                    {/if}
                    <span class="step-card-title">{ev.title}</span>
                  </div>
                  <div class="step-top-right">
                    <span class="step-time">{formatLocalTime(ev.timestamp)}</span>
                    <button class="btn-inspect-step" on:click|stopPropagation={() => handleSelectStepWithScroll(ev)}>
                      <span>Inspect</span>
                      <Icon name="chevron-right" size={11} />
                    </button>
                  </div>
                </div>

                {#if stepViewDensity === 'detailed' || expandedSteps.has(ev.step)}
                  <div class="step-summary-text">
                    {ev.summary}
                  </div>

                  {#if ev.command || (ev.category === 'terminal' && ev.details)}
                    <div class="cmd-box-wrap">
                      <pre class="step-cmd-preview"><code>{formatFullCommand(redactText(ev.command || ev.details, $maskSecrets))}</code></pre>
                      <button
                        class="btn-cmd-copy"
                        on:click|stopPropagation={() => handleCopyCmd(ev.command || ev.details)}
                        title="Copy command to clipboard"
                      >
                        <Icon name="copy" size={12} />
                      </button>
                    </div>
                  {:else if ev.details && ev.details !== ev.summary}
                    <div class="step-details-preview">{ev.details}</div>
                  {/if}
                {:else}
                  <div class="step-compact-line" on:click|stopPropagation={() => toggleStepExpand(ev.step)}>
                    <code class="compact-cmd-snippet font-mono">{formatCompactSnippet(ev)}</code>
                  </div>
                {/if}
              </div>
            </div>
          {/each}
        {/if}
      </div>
    </div>
  {/if}
</section>
