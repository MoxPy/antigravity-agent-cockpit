<script lang="ts">
  import { reports, viewReport, revealReport, exportReport, isExporting } from '../stores/sessionStore';
  import { showVaultModal, vaultReportContent, vaultReportFilename, showToast } from '../stores/uiStore';
  import { copyToClipboard } from '../lib/formatters';
  import { toArray } from '../lib/security';
  import Icon from './Icon.svelte';

  async function handleCopy() {
    if ($vaultReportContent) {
      const ok = await copyToClipboard($vaultReportContent);
      if (ok) showToast('Report copied to clipboard');
    }
  }

  function handleClose() {
    $showVaultModal = false;
    $vaultReportContent = null;
    $vaultReportFilename = null;
  }
</script>

{#if $showVaultModal}
  <!-- svelte-ignore a11y-click-events-have-key-events -->
  <!-- svelte-ignore a11y-no-static-element-interactions -->
  <div class="modal-backdrop" on:click={handleClose}>
    <!-- svelte-ignore a11y-no-noninteractive-element-interactions -->
    <div class="modal-dialog" on:click|stopPropagation role="dialog" aria-modal="true">
      <div class="modal-header">
        <div class="modal-title-wrap">
          <Icon name={$vaultReportContent ? "list" : "folder"} size={16} color="#8ab4f8" />
          <span class="modal-title">
            {#if $vaultReportContent}
              {$vaultReportFilename}
            {:else}
              Compliance Reports Vault ({$reports.length})
            {/if}
          </span>
        </div>
        <button class="modal-close" on:click={handleClose} aria-label="Close dialog">
          <Icon name="close" size={16} />
        </button>
      </div>

      <div class="modal-body">
        {#if $vaultReportContent}
          <div class="report-view-actions">
            <button class="btn btn-secondary btn-sm" on:click={() => $vaultReportContent = null}>
              <Icon name="chevron-left" size={13} />
              <span>Back to Reports List</span>
            </button>
            <div class="action-buttons-group">
              <button class="btn btn-secondary btn-sm" on:click={handleCopy}>
                <Icon name="copy" size={13} />
                <span>Copy Markdown</span>
              </button>
              {#if $vaultReportFilename}
                <button class="btn btn-primary btn-sm" on:click={() => revealReport($vaultReportFilename || '')}>
                  <Icon name="folder" size={13} />
                  <span>Reveal in Finder</span>
                </button>
              {/if}
            </div>
          </div>
          <pre class="report-content-pre font-mono"><code>{$vaultReportContent}</code></pre>
        {:else if $reports.length === 0}
          <div class="empty-state-modal">
            <div class="empty-icon-wrap">
              <Icon name="folder" size={36} color="#8ab4f8" />
            </div>
            <div class="empty-title">No Audit Reports Yet</div>
            <div class="empty-sub">
              Generate full markdown compliance audits documenting every operation, security boundary verification, and file modification.
            </div>
            <button class="btn btn-primary mt-4" on:click={() => exportReport()} disabled={$isExporting}>
              <Icon name="download" size={14} />
              <span>{$isExporting ? 'Generating Report...' : 'Generate Compliance Audit'}</span>
            </button>
          </div>
        {:else}
          <div class="modal-reports-list">
            {#each $reports as r}
              <div class="modal-report-row">
                <div class="report-row-info">
                  <div class="report-file-title-wrap">
                    <Icon name="list" size={14} color="#8ab4f8" />
                    <span class="report-row-name font-mono">{r.filename}</span>
                  </div>
                  <span class="report-row-meta">{r.date} &bull; {r.size_kb} KB</span>
                </div>
                <div class="report-row-actions">
                  <button class="btn btn-sm btn-secondary" on:click={() => viewReport(r.filename)}>
                    <Icon name="eye" size={12} />
                    <span>View</span>
                  </button>
                  <button class="btn btn-sm btn-ghost" on:click={() => revealReport(r.filename)}>
                    <Icon name="folder" size={12} />
                    <span>Finder</span>
                  </button>
                </div>
              </div>
            {/each}
          </div>
        {/if}
      </div>

      <div class="modal-footer">
        <button class="btn btn-secondary" on:click={handleClose}>
          Close
        </button>
      </div>
    </div>
  </div>
{/if}
