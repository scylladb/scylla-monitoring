import { PieChartCtrl } from './piechart_ctrl';
import { loadPluginCss } from 'grafana/app/plugins/sdk';

loadPluginCss({
  dark: 'plugins/grafana-piechart-panel/styles/dark.css',
  light: 'plugins/grafana-piechart-panel/styles/light.css',
});

export { PieChartCtrl as PanelCtrl };
