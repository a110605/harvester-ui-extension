<script>
import merge from 'lodash/merge';
import jsyaml from 'js-yaml';
import { mapGetters } from 'vuex';
import { Card } from '@components/Card';
import { LabeledInput } from '@components/Form/LabeledInput';
import AsyncButton from '@shell/components/AsyncButton';
import { escapeHtml } from '@shell/utils/string';

const DEFAULT_VALUE = {
  image:          { repository: 'rancher/harvester-nvidia-driver-toolkit', tag: '' },
  driverLocation: '',
};

export default {
  name: 'HarvesterEnableNvidiaDriverToolkit',

  emits: ['close'],

  components: {
    AsyncButton,
    Card,
    LabeledInput,
  },

  props: {
    resources: {
      type:     Array,
      required: true,
    },
  },

  data() {
    const parsed = this.parseValuesContent(this.resources[0]);

    return {
      imageRepository: parsed.image?.repository || DEFAULT_VALUE.image.repository,
      imageTag:        parsed.image?.tag || DEFAULT_VALUE.image.tag,
      driverLocation:  parsed.driverLocation || DEFAULT_VALUE.driverLocation,
    };
  },

  computed: {
    ...mapGetters({ t: 'i18n/t' }),

    isValid() {
      return !!this.imageRepository;
    },
  },

  methods: {
    parseValuesContent(addon) {
      try {
        return merge({}, DEFAULT_VALUE, jsyaml.load(addon.spec.valuesContent));
      } catch (e) {
        return { ...DEFAULT_VALUE };
      }
    },

    close() {
      this.$emit('close');
    },

    async save(buttonCb) {
      const addon = this.resources[0];

      try {
        const values = {
          image: {
            repository: this.imageRepository,
            tag:        this.imageTag,
          },
          driverLocation: this.driverLocation,
        };

        addon.spec.valuesContent = jsyaml.dump(values);
        addon.spec.enabled = true;

        await addon.save();
        buttonCb(true);
        this.close();
      } catch (err) {
        addon.spec.enabled = false;
        this.$store.dispatch('growl/fromError', {
          title: this.t('generic.notification.title.error', { name: escapeHtml(addon.metadata.name) }),
          err,
        }, { root: true });
        buttonCb(false);
      }
    },
  },
};
</script>

<template>
  <Card :show-highlight-border="false">
    <template #title>
      <h4
        v-clean-html="t('harvester.addons.nvidiaDriverToolkit.titles.enable')"
        class="text-default-text"
      />
    </template>

    <template #body>
      <div class="body">
        <div class="row mb-15">
          <div class="col span-6">
            <LabeledInput
              v-model:value="imageRepository"
              :required="true"
              label-key="harvester.addons.nvidiaDriverToolkit.image.repository"
            />
          </div>
          <div class="col span-6">
            <LabeledInput
              v-model:value="imageTag"
              label-key="harvester.addons.nvidiaDriverToolkit.image.tag"
            />
          </div>
        </div>
        <div class="row mb-15">
          <div class="col span-12">
            <LabeledInput
              v-model:value="driverLocation"
              label-key="harvester.addons.nvidiaDriverToolkit.driver.location"
            />
          </div>
        </div>
      </div>
    </template>

    <template #actions>
      <div class="buttons actions">
        <button
          class="btn role-secondary mr-10"
          @click="close"
        >
          {{ t('generic.cancel') }}
        </button>

        <AsyncButton
          mode="enable"
          :disabled="!isValid"
          @click="save"
        />
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
