<script>
import { mapGetters } from 'vuex';
import { exceptionToErrorsArray } from '@shell/utils/error';
import { Card } from '@components/Card';
import { Banner } from '@components/Banner';
import AsyncButton from '@shell/components/AsyncButton';
import { LabeledInput } from '@components/Form/LabeledInput';
export default {
  name: 'HarvesterEditReplicasDialog',

  emits: ['close'],

  components: {
    AsyncButton, Banner, Card, LabeledInput
  },
  props: {
    resources: {
      type:     Array,
      required: true
    }
  },
  data() {
    return {
      count:   3,
      errors: []
    };
  },
  computed: {
    ...mapGetters({ t: 'i18n/t' }),
    actionResource() {
      return this.resources[0];
    },
    // disableSave() {
    //   return !this.count;
    // }
  },
  methods: {
    close() {
      this.name = '';
      this.$emit('close');
    },
    async save(buttonCb) {
      console.log('this.actionResource=', this.actionResource);
      try {
        const data = {
          replicaCount: Number(this.count)
        };
        const host = window.location.host;
        const volumePVCName = `pvc-${this.actionResource.metadata.uid}`;
        const url = `https://${ host }/k8s/clusters/local/api/v1/namespaces/longhorn-system/services/http:longhorn-frontend:80/proxy/v1/volumes/${ volumePVCName }?action=updateReplicaCount`;

        const res = await this.$store.dispatch('harvester/request', {
          url,
          method: 'POST',
          data,
        });

        console.log("🚀 ~ res:", res)

        if (res._status === 200 || res._status === 204) {
          const volumeName = this.actionResource.metadata.name;
          this.$store.dispatch('growl/success', {
            title:   this.t('harvester.notification.title.succeed'),
            message: this.t('harvester.modal.editReplicas.message.success', { name: volumeName })
          }, { root: true });
          this.close();
          buttonCb(true);
        } else {
          const error = [res?.data] || exceptionToErrorsArray(res);

          this['errors'] = error;
          buttonCb(false);
        }
      } catch (err) {
        const error = err?.data || err;
        const message = exceptionToErrorsArray(error);

        this['errors'] = message;
        buttonCb(false);
      }
    }
  },
};
</script>
<template>
  <Card :show-highlight-border="false">
    <template #title>
      {{ t('harvester.modal.editReplicas.title') }}
    </template>

    <template #body>
      <LabeledInput
        type="number"
        :mode="mode"
        :min="0"
        v-model:value="count"
        :label="t('harvester.modal.editReplicas.name')"
        required
      />
      <Banner
        v-for="(err, i) in errors"
        :key="i"
        color="error"
        :label="err"
      />
    </template>

    <template #actions>
      <div class="actions">
        <div class="buttons">
          <button
            class="btn role-secondary mr-10"
            @click="close"
          >
            {{ t('generic.cancel') }}
          </button>
          <AsyncButton
            mode="create"
            @click="save"
          />
        </div>
      </div>
    </template>
  </Card>
</template>
<style lang="scss" scoped>
.actions {
  width: 100%;
}
.buttons {
  display: flex;
  justify-content: flex-end;
  width: 100%;
}
</style>
