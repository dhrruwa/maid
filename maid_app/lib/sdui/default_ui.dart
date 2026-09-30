/// The built-in UI bundle: what every screen shows when the server has sent
/// nothing (first start, offline, no row in app_ui) or sent something unusable.
/// Same shape as a get_ui reply's `ui`; see docs/SDUI.md.
const defaultUi = <String, Object>{
  'screens': {
    'home': {
      'blocks': [
        {'type': 'offline_banner'},
        {'type': 'saved_banner'},
        {'type': 'salary_card'},
        {'type': 'today_card'},
        {'type': 'scan_button'},
        {'type': 'cook_card'},
        {'type': 'week_timeline'},
        {'type': 'more_buttons'},
        {'type': 'app_version'},
      ],
    },
  },
  'strings': <String, Object>{},
};
