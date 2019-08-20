import angular from 'angular';
// @ts-ignore
import $ from 'jquery';
//import './lib/jquery.flot.pie';

//import 'jquery.flot';

import './lib/jquery.flot.time';

import _ from 'lodash';

// @ts-ignore
import PerfectScrollbar from './lib/perfect-scrollbar.min';

angular.module('grafana.directives').directive('piechartLegend', (popoverSrv: any, $timeout: any) => {
  return {
    link: (scope: any, elem: any) => {
      const $container = $('<div class="piechart-legend__container"></div>');
      let firstRender = true;
      const ctrl = scope.ctrl;
      const panel = ctrl.panel;
      let data: any;
      let seriesList: any;
      let dataList: any;
      let i;
      let legendScrollbar: any;

      scope.$on('$destroy', () => {
        if (legendScrollbar) {
          legendScrollbar.destroy();
        }
      });

      ctrl.events.on('render', () => {
        data = ctrl.series;
        if (data) {
          for (const i in data) {
            data[i].color = ctrl.data[i].color;
          }
          render();
        }
      });

      function getSeriesIndexForElement(el: any) {
        return el.parents('[data-series-index]').data('series-index');
      }

      function toggleSeries(e: any) {
        const el = $(e.currentTarget);
        const index = getSeriesIndexForElement(el);
        const seriesInfo = dataList[index];
        const scrollPosition = $($container.children('tbody')).scrollTop();
        ctrl.toggleSeries(seriesInfo);
        if (typeof scrollPosition !== 'undefined') {
          $($container.children('tbody')).scrollTop(scrollPosition);
        }
      }

      function sortLegend(e: any) {
        const el = $(e.currentTarget);
        const stat = el.data('stat');

        if (stat !== panel.legend.sort) {
          panel.legend.sortDesc = null;
        }

        // if already sort ascending, disable sorting
        if (panel.legend.sortDesc === false) {
          panel.legend.sort = null;
          panel.legend.sortDesc = null;
          ctrl.render();
          return;
        }

        panel.legend.sortDesc = !panel.legend.sortDesc;
        panel.legend.sort = stat;
        ctrl.render();
      }

      function getLegendHeaderHtml(statName: any) {
        let name = statName;

        if (panel.legend.header) {
          name = panel.legend.header;
        }

        let html = '<th class="pointer" data-stat="' + _.escape(statName) + '">' + name;

        if (panel.legend.sort === statName) {
          const cssClass = panel.legend.sortDesc ? 'fa fa-caret-down' : 'fa fa-caret-up';
          html += ' <span class="' + cssClass + '"></span>';
        }

        return html + '</th>';
      }

      function getLegendPercentageHtml(statName: any) {
        const name = 'percentage';
        let html = '<th class="pointer" data-stat="' + statName + '">' + name;

        if (panel.legend.sort === statName) {
          const cssClass = panel.legend.sortDesc ? 'fa fa-caret-down' : 'fa fa-caret-up';
          html += ' <span class="' + cssClass + '"></span>';
        }

        return html + '</th>';
      }

      function openColorSelector(e: any) {
        // if we clicked inside poup container ignore click
        if ($(e.target).parents('.popover').length) {
          return;
        }

        const el = $(e.currentTarget).find('.fa-minus');
        const index = getSeriesIndexForElement(el);
        const series = seriesList[index];

        $timeout(() => {
          popoverSrv.show({
            element: el[0],
            position: 'right center',
            template:
              '<series-color-picker-popover series="series" onToggleAxis="toggleAxis" onColorChange="colorSelected">' +
              '</series-color-picker-popover>',
            openOn: 'hover',
            classNames: 'drop-popover drop-popover--transparent',
            model: {
              autoClose: true,
              series: series,
              toggleAxis: () => {},
              colorSelected: (color: any) => {
                ctrl.changeSeriesColor(series, color);
              },
            },
          });
        });
      }

      function render() {
        if (panel.legendType === 'On graph' || !panel.legend.show) {
          $container.empty();
          elem.find('.piechart-legend').css('padding-top', 0);
          return;
        } else {
          elem.find('.piechart-legend').css('padding-top', 6);
        }

        if (firstRender) {
          elem.append($container);
          $container.on('click', '.piechart-legend-icon', openColorSelector);
          $container.on('click', '.piechart-legend-alias', toggleSeries);
          $container.on('click', 'th', sortLegend);
          firstRender = false;
        }

        seriesList = data;
        dataList = ctrl.data;

        $container.empty();

        const width = panel.legendType === 'Right side' && panel.legend.sideWidth ? panel.legend.sideWidth + 'px' : '';
        const ieWidth = panel.legendType === 'Right side' && panel.legend.sideWidth ? panel.legend.sideWidth - 1 + 'px' : '';
        elem.css('min-width', width);
        elem.css('width', ieWidth);

        const showValues = panel.legend.values || panel.legend.percentage;
        const tableLayout = (panel.legendType === 'Under graph' || panel.legendType === 'Right side') && showValues;

        $container.toggleClass('piechart-legend-table', tableLayout);

        let legendHeader;
        if (tableLayout) {
          let header = '<tr><th colspan="2" style="text-align:left"></th>';
          if (panel.legend.values) {
            header += getLegendHeaderHtml(ctrl.panel.valueName);
          }
          if (panel.legend.percentage) {
            header += getLegendPercentageHtml(ctrl.panel.valueName);
          }
          header += '</tr>';
          legendHeader = $(header);
        }

        let total = 0;
        if (panel.legend.percentage) {
          for (i = 0; i < seriesList.length; i++) {
            total += seriesList[i].stats[ctrl.panel.valueName];
          }
        }

        //let seriesShown = 0;
        const seriesElements = [];

        for (i = 0; i < seriesList.length; i++) {
          const series = seriesList[i];
          const seriesData = dataList[i];

          // ignore empty series
          if (panel.legend.hideEmpty && series.allIsNull) {
            continue;
          }
          // ignore series excluded via override
          if (!series.legend) {
            continue;
          }

          let decimal = 0;
          if (ctrl.panel.legend.percentageDecimals) {
            decimal = ctrl.panel.legend.percentageDecimals;
          }

          let html = '<div class="piechart-legend-series';
          if (ctrl.hiddenSeries[seriesData.label]) {
            html += ' piechart-legend-series-hidden';
          }
          html += '" data-series-index="' + i + '">';
          html += '<span class="piechart-legend-icon" style="float:none;">';
          html += '<i class="fa fa-minus pointer" style="color:' + seriesData.color + '"></i>';
          html += '</span>';

          html += '<a class="piechart-legend-alias" style="float:none;">' + _.escape(seriesData.label) + '</a>';

          if (showValues && tableLayout) {
            const value = seriesData.legendData;
            if (panel.legend.values) {
              html += '<div class="piechart-legend-value">' + ctrl.formatValue(value) + '</div>';
            }
            if (total) {
              const pvalue = ((value / total) * 100).toFixed(decimal) + '%';
              html += '<div class="piechart-legend-value">' + pvalue + '</div>';
            }
          }

          html += '</div>';

          seriesElements.push($(html));
          //seriesShown++;
        }
        if (tableLayout) {
          // const topPadding = 6;
          const tbodyElem = $('<tbody></tbody>');
          // tbodyElem.css("max-height", maxHeight - topPadding);
          if (typeof legendHeader !== 'undefined') {
            tbodyElem.append(legendHeader);
          }
          tbodyElem.append(seriesElements);
          $container.append(tbodyElem);
        } else {
          $container.append(seriesElements);
        }

        if (panel.legendType === 'Under graph') {
          addScrollbar();
        } else {
          destroyScrollbar();
        }
      }
      function addScrollbar() {
        const scrollbarOptions = {
          // Number of pixels the content height can surpass the container height without enabling the scroll bar.
          scrollYMarginOffset: 2,
          suppressScrollX: true,
        };

        if (!legendScrollbar) {
          legendScrollbar = new PerfectScrollbar(elem[0], scrollbarOptions);
        } else {
          legendScrollbar.update();
        }
      }

      function destroyScrollbar() {
        if (legendScrollbar) {
          legendScrollbar.destroy();
          legendScrollbar = null;
        }
      }
    },
  };
});
