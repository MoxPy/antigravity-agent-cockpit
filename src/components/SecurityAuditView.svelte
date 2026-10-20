<script lang="ts">
  import { summary, initSession } from '../stores/sessionStore';
  import { maskSecrets, jumpToStep, showToast } from '../stores/uiStore';
  import { toArray, redactSecretPreview, redactText } from '../lib/security';
  import { formatLocalTime, copyToClipboard } from '../lib/formatters';
  import Icon from './Icon.svelte';

  let auditFilter: 'all' | 'secrets' | 'escapes' | 'egress' | 'packages' | 'injections' = 'all';
  let auditSearch = '';

  $: sec = $summary?.security_audit;
  $: auditSecrets = toArray(sec?.secrets);
  $: auditEscapes = toArray(sec?.boundary_escapes);
  $: auditEgress = toArray(sec?.network_egress);
  $: auditPackages = toArray(sec?.packages);
  $: auditInjections = toArray(sec?.injections);
  $: totalFindings = auditSecrets.length + auditEscapes.length + auditEgress.length + auditPackages.length + auditInjections.length;

  $: q = (auditSearch || '').trim().toLowerCase();
  $: filteredSecrets = q
    ? auditSecrets.filter(s => (s.type && s.type.toLowerCase().includes(q)) || (s.preview && s.preview.toLowerCase().includes(q)) || (s.step != null && String(s.step).includes(q)) || (s.turn_id != null && String(s.turn_id).includes(q)))
    : auditSecrets;
  $: filteredEscapes = q
    ? auditEscapes.filter(e => (e.reason && e.reason.toLowerCase().includes(q)) || (e.target && e.target.toLowerCase().includes(q)) || (e.cwd && e.cwd.toLowerCase().includes(q)) || (e.step != null && String(e.step).includes(q)) || (e.turn_id != null && String(e.turn_id).includes(q)))
    : auditEscapes;
  $: filteredEgress = q
    ? auditEgress.filter(g => (g.type && g.type.toLowerCase().includes(q)) || (g.destination && g.destination.toLowerCase().includes(q)) || (g.step != null && String(g.step).includes(q)) || (g.turn_id != null && String(g.turn_id).includes(q)))
    : auditEgress;
  $: filteredPackages = q
    ? auditPackages.filter(p => (p.manager && p.manager.toLowerCase().includes(q)) || (p.package && p.package.toLowerCase().includes(q)) || (p.step != null && String(p.step).includes(q)) || (p.turn_id != null && String(p.turn_id).includes(q)))
    : auditPackages;
  $: filteredInjections = q
    ? auditInjections.filter(i => (i.type && i.type.toLowerCase().includes(q)) || (i.source && i.source.toLowerCase().includes(q)) || (i.snippet && i.snippet.toLowerCase().includes(q)) || (i.target && i.target.toLowerCase().includes(q)) || (i.step != null && String(i.step).includes(q)) || (i.turn_id != null && String(i.turn_id).includes(q)))
    : auditInjections;

  async function handleCopy(text: string) {
    const toCopy = $maskSecrets ? '••••••••••••••••••••' : text;
    const ok = await copyToClipboard(toCopy);
    if (ok) showToast($maskSecrets ? 'Copied (redacted)' : 'Copied');
  }

  function handleJump(step: number, turnId?: number) {
    jumpToStep(step, turnId, $summary.turns);
  }
</script>

<main class="audit-room-layout" aria-label="Security and Perimeter Audit">
  <!-- Top Dedicated Google Cloud Action Bar -->
  <div class="audit-sub-header">
    <div class="audit-header-left">
      <div class="audit-title-group">
        <Icon name="shield" size={16} color="#8ab4f8" />
        <h2 class="audit-view-title">Security & Perimeter Audit</h2>
      </div>

      <div class="audit-meta-group">
        {#if totalFindings > 0}
          <span class="status-pill status-pill-alert">
            <span class="status-dot-sm alert"></span>
            <span>{totalFindings} Policy {totalFindings === 1 ? 'Alert' : 'Alerts'}</span>
          </span>
        {:else}
          <span class="status-pill status-pill-clean">
            <span class="status-dot-sm clean"></span>
            <span>All Checks Passed</span>
          </span>
        {/if}

        {#if $summary.workspace_root}
          <span class="scope-chip" title="Monitored workspace boundary: {$summary.workspace_root}">
            <span class="scope-label">Boundary:</span>
            <span class="scope-val font-mono">{$summary.workspace_root.split('/').pop() || $summary.workspace_root}</span>
          </span>
        {/if}
      </div>
    </div>

    <div class="audit-actions-right">
      <label class="toggle-mask-label" title="Mask sensitive tokens and credentials in display">
        <span class="switch-ui">
          <input type="checkbox" bind:checked={$maskSecrets} />
          <span class="switch-slider"></span>
        </span>
        <span class="toggle-text">
          <Icon name={$maskSecrets ? "lock" : "unlock"} size={13} color={$maskSecrets ? "#8ab4f8" : "#9aa0a6"} />
          <span>Redact Secrets</span>
        </span>
      </label>

      <button class="btn btn-secondary btn-sm" on:click={() => initSession()} title="Re-scan and refresh status">
        <Icon name="refresh" size={13} />
        <span>Refresh</span>
      </button>

    </div>
  </div>

  <!-- Google Cloud 4 KPI Cards Strip (Consistent with overview-metrics-strip) -->
  <div class="audit-metrics-strip">
    <div
      role="button"
      tabindex="0"
      class="metric-card card-interactive"
      class:card-active={auditFilter === 'secrets'}
      class:card-alert={auditSecrets.length > 0}
      on:click={() => auditFilter = auditFilter === 'secrets' ? 'all' : 'secrets'}
      on:keydown={(e) => { if (e.key === 'Enter') auditFilter = auditFilter === 'secrets' ? 'all' : 'secrets'; }}
    >
      <div class="metric-label-row">
        <div class="label-with-icon">
          <Icon name="key" size={13} color={auditSecrets.length > 0 ? "#f28b82" : "#9aa0a6"} />
          <span class="metric-label">Exposed Credentials</span>
        </div>
        {#if auditFilter === 'secrets'}
          <span class="filter-active-tag">FILTERED</span>
        {/if}
      </div>
      <div class="metric-value" class:text-red={auditSecrets.length > 0} class:text-green={auditSecrets.length === 0}>
        {auditSecrets.length}
      </div>
      <div class="metric-subtext">
        {auditSecrets.length === 0 ? '0 credentials detected' : 'Tokens in transcript'}
      </div>
    </div>

    <div
      role="button"
      tabindex="0"
      class="metric-card card-interactive"
      class:card-active={auditFilter === 'escapes'}
      class:card-alert={auditEscapes.length > 0}
      on:click={() => auditFilter = auditFilter === 'escapes' ? 'all' : 'escapes'}
      on:keydown={(e) => { if (e.key === 'Enter') auditFilter = auditFilter === 'escapes' ? 'all' : 'escapes'; }}
    >
      <div class="metric-label-row">
        <div class="label-with-icon">
          <Icon name="escape" size={13} color={auditEscapes.length > 0 ? "#fdd663" : "#9aa0a6"} />
          <span class="metric-label">Boundary Escapes</span>
        </div>
        {#if auditFilter === 'escapes'}
          <span class="filter-active-tag">FILTERED</span>
        {/if}
      </div>
      <div class="metric-value" class:text-red={auditEscapes.length > 0} class:text-green={auditEscapes.length === 0}>
        {auditEscapes.length}
      </div>
      <div class="metric-subtext">
        {auditEscapes.length === 0 ? 'Within workspace root' : 'Paths outside boundary'}
      </div>
    </div>

    <div
      role="button"
      tabindex="0"
      class="metric-card card-interactive"
      class:card-active={auditFilter === 'egress'}
      class:card-alert={auditEgress.length > 0}
      on:click={() => auditFilter = auditFilter === 'egress' ? 'all' : 'egress'}
      on:keydown={(e) => { if (e.key === 'Enter') auditFilter = auditFilter === 'egress' ? 'all' : 'egress'; }}
    >
      <div class="metric-label-row">
        <div class="label-with-icon">
          <Icon name="globe" size={13} color={auditEgress.length > 0 ? "#8ab4f8" : "#9aa0a6"} />
          <span class="metric-label">Network Connections</span>
        </div>
        {#if auditFilter === 'egress'}
          <span class="filter-active-tag">FILTERED</span>
        {/if}
      </div>
      <div class="metric-value">
        {auditEgress.length}
      </div>
      <div class="metric-subtext">
        {auditEgress.length === 0 ? '0 outbound calls' : 'Remote endpoints contacted'}
      </div>
    </div>

    <div
      role="button"
      tabindex="0"
      class="metric-card card-interactive"
      class:card-active={auditFilter === 'packages'}
      class:card-alert={auditPackages.length > 0}
      on:click={() => auditFilter = auditFilter === 'packages' ? 'all' : 'packages'}
      on:keydown={(e) => { if (e.key === 'Enter') auditFilter = auditFilter === 'packages' ? 'all' : 'packages'; }}
    >
      <div class="metric-label-row">
        <div class="label-with-icon">
          <Icon name="package" size={13} color={auditPackages.length > 0 ? "#81c995" : "#9aa0a6"} />
          <span class="metric-label">Package Installs</span>
        </div>
        {#if auditFilter === 'packages'}
          <span class="filter-active-tag">FILTERED</span>
        {/if}
      </div>
      <div class="metric-value">
        {auditPackages.length}
      </div>
      <div class="metric-subtext">
        {auditPackages.length === 0 ? '0 packages installed' : 'npm / pip / cargo / luarocks'}
      </div>
    </div>

    <div
      role="button"
      tabindex="0"
      class="metric-card card-interactive"
      class:card-active={auditFilter === 'injections'}
      class:card-alert={auditInjections.length > 0}
      on:click={() => auditFilter = auditFilter === 'injections' ? 'all' : 'injections'}
      on:keydown={(e) => { if (e.key === 'Enter') auditFilter = auditFilter === 'injections' ? 'all' : 'injections'; }}
    >
      <div class="metric-label-row">
        <div class="label-with-icon">
          <Icon name="shield-alert" size={13} color={auditInjections.length > 0 ? "#f28b82" : "#9aa0a6"} />
          <span class="metric-label">Prompt Injections</span>
        </div>
        {#if auditFilter === 'injections'}
          <span class="filter-active-tag">FILTERED</span>
        {/if}
      </div>
      <div class="metric-value" class:text-red={auditInjections.length > 0} class:text-green={auditInjections.length === 0}>
        {auditInjections.length}
      </div>
      <div class="metric-subtext">
        {auditInjections.length === 0 ? '0 injection vectors' : 'Adversarial patterns'}
      </div>
    </div>
  </div>

  <!-- Scrollable Audit Content Body -->
  <div class="audit-body-scroll">
    <!-- Filter & Search Toolbar -->
    <div class="audit-toolbar">
      <div class="filter-pills">
        <button class="pill-btn" class:active={auditFilter === 'all'} on:click={() => auditFilter = 'all'}>
          All Findings ({totalFindings})
        </button>
        <button class="pill-btn" class:active={auditFilter === 'secrets'} on:click={() => auditFilter = 'secrets'}>
          <Icon name="key" size={11} />
          <span>Credentials ({auditSecrets.length})</span>
        </button>
        <button class="pill-btn" class:active={auditFilter === 'escapes'} on:click={() => auditFilter = 'escapes'}>
          <Icon name="escape" size={11} />
          <span>Escapes ({auditEscapes.length})</span>
        </button>
        <button class="pill-btn" class:active={auditFilter === 'egress'} on:click={() => auditFilter = 'egress'}>
          <Icon name="globe" size={11} />
          <span>Network ({auditEgress.length})</span>
        </button>
        <button class="pill-btn" class:active={auditFilter === 'packages'} on:click={() => auditFilter = 'packages'}>
          <Icon name="package" size={11} />
          <span>Packages ({auditPackages.length})</span>
        </button>
        <button class="pill-btn" class:active={auditFilter === 'injections'} class:pill-alert={auditInjections.length > 0} on:click={() => auditFilter = 'injections'}>
          <Icon name="shield-alert" size={11} />
          <span>Injections ({auditInjections.length})</span>
        </button>
      </div>

      <div class="google-search-wrap audit-search-wrap">
        <Icon name="search" size={13} className="search-icon" color="#9aa0a6" />
        <input
          type="text"
          class="input-google-search search-log-input"
          placeholder="Filter findings..."
          bind:value={auditSearch}
        />
        {#if auditSearch}
          <button class="search-clear-btn" on:click={() => auditSearch = ''}>
            <Icon name="close" size={12} />
          </button>
        {/if}
      </div>
    </div>

    <!-- Deep-Dive Audit Panels Grid -->
    <div class="audit-pillars-grid">
      <!-- Pillar 1: Exposed Credentials -->
      {#if auditFilter === 'all' || auditFilter === 'secrets'}
        <div class="panel-card audit-pillar-card">
          <div class="pane-header">
            <div class="pane-header-title-group">
              <Icon name="key" size={14} color="#f28b82" />
              <span class="pane-title">Exposed Credentials</span>
            </div>
            <span class="badge-count" class:badge-active={auditSecrets.length > 0}>{auditSecrets.length}</span>
          </div>
          <div class="audit-card-body">
            <p class="pillar-desc">
              Monitors API tokens, private keys, GitHub tokens, and cloud service credentials.
            </p>
            {#if auditSecrets.length === 0}
              <div class="empty-state-card green-state">
                <div class="empty-icon-wrap">
                  <Icon name="shield-check" size={28} color="#81c995" />
                </div>
                <div class="empty-title">Zero Credentials Exposed</div>
                <div class="empty-sub">No API keys, access tokens, or private credentials detected in transcripts.</div>
              </div>
            {:else if filteredSecrets.length === 0}
              <div class="empty-state-card">
                <div class="empty-title">No Matching Findings</div>
                <div class="empty-sub">No credentials match "{auditSearch}"</div>
              </div>
            {:else}
              <div class="audit-table-wrap">
                <table class="audit-table">
                  <thead>
                    <tr>
                      <th>Step</th>
                      <th>Turn</th>
                      <th>Type</th>
                      <th>Token Preview</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {#each filteredSecrets as sec}
                      <tr>
                        <td>
                          <button class="step-link-btn" on:click={() => handleJump(sec.step, sec.turn_id)}>
                            #{sec.step}
                          </button>
                        </td>
                        <td>Turn #{sec.turn_id}</td>
                        <td><span class="pill-sec-type">{sec.type}</span></td>
                        <td>
                          <code class="code-preview font-mono">
                            {redactSecretPreview(sec.preview, $maskSecrets)}
                          </code>
                        </td>
                        <td>
                          <button class="btn btn-tiny btn-ghost" on:click={() => handleCopy(sec.preview)}>
                            <Icon name="copy" size={11} />
                            <span>Copy</span>
                          </button>
                        </td>
                      </tr>
                    {/each}
                  </tbody>
                </table>
              </div>
            {/if}
          </div>
        </div>
      {/if}

      <!-- Pillar 2: Workspace Perimeter Boundary -->
      {#if auditFilter === 'all' || auditFilter === 'escapes'}
        <div class="panel-card audit-pillar-card">
          <div class="pane-header">
            <div class="pane-header-title-group">
              <Icon name="escape" size={14} color="#fdd663" />
              <span class="pane-title">Workspace Perimeter</span>
            </div>
            <span class="badge-count" class:badge-active={auditEscapes.length > 0}>{auditEscapes.length}</span>
          </div>
          <div class="audit-card-body">
            <p class="pillar-desc">
              Monitors directory traversals and execution paths outside the workspace boundary.
            </p>
            {#if auditEscapes.length === 0}
              <div class="empty-state-card green-state">
                <div class="empty-icon-wrap">
                  <Icon name="shield-check" size={28} color="#81c995" />
                </div>
                <div class="empty-title">Perimeter Intact</div>
                <div class="empty-sub">All shell commands and file mutations executed inside the workspace root.</div>
              </div>
            {:else if filteredEscapes.length === 0}
              <div class="empty-state-card">
                <div class="empty-title">No Matching Findings</div>
                <div class="empty-sub">No boundary escapes match "{auditSearch}"</div>
              </div>
            {:else}
              <div class="audit-table-wrap">
                <table class="audit-table">
                  <thead>
                    <tr>
                      <th>Step</th>
                      <th>Turn</th>
                      <th>Reason</th>
                      <th>Path / Target</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {#each filteredEscapes as esc}
                      <tr>
                        <td>
                          <button class="step-link-btn" on:click={() => handleJump(esc.step, esc.turn_id)}>
                            #{esc.step}
                          </button>
                        </td>
                        <td>Turn #{esc.turn_id}</td>
                        <td><span class="pill-sec-warning">{esc.reason}</span></td>
                        <td><code class="code-preview font-mono">{esc.target || esc.cwd || 'N/A'}</code></td>
                        <td>
                          <button class="btn btn-tiny btn-ghost" on:click={() => handleJump(esc.step, esc.turn_id)}>
                            <span>Inspect</span>
                            <Icon name="chevron-right" size={11} />
                          </button>
                        </td>
                      </tr>
                    {/each}
                  </tbody>
                </table>
              </div>
            {/if}
          </div>
        </div>
      {/if}

      <!-- Pillar 3: Outbound Network Calls -->
      {#if auditFilter === 'all' || auditFilter === 'egress'}
        <div class="panel-card audit-pillar-card">
          <div class="pane-header">
            <div class="pane-header-title-group">
              <Icon name="globe" size={14} color="#8ab4f8" />
              <span class="pane-title">Network Connections</span>
            </div>
            <span class="badge-count" class:badge-active={auditEgress.length > 0}>{auditEgress.length}</span>
          </div>
          <div class="audit-card-body">
            <p class="pillar-desc">
              Monitors remote network connections, external endpoints, and git push/fetch targets.
            </p>
            {#if auditEgress.length === 0}
              <div class="empty-state-card green-state">
                <div class="empty-icon-wrap">
                  <Icon name="shield-check" size={28} color="#81c995" />
                </div>
                <div class="empty-title">Zero Remote Egress</div>
                <div class="empty-sub">No external network endpoints were contacted during execution.</div>
              </div>
            {:else if filteredEgress.length === 0}
              <div class="empty-state-card">
                <div class="empty-title">No Matching Findings</div>
                <div class="empty-sub">No network calls match "{auditSearch}"</div>
              </div>
            {:else}
              <div class="audit-table-wrap">
                <table class="audit-table">
                  <thead>
                    <tr>
                      <th>Step</th>
                      <th>Turn</th>
                      <th>Type</th>
                      <th>Destination</th>
                      <th>Timestamp</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {#each filteredEgress as eg}
                      <tr>
                        <td>
                          <button class="step-link-btn" on:click={() => handleJump(eg.step, eg.turn_id)}>
                            #{eg.step}
                          </button>
                        </td>
                        <td>Turn #{eg.turn_id}</td>
                        <td><span class="badge-egress-type">{eg.type.toUpperCase()}</span></td>
                        <td><code class="code-preview font-mono" title={eg.destination}>{eg.destination}</code></td>
                        <td class="text-muted">{formatLocalTime(eg.timestamp)}</td>
                        <td>
                          <button class="btn btn-tiny btn-ghost" on:click={() => handleJump(eg.step, eg.turn_id)}>
                            <span>Inspect</span>
                            <Icon name="chevron-right" size={11} />
                          </button>
                        </td>
                      </tr>
                    {/each}
                  </tbody>
                </table>
              </div>
            {/if}
          </div>
        </div>
      {/if}

      <!-- Pillar 4: Supply Chain Packages -->
      {#if auditFilter === 'all' || auditFilter === 'packages'}
        <div class="panel-card audit-pillar-card">
          <div class="pane-header">
            <div class="pane-header-title-group">
              <Icon name="package" size={14} color="#81c995" />
              <span class="pane-title">Package Installations</span>
            </div>
            <span class="badge-count" class:badge-active={auditPackages.length > 0}>{auditPackages.length}</span>
          </div>
          <div class="audit-card-body">
            <p class="pillar-desc">
              Tracks package dependencies installed via package managers.
            </p>
            {#if auditPackages.length === 0}
              <div class="empty-state-card green-state">
                <div class="empty-icon-wrap">
                  <Icon name="shield-check" size={28} color="#81c995" />
                </div>
                <div class="empty-title">Supply Chain Clean</div>
                <div class="empty-sub">No third-party packages installed during session.</div>
              </div>
            {:else if filteredPackages.length === 0}
              <div class="empty-state-card">
                <div class="empty-title">No Matching Findings</div>
                <div class="empty-sub">No packages match "{auditSearch}"</div>
              </div>
            {:else}
              <div class="audit-table-wrap">
                <table class="audit-table">
                  <thead>
                    <tr>
                      <th>Step</th>
                      <th>Turn</th>
                      <th>Manager</th>
                      <th>Package</th>
                      <th>Timestamp</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {#each filteredPackages as pkg}
                      <tr>
                        <td>
                          <button class="step-link-btn" on:click={() => handleJump(pkg.step, pkg.turn_id)}>
                            #{pkg.step}
                          </button>
                        </td>
                        <td>Turn #{pkg.turn_id}</td>
                        <td><span class="badge-pkg-mgr">{pkg.manager}</span></td>
                        <td><code class="font-mono">{pkg.package}</code></td>
                        <td class="text-muted">{formatLocalTime(pkg.timestamp)}</td>
                        <td>
                          <button class="btn btn-tiny btn-ghost" on:click={() => handleJump(pkg.step, pkg.turn_id)}>
                            <span>Inspect</span>
                            <Icon name="chevron-right" size={11} />
                          </button>
                        </td>
                      </tr>
                    {/each}
                  </tbody>
                </table>
              </div>
            {/if}
          </div>
        </div>
      {/if}
      <!-- Pillar 5: Prompt Injections & Jailbreak Vectors -->
      {#if auditFilter === 'all' || auditFilter === 'injections'}
        <div class="panel-card audit-pillar-card">
          <div class="pane-header">
            <div class="pane-header-title-group">
              <Icon name="shield-alert" size={14} color="#f28b82" />
              <span class="pane-title">Prompt Injections & Jailbreak Vectors</span>
            </div>
            <span class="badge-count" class:badge-active={auditInjections.length > 0}>{auditInjections.length}</span>
          </div>
          <div class="audit-card-body">
            <p class="pillar-desc">
              Detects indirect prompt injection vectors, system role spoofing, instruction overrides, and jailbreak signatures in inputs and tool outputs.
            </p>
            {#if auditInjections.length === 0}
              <div class="empty-state-card green-state">
                <div class="empty-icon-wrap">
                  <Icon name="shield-check" size={28} color="#81c995" />
                </div>
                <div class="empty-title">Zero Injection Vectors Detected</div>
                <div class="empty-sub">All inputs, tool results, and command streams are clean of adversarial injection patterns.</div>
              </div>
            {:else if filteredInjections.length === 0}
              <div class="empty-state-card">
                <div class="empty-title">No Matching Findings</div>
                <div class="empty-sub">No prompt injection findings match "{auditSearch}"</div>
              </div>
            {:else}
              <div class="audit-table-wrap">
                <table class="audit-table">
                  <thead>
                    <tr>
                      <th>Step</th>
                      <th>Turn</th>
                      <th>Category</th>
                      <th>Source / Context</th>
                      <th>Evidence Snippet</th>
                      <th>Severity</th>
                      <th>Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {#each filteredInjections as inj}
                      <tr>
                        <td>
                          <button class="step-link-btn" on:click={() => handleJump(inj.step, inj.turn_id)}>
                            #{inj.step}
                          </button>
                        </td>
                        <td>Turn #{inj.turn_id}</td>
                        <td><span class="pill-sec-danger">{inj.type}</span></td>
                        <td><code class="font-mono text-muted">{inj.source || inj.target || 'Tool Output'}</code></td>
                        <td><code class="code-preview font-mono" title={inj.snippet}>{inj.snippet}</code></td>
                        <td><span class="pill-sec-warning">{inj.severity.toUpperCase()}</span></td>
                        <td>
                          <button class="btn btn-tiny btn-ghost" on:click={() => handleJump(inj.step, inj.turn_id)}>
                            <span>Inspect</span>
                            <Icon name="chevron-right" size={11} />
                          </button>
                        </td>
                      </tr>
                    {/each}
                  </tbody>
                </table>
              </div>
            {/if}
          </div>
        </div>
      {/if}
    </div>
  </div>
</main>
