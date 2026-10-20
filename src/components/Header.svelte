<script lang="ts">
  import { summary, reports, statusMsg, isExporting, exportReport, sessions, selectedSessionId, isLoadingSession, fetchSessions, switchSession } from "../stores/sessionStore";
  import { viewMode, showTurnsNav, showInspector, toastMessage, showVaultModal, showToast } from "../stores/uiStore";
  import { copyToClipboard } from "../lib/formatters";
  import { toArray } from "../lib/security";
  import Icon from "./Icon.svelte";

  $: sec = $summary?.security_audit;
  $: auditSecrets = toArray(sec?.secrets);
  $: auditEscapes = toArray(sec?.boundary_escapes);
  $: auditEgress = toArray(sec?.network_egress);
  $: auditPackages = toArray(sec?.packages);
  $: auditInjections = toArray(sec?.injections);
  $: securityAuditTotal = auditSecrets.length + auditEscapes.length + auditEgress.length + auditPackages.length + auditInjections.length;

  let isDropdownOpen = false;
  let dropdownRef: HTMLElement;

  function toggleDropdown(e: MouseEvent) {
    e.stopPropagation();
    isDropdownOpen = !isDropdownOpen;
    if (isDropdownOpen) {
      fetchSessions();
    }
  }

  function handleSelectSession(uuid: string, e: MouseEvent) {
    e.stopPropagation();
    switchSession(uuid);
    isDropdownOpen = false;
  }

  function handleClickOutside(e: MouseEvent) {
    if (isDropdownOpen && dropdownRef && !dropdownRef.contains(e.target as Node)) {
      isDropdownOpen = false;
    }
  }

  async function handleCopySession() {
    if ($selectedSessionId) {
      const ok = await copyToClipboard($selectedSessionId);
      if (ok) showToast("Session UUID copied");
    }
  }
</script>

<svelte:window on:click={handleClickOutside} />

<header class="cockpit-header">
  <div class="header-left">
    <div class="brand-group">
      <div class="app-icon" title="Antigravity Agent Cockpit">
        <img src="/app-icon.png" alt="Antigravity Logo" class="brand-logo-img" />
      </div>
      <div class="brand-text">
        <div class="title-row">
          <h1 class="app-title">Antigravity</h1>
          <span class="product-subtitle">Agent Cockpit</span>
          <span class="badge-tech">BRAIN</span>
        </div>
        <div class="app-badge-row">
          {#if $selectedSessionId || $summary.session_uuid}
            <div class="session-selector-container" bind:this={dropdownRef}>
              <div class="session-chip-group" class:is-loading={$isLoadingSession}>
                <button
                  class="session-chip"
                  on:click={toggleDropdown}
                  title="Session: {$selectedSessionId}. Click to switch conversations."
                  aria-haspopup="true"
                  aria-expanded={isDropdownOpen}
                >
                  {#if $isLoadingSession}
                    <Icon name="refresh" size={11} className="chip-icon spinning" />
                    <span class="session-id-text">Loading...</span>
                  {:else}
                    <span class="status-pulse-dot mini-pulse"></span>
                    <span class="session-id-text font-mono">{$selectedSessionId ? $selectedSessionId.slice(0, 8) : "Session"}</span>
                  {/if}
                  <Icon name={isDropdownOpen ? "chevron-up" : "chevron-down"} size={10} className="dropdown-arrow" />
                </button>

                <button
                  class="session-copy-btn"
                  on:click={handleCopySession}
                  title="Copy full UUID: {$selectedSessionId}"
                  aria-label="Copy session UUID"
                >
                  <Icon name="copy" size={10} />
                </button>
              </div>

              {#if isDropdownOpen}
                <div class="sessions-dropdown" role="menu">
                  <div class="dropdown-header">
                    <div class="header-label">
                      <Icon name="clock" size={13} color="#9aa0a6" />
                      <span>Conversations ({$sessions.length})</span>
                    </div>
                    <button
                      class="btn-refresh-sessions"
                      on:click={() => fetchSessions()}
                      title="Refresh session list"
                    >
                      <Icon name="refresh" size={12} />
                    </button>
                  </div>

                  <div class="sessions-list">
                    {#each $sessions as s (s.session_uuid)}
                      <button
                        class="session-item"
                        class:selected={$selectedSessionId === s.session_uuid}
                        on:click={(e) => handleSelectSession(s.session_uuid, e)}
                      >
                        <div class="item-icon-col">
                          {#if s.session_uuid === $selectedSessionId}
                            <span class="status-pulse-dot"></span>
                          {:else}
                            <Icon name="folder" size={13} color="#8ab4f8" />
                          {/if}
                        </div>
                        <div class="item-body">
                          <div class="item-top">
                            <span class="item-title font-mono">{s.short_id}</span>
                            <span class="item-steps">{s.total_steps} steps</span>
                          </div>
                          <p class="item-preview" title={s.preview}>{s.preview}</p>
                        </div>
                        {#if $selectedSessionId === s.session_uuid}
                          <Icon name="check" size={13} color="#81c995" />
                        {/if}
                      </button>
                    {/each}
                  </div>
                </div>
              {/if}
            </div>
          {/if}
          <div class="status-indicator live">
            <span class="status-dot"></span>
            <span class="status-text">{$statusMsg}</span>
          </div>
        </div>
      </div>
    </div>
  </div>

  <div class="header-center">
    <nav class="mode-switcher" aria-label="Google Cloud View Mode Switcher">
      <button
        class="mode-btn"
        class:active={$viewMode === 'turns'}
        on:click={() => $viewMode = 'turns'}
      >
        <Icon name="layers" size={15} />
        <span>Turn Situation</span>
        <span class="mode-counter">{$summary.total_turns || 0}</span>
      </button>

      <button
        class="mode-btn"
        class:active={$viewMode === 'log'}
        on:click={() => $viewMode = 'log'}
      >
        <Icon name="list" size={15} />
        <span>Granular Log</span>
        <span class="mode-counter">{$summary.total_steps || 0}</span>
      </button>

      <button
        class="mode-btn mode-btn-audit"
        class:active={$viewMode === 'audit'}
        class:has-alerts={securityAuditTotal > 0}
        on:click={() => $viewMode = 'audit'}
      >
        <Icon name={securityAuditTotal > 0 ? "shield-alert" : "shield"} size={15} />
        <span>Perimeter & Security</span>
        <span class="mode-counter" class:counter-alert={securityAuditTotal > 0}>
          {securityAuditTotal}
        </span>
      </button>
    </nav>
  </div>

  <div class="header-right">
    {#if $toastMessage}
      <div class="feedback-toast" role="status">
        <Icon name="check" size={13} color="#81c995" />
        <span>{$toastMessage}</span>
      </div>
    {/if}

    {#if $viewMode === 'turns'}
      <div class="panel-toggles-group">
        <button
          class="btn-panel-toggle"
          class:active={$showTurnsNav}
          on:click={() => $showTurnsNav = !$showTurnsNav}
          title="Toggle Turns Navigator (Left Drawer)"
        >
          <Icon name="sidebar" size={14} />
          <span>Turns</span>
        </button>
        <button
          class="btn-panel-toggle"
          class:active={$showInspector}
          on:click={() => $showInspector = !$showInspector}
          title="Toggle Step Inspector (Right Drawer)"
        >
          <Icon name="tune" size={14} />
          <span>Inspector</span>
        </button>
      </div>
    {/if}

    <button
      class="btn btn-secondary btn-sm"
      on:click={() => $showVaultModal = true}
      title="Open Compliance Reports Vault"
    >
      <Icon name="folder" size={14} />
      <span>Vault ({$reports.length})</span>
    </button>

    <button
      class="btn btn-primary btn-sm"
      on:click={() => exportReport()}
      disabled={$isExporting}
      title="Generate full Markdown Audit Report"
    >
      <Icon name="download" size={14} />
      <span>{$isExporting ? 'Exporting...' : 'Export Audit'}</span>
    </button>
  </div>
</header>
