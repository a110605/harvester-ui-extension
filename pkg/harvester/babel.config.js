const shellBabelConfig = require('@rancher/shell/pkg/babel.config');

module.exports = {
  ...shellBabelConfig,
  plugins: [
    '@babel/plugin-transform-class-static-block'
  ]
};
