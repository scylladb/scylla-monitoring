import defaults from 'lodash/defaults';

import React, { ChangeEvent, PureComponent } from 'react';
import { LegacyForms } from '@grafana/ui';
import { QueryEditorProps } from '@grafana/data';
import { DataSource } from './DataSource';
import { defaultQuery, MyDataSourceOptions, MyQuery } from './types';

const { FormField } = LegacyForms;

type Props = QueryEditorProps<DataSource, MyQuery, MyDataSourceOptions>;

export class QueryEditor extends PureComponent<Props> {
  onQueryTextChange = (event: ChangeEvent<HTMLInputElement>) => {
    const { onChange, query } = this.props;
    onChange({ ...query, queryText: event.target.value });
  };
  onQueryHostChange = (event: ChangeEvent<HTMLInputElement>) => {
    const { onChange, query } = this.props;
    onChange({ ...query, queryHost: event.target.value });
  };
  render() {
    const query = defaults(this.props.query, defaultQuery);
    const { queryText, queryHost } = query;

    return (
      <div className="gf-form">
        <FormField
          labelWidth={8}
          inputWidth={30}
          value={queryText || ''}
          onChange={this.onQueryTextChange}
          label="Query Text"
          tooltip="Enter a CQL query"
        />
        <FormField
          labelWidth={8}
          inputWidth={30}
          value={queryHost || ''}
          onChange={this.onQueryHostChange}
          label="Host"
          tooltip="Optional host"
        />
      </div>
    );
  }
}
