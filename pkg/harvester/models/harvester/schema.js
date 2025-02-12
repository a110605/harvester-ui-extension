import SteveSchema from '@shell/models/steve-schema';

/**
 * This is the steve schema that's used for the harvester store
 */
export default class HarvesterStoreSchema extends SteveSchema {
  constructor(...args) {
    console.log('HarvesterStoreSchema constructor args:', args);
    if (args[0].type === 'type of resource that throws error') {
      debugger;
    }
    super(...args);
  }
 }
