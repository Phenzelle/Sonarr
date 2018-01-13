import { connect } from 'react-redux';
import { createSelector } from 'reselect';
import * as seriesEditorActions from 'Store/Actions/seriesEditorActions';
import FilterModal from 'Components/Filter/FilterModal';

function createMapStateToProps() {
  return createSelector(
    (state) => state.series.items,
    (state) => state.seriesEditor.filterBuilderProps,
    (sectionItems, filterBuilderProps) => {
      return {
        sectionItems,
        filterBuilderProps
      };
    }
  );
}

function createMapDispatchToProps(dispatch, props) {
  return {
    onRemoveCustomFilterPress(payload) {
      dispatch(seriesEditorActions.removeSeriesEditorCustomFilter(payload));
    },

    onSaveCustomFilterPress(payload) {
      dispatch(seriesEditorActions.saveSeriesEditorCustomFilter(payload));
    }
  };
}

export default connect(createMapStateToProps, createMapDispatchToProps)(FilterModal);
