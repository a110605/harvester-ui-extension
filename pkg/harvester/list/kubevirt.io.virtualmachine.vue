<script>
import { mapGetters } from 'vuex';
import ResourceTable from '@shell/components/ResourceTable';
import { STATE, AGE, NAME, NAMESPACE } from '@shell/config/table-headers';
import {
  PVC, PV, NODE, POD, STORAGE_CLASS
} from '@shell/config/types';

import { allHash } from '@shell/utils/promise';
import Loading from '@shell/components/Loading';
import { clone } from '@shell/utils/object';
import PercentageBar from '@shell/components/PercentageBar';
import { HCI } from '../types';
import HarvesterVmState from '../formatters/HarvesterVmState';
import ConsoleBar from '../components/VMConsoleBar';

const ENCRYPTED_VOLUME_TOOLTIP_KEYS = {
  all:     'harvester.virtualMachine.volume.lockTooltip.all',
  partial: 'harvester.virtualMachine.volume.lockTooltip.partial',
};

export const VM_HEADERS = [
  STATE,
  {
    ...NAME,
    width: 350,
    value: 'nameDisplay',
    sort:  ['nameDisplay'],
  },
  NAMESPACE,
  {
    name:        'CPU',
    label:       'CPU',
    sort:        ['displayCPU'],
    value:       'displayCPU',
    align:       'center',
    dashIfEmpty: true,
  },
  {
    name:          'Memory',
    value:         'displayMemory',
    sort:          ['memorySort'],
    align:         'center',
    labelKey:      'tableHeaders.memory',
    formatter:     'Si',
    formatterOpts: {
      opts: {
        increment: 1024, addSuffix: true, maxExponent: 3, minExponent: 3, suffix: 'i',
      },
      needParseSi: true
    },
  },
  {
    name:      'ip',
    label:     'IP Address',
    value:     'id',
    formatter: 'HarvesterIpAddress',
    labelKey:  'tableHeaders.ipAddress',
    sort:      ['id'],
  },
  {
    ...AGE,
    sort: 'metadata.creationTimestamp:desc',
  }
];

export default {
  name:       'HarvesterListVM',
  components: {
    Loading,
    PercentageBar,
    HarvesterVmState,
    ConsoleBar,
    ResourceTable
  },

  props: {
    schema: {
      type:     Object,
      required: true,
    },
  },

  async fetch() {
    const inStore = this.$store.getters['currentProduct'].inStore;
    const _hash = {
      vms:     this.$store.dispatch(`${ inStore }/findAll`, { type: HCI.VM, opt: { force: true } }),
      pod:     this.$store.dispatch(`${ inStore }/findAll`, { type: POD }),
      pvcs:    this.$store.dispatch(`${ inStore }/findAll`, { type: PVC }),
      pvs:     this.$store.dispatch(`${ inStore }/findAll`, { type: PV }),
      images:  this.$store.dispatch(`${ inStore }/findAll`, { type: HCI.IMAGE }),
      restore: this.$store.dispatch(`${ inStore }/findAll`, { type: HCI.RESTORE }),
      backups: this.$store.dispatch(`${ inStore }/findAll`, { type: HCI.BACKUP }),
      storage: this.$store.dispatch(`${ inStore }/findAll`, { type: STORAGE_CLASS }),
    };

    if (this.$store.getters[`${ inStore }/schemaFor`](HCI.RESOURCE_QUOTA)) {
      _hash.resourceQuotas = this.$store.dispatch(`${ inStore }/findAll`, { type: HCI.RESOURCE_QUOTA });
    }

    if (this.$store.getters[`${ inStore }/schemaFor`](NODE)) {
      _hash.nodes = this.$store.dispatch(`${ inStore }/findAll`, { type: NODE });
      this.hasNode = true;
    }

    const hash = await allHash(_hash);

    this.allVMs = hash.vms;
  },

  data() {
    return {
      hasNode:                      false,
      allVMs:                       [],
      allVMIs:                      [],
      restartNotificationDisplayed: false,
      actionProgressByVmId:         {},
      progressTimersByVmId:         {},
      HCI
    };
  },

  computed: {
    ...mapGetters({ actionCb: 'action-menu/performCallbackData' }),

    headers() {
      const restoreCol = {
        name:      'restoreProgress',
        labelKey:  'harvester.tableHeaders.restore',
        value:     'restoreProgress',
        align:     'left',
        formatter: 'HarvesterBackupProgressBar',
        width:     200,
      };
      const nodeCol = {
        name:      'node',
        label:     'Node',
        value:     'nodeName',
        sort:      ['realAttachNodeName'],
        formatter: 'HarvesterHost',
        labelKey:  'harvester.tableHeaders.vm.node'
      };

      const cols = clone(VM_HEADERS);

      if (this.hasNode) {
        cols.splice(-1, 0, nodeCol);
      }

      if (this.hasBackUpRestoreInProgress) {
        cols.splice(-1, 0, restoreCol);
      }

      return cols;
    },

    rows() {
      const matchVMIs = this.allVMIs.filter((VMI) => !this.allVMs.find((VM) => VM.id === VMI.id));

      return [...this.allVMs, ...matchVMIs];
    },

    /**
     * We want to show the progress bar only for Backup's restore; snapshot's restore is immediate.
     */
    hasBackUpRestoreInProgress() {
      return !!this.rows.find((r) => r.restoreResource && !r.restoreResource.fromSnapshot && !r.restoreResource.isComplete);
    },

    vmRestartRequiredNames() {
      return this.allVMs
        .filter((vm) => vm.isRestartRequired)
        .map((vm) => vm.metadata.name);
    }
  },

  async created() {
    const inStore = this.$store.getters['currentProduct'].inStore;
    const vmis = await this.$store.dispatch(`${ inStore }/findAll`, { type: HCI.VMI });

    await this.$store.dispatch(`${ inStore }/findAll`, { type: HCI.VMIM });

    this['allVMIs'] = vmis;
  },

  beforeUnmount() {
    Object.values(this.progressTimersByVmId).forEach(({ intervalId, timeoutId }) => {
      clearInterval(intervalId);
      clearTimeout(timeoutId);
    });
    this.progressTimersByVmId = {};

    // clear restart message before component unmount
    this.$store.dispatch('growl/clear');
  },

  watch: {
    actionCb(neu) {
      if (neu?.performCallback && this.shouldShowActionProgress(neu?.action) && Array.isArray(neu?.resourceIds)) {
        this.startActionProgress(neu.resourceIds);
      }

      if (neu?.clearTableSelection) {
        this.$refs.resourceTable.clearSelection();
        this.$store.dispatch('action-menu/clearCallbackData');
      }
    },

    vmRestartRequiredNames(vmNames) {
      const count = vmNames.length;

      if (count === 0 && this.restartNotificationDisplayed) {
        this.restartNotificationDisplayed = false;

        return;
      }

      if (count > 0) {
        // clear old notification before showing new one
        if (this.restartNotificationDisplayed) {
          this.$store.dispatch('growl/clear');
        }

        this.$store.dispatch('growl/warning', {
          title:   this.t('harvester.notification.restartRequired.title', { count }),
          message: this.t('harvester.notification.restartRequired.message', { vmNames: vmNames.join(', ') }),
          timeout: 10000,
        }, { root: true });
        this.restartNotificationDisplayed = true;
      }
    }
  },
  methods: {
    shouldShowActionProgress(action) {
      const key = (action || '').toLowerCase();

      return ['restart', 'stop', 'start', 'pause', 'forcestop'].includes(key);
    },

    startActionProgress(resourceIds = []) {
      resourceIds.forEach((id) => {
        if (!id) {
          return;
        }

        const existingTimers = this.progressTimersByVmId[id];

        if (existingTimers) {
          clearInterval(existingTimers.intervalId);
          clearTimeout(existingTimers.timeoutId);
        }

        const duration = 15000;
        const startedAt = Date.now();

        this.actionProgressByVmId[id] = 0;

        const intervalId = setInterval(() => {
          const elapsed = Date.now() - startedAt;
          const nextValue = Math.min(100, Math.round((elapsed / duration) * 100));

          this.actionProgressByVmId[id] = nextValue;

          if (nextValue >= 100) {
            clearInterval(intervalId);
          }
        }, 180);

        const timeoutId = setTimeout(() => {
          clearInterval(intervalId);
          this.actionProgressByVmId[id] = 100;

          const cleanupTimeoutId = setTimeout(() => {
            delete this.actionProgressByVmId[id];
            delete this.progressTimersByVmId[id];
          }, 1200);

          if (this.progressTimersByVmId[id]) {
            this.progressTimersByVmId[id] = {
              intervalId,
              timeoutId: cleanupTimeoutId,
            };
          }
        }, duration);

        this.progressTimersByVmId[id] = { intervalId, timeoutId };
      });
    },

    actionProgressValue(row) {
      return this.actionProgressByVmId?.[row?.id];
    },

    lockIconTooltipMessage(row) {
      const key = ENCRYPTED_VOLUME_TOOLTIP_KEYS[row.encryptedVolumeType];

      return key ? this.t(key) : '';
    }
  }
};
</script>

<template>
  <Loading v-if="$fetchState.pending" />
  <div v-else>
    <ResourceTable
      ref="resourceTable"
      v-bind="$attrs"
      :headers="headers"
      default-sort-by="age"
      :rows="rows"
      :schema="schema"
      :groupable="true"
      key-field="_key"
    >
      <template #cell:state="scope">
        <div class="state">
          <HarvesterVmState
            class="vmstate"
            :row="scope.row"
          />
        </div>
      </template>

      <template #cell:name="scope">
        <div class="name-console">
          <div class="name-wrap">
            <router-link
              v-if="scope.row.type !== HCI.VMI"
              :to="scope.row.detailLocation"
            >
              {{ scope.row.nameDisplay }}
              <i
                v-if="scope.row.encryptedVolumeType !== 'none'"
                v-tooltip="lockIconTooltipMessage(scope.row)"
                class="icon icon-lock"
                :class="{'green-icon': scope.row.encryptedVolumeType === 'all', 'yellow-icon': scope.row.encryptedVolumeType === 'partial'}"
              />
            </router-link>
            <span v-else>
              {{ scope.row.nameDisplay }}
            </span>
          </div>

          <div class="name-actions">
            <div
              v-if="actionProgressValue(scope.row) !== undefined"
              class="action-progress"
            >
              <PercentageBar
                :model-value="actionProgressValue(scope.row)"
                preferred-direction="MORE"
                class="action-progress-bar"
              />
              <span class="progress-text text-muted">{{ actionProgressValue(scope.row) }}%</span>
            </div>
            <ConsoleBar
              :resource-type="scope.row"
              class="console ml-6 mr-6"
            />
          </div>
        </div>
      </template>
    </ResourceTable>
  </div>
</template>

<style lang="scss">
.growl-container {
  z-index: 56 !important;  // set to be lower than the vm action menu (z-index: 57)
}
</style>

<style lang="scss" scoped>
.state {
  display: flex;

  .vmstate {
    margin-right: 6px;
  }
}

.green-icon {
  color: var(--success);
}

.yellow-icon {
  color: var(--warning);
}

.name-console {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;

  .name-wrap {
    min-width: 0;
    display: flex;
    align-items: center;

    a,
    span {
      overflow: hidden;
      text-overflow: ellipsis;
    }
  }

  .name-actions {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    flex-shrink: 0;
    min-width: 220px;
    gap: 6px;

    .action-progress {
      width: 120px;
      display: flex;
      align-items: center;
      gap: 6px;

      .action-progress-bar {
        flex: 1;
      }

      .progress-text {
        min-width: 36px;
        text-align: right;
        font-size: 12px;
      }
    }
  }

  span {
    padding-right: 4px;
    line-height: 26px;
    white-space: nowrap;
  }
}
</style>
