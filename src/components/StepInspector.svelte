<script lang="ts">
  import { radar, reports, viewReport, revealReport } from '../stores/sessionStore';
  import { selectedStep, showInspector, showToast, maskSecrets } from '../stores/uiStore';
  import { formatLocalTime, formatFullCommand, copyToClipboard } from '../lib/formatters';
  import { redactSecretPreview, redactText, toArray } from '../lib/security';
  import Icon from './Icon.svelte';

  async function handleCopy(text: string, label = 'Copied') {
    const ok = await copyToClipboard(text);
    if (ok) showToast(label);
  }
</script>

<aside class="step-inspector-pane" aria-label="Step Details Inspector">
  <div class="pane-header">
    <div class="pane-header-title-group">
      <Icon name="tune" size={14} color="#8ab4f8" />
      <span class="pane-title">Inspector</span>
      {#if $selectedStep}
        <span class="pane-counter">#{$selectedStep.step}</span>
      {/if}
    </div>
    <button
      class="btn-pane-close"
      on:click={() => $showInspector = false}
      title="Collapse Inspector"
      aria-label="Collapse Inspector"
    >
      <Icon name="close" size={14} />
    </button>
  </div>

  <div class="inspector-scroll-body">
    {#if !$selectedStep}
      <div class="empty-state">
        <Icon name="search" size={28} color="#5f6368" />
        <span class="empty-title">No Step Selected</span>
        <p class="empty-sub">Click any step from the execution timeline to inspect parameters and command lines.</p>
      </div>
    {:else}
      <!-- Security & Risk Banners -->
      {#if $selectedStep.secret_findings && $selectedStep.secret_findings.length > 0}
        <div class="inspector-security-alert alert-critical">
          <div class="sec-alert-header">
            <Icon name="key" size={15} color="#f28b82" />
            <span class="sec-alert-title">EXPOSED CREDENTIAL</span>
          </div>
          <ul class="sec-alert-list">
            {#each $selectedStep.secret_findings as sf}
              <li>
                <strong>{sf.type}</strong>:
                <code>{redactSecretPreview(sf.preview, $maskSecrets)}</code>
              </li>
            {/each}
          </ul>
        </div>
      {/if}

      {#if $selectedStep.is_boundary_escape}
        <div class="inspector-security-alert alert-high">
          <div class="sec-alert-header">
            <Icon name="escape" size={15} color="#f28b82" />
            <span class="sec-alert-title">BOUNDARY ESCAPE</span>
          </div>
          <div class="sec-alert-desc">{$selectedStep.boundary_escape_reason || 'Operation executed outside project workspace root.'}</div>
        </div>
      {/if}

      {#if $selectedStep.network_egress}
        <div class="inspector-security-alert alert-medium">
          <div class="sec-alert-header">
            <Icon name="globe" size={15} color="#fdd663" />
            <span class="sec-alert-title">NETWORK EGRESS</span>
          </div>
          <div class="sec-alert-desc">Destination: <code>{$selectedStep.network_egress.destination}</code> ({$selectedStep.network_egress.type})</div>
        </div>
      {/if}

      {#if $selectedStep.package_installed}
        <div class="inspector-security-alert alert-medium">
          <div class="sec-alert-header">
            <Icon name="package" size={15} color="#8ab4f8" />
            <span class="sec-alert-title">PACKAGE INSTALLED</span>
          </div>
          <div class="sec-alert-desc">Manager: <strong>{$selectedStep.package_installed.manager}</strong> &bull; Package: <code>{$selectedStep.package_installed.package}</code></div>
        </div>
      {/if}

      {#if $selectedStep.injection_finding}
        <div class="inspector-security-alert alert-critical">
          <div class="sec-alert-header">
            <Icon name="shield-alert" size={15} color="#f28b82" />
            <span class="sec-alert-title">PROMPT INJECTION / JAILBREAK VECTOR ({$selectedStep.injection_finding.type.toUpperCase()})</span>
          </div>
          <div class="sec-alert-desc">
            Severity: <strong>{$selectedStep.injection_finding.severity.toUpperCase()}</strong> &bull; Source: <code>{$selectedStep.injection_finding.source}</code>
          </div>
          <div class="injection-snippet-box">
            <span class="snippet-label">Detected Pattern:</span>
            <code>{$selectedStep.injection_finding.snippet}</code>
          </div>
        </div>
      {/if}

      {#if $selectedStep.risk_level && $selectedStep.risk_level !== 'safe'}
        <div class="inspector-security-alert alert-{$selectedStep.risk_level}">
          <div class="sec-alert-header">
            <Icon name="warning" size={15} color="#f28b82" />
            <span class="sec-alert-title">POLICY FLAG ({$selectedStep.risk_level.toUpperCase()} RISK)</span>
          </div>
          <ul class="sec-alert-list">
            {#each $selectedStep.risk_reasons || [] as reason}
              <li>{reason}</li>
            {/each}
          </ul>
        </div>
      {/if}

      <!-- Step Meta Card -->
      <div class="inspector-card">
        <div class="inspector-meta-row">
          <div class="meta-field">
            <span class="meta-label">OPERATION</span>
            <span class="meta-val font-mono">{$selectedStep.tool || $selectedStep.raw_type || $selectedStep.category}</span>
          </div>
          <div class="meta-field">
            <span class="meta-label">TIMESTAMP</span>
            <span class="meta-val">{formatLocalTime($selectedStep.timestamp)}</span>
          </div>
          <div class="meta-field">
            <span class="meta-label">STATUS</span>
            <span class="meta-val badge-status">{$selectedStep.status}</span>
          </div>
        </div>

        {#if $selectedStep.cwd}
          <div class="meta-field-full">
            <span class="meta-label">WORKING DIR</span>
            <span class="meta-val-path font-mono">{$selectedStep.cwd}</span>
          </div>
        {/if}

        <div class="meta-field-full">
          <span class="meta-label">SUMMARY</span>
          <div class="meta-val-desc">{$selectedStep.summary}</div>
        </div>
      </div>

      <!-- Execution Command Box -->
      {#if $selectedStep.command || ($selectedStep.category === 'terminal' && $selectedStep.details)}
        <div class="inspector-card">
          <div class="card-title-bar">
            <div class="card-title-left">
              <Icon name="terminal" size={12} color="#8ab4f8" />
              <span class="card-title">SHELL COMMAND</span>
            </div>
            <button
              class="btn-copy"
              on:click={() => handleCopy($selectedStep?.command || $selectedStep?.details || '', 'Command copied')}
            >
              <Icon name="copy" size={11} />
              <span>Copy</span>
            </button>
          </div>
          <div class="cmd-box-wrap">
            <pre class="code-box-inspector"><code>{formatFullCommand(redactText($selectedStep.command || $selectedStep.details, $maskSecrets))}</code></pre>
          </div>
        </div>
      {/if}

      <!-- Target File Box -->
      {#if $selectedStep.target}
        <div class="inspector-card">
          <div class="card-title-bar">
            <div class="card-title-left">
              <Icon name="edit" size={12} color="#81c995" />
              <span class="card-title">TARGET FILE</span>
            </div>
            <button
              class="btn-copy"
              on:click={() => handleCopy($selectedStep?.target || '', 'Path copied')}
            >
              <Icon name="copy" size={11} />
              <span>Copy</span>
            </button>
          </div>
          <div class="target-path-box font-mono">{$selectedStep.target}</div>
        </div>
      {/if}

      <!-- Detailed Description Box -->
      {#if $selectedStep.details && $selectedStep.details !== $selectedStep.summary && !$selectedStep.command}
        <div class="inspector-card">
          <div class="card-title-bar">
            <div class="card-title-left">
              <Icon name="list" size={12} color="#9aa0a6" />
              <span class="card-title">DETAILS</span>
            </div>
            <button
              class="btn-copy"
              on:click={() => handleCopy($selectedStep?.details || '', 'Details copied')}
            >
              <Icon name="copy" size={11} />
              <span>Copy</span>
            </button>
          </div>
          <pre class="code-box-inspector"><code>{redactText($selectedStep.details, $maskSecrets)}</code></pre>
        </div>
      {/if}

      <!-- Reasoning Trace Box -->
      {#if $selectedStep.thinking}
        <div class="inspector-card">
          <div class="card-title-bar">
            <div class="card-title-left">
              <Icon name="gemini" size={12} />
              <span class="card-title">THINKING</span>
            </div>
            <button
              class="btn-copy"
              on:click={() => handleCopy($selectedStep?.thinking || '', 'Thinking copied')}
            >
              <Icon name="copy" size={11} />
              <span>Copy</span>
            </button>
          </div>
          <div class="thought-inspector-box">{$selectedStep.thinking}</div>
        </div>
      {/if}
    {/if}

    <!-- Workspace Radar Panel -->
    <div class="radar-panel-block">
      <div class="panel-section-title">
        <div class="title-left">
          <Icon name="layers" size={12} color="#8ab4f8" />
          <span>Git Repositories</span>
        </div>
        <span class="radar-count">{$radar.length} repos</span>
      </div>
      <div class="radar-list">
        {#if $radar.length === 0}
          <div class="radar-empty">No active Git repositories detected in workspace.</div>
        {:else}
          {#each $radar as repo}
            <div class="radar-item">
              <div class="radar-item-left">
                <span class="repo-name">{repo.name}</span>
                <span class="branch-pill">{repo.branch}</span>
              </div>
              <span class="mod-pill" class:has-mods={repo.modified_files > 0}>
                {repo.modified_files} modified
              </span>
            </div>
          {/each}
        {/if}
      </div>
    </div>

    <!-- Exported Compliance Audits Panel -->
    <div class="radar-panel-block">
      <div class="panel-section-title">
        <div class="title-left">
          <Icon name="folder" size={12} color="#fdd663" />
          <span>Audit Reports</span>
        </div>
        <span class="radar-count">{$reports.length} files</span>
      </div>
      {#if $reports.length === 0}
        <div class="radar-empty">No reports generated yet. Click "Export Audit" to generate one.</div>
      {:else}
        <div class="audit-history-list">
          {#each $reports.slice(0, 5) as r}
            <div class="audit-item">
              <div class="audit-info">
                <div class="audit-name" title={r.filename}>{r.filename}</div>
                <div class="audit-meta">{r.date} &bull; {r.size_kb} KB</div>
              </div>
              <div class="audit-actions">
                <button class="btn btn-tiny" on:click={() => viewReport(r.filename)} title="Preview report markdown">
                  <Icon name="eye" size={11} />
                  <span>View</span>
                </button>
                <button class="btn btn-tiny" on:click={() => revealReport(r.filename)} title="Show file in macOS Finder">
                  <Icon name="folder" size={11} />
                  <span>Finder</span>
                </button>
              </div>
            </div>
          {/each}
        </div>
      {/if}
    </div>
  </div>
</aside>
