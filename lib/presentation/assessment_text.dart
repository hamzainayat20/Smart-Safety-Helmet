/// Plain-language explanations for AI assessment reason codes
/// (FR-AI-09, NFR-AI-08). Unknown codes fall back to a readable form of the
/// code itself rather than being hidden.
const Map<String, String> _reasonText = {
  'FALL_DETECTED': 'The motion model detected a fall pattern.',
  'FALL_MODEL_UNAVAILABLE': 'The fall model was unavailable for this reading.',
  'GAS_INPUT_OUT_OF_DISTRIBUTION':
      'Gas readings are outside the range the model was validated on.',
  'GAS_MIXTURE': 'The gas model classified the air as a gas mixture.',
  'GAS_MODEL_UNAVAILABLE': 'The gas model was unavailable for this reading.',
  'GAS_NO_GAS': 'The gas model did not detect a hazardous gas.',
  'GAS_PERFUME': 'The gas model classified the air as a scented vapour.',
  'GAS_SENSOR_WARMING':
      'The gas sensor is still warming up, so gas results are excluded.',
  'GAS_SMOKE': 'The gas model classified the air as smoke.',
  'HEAT_INDEX_WARNING': 'The heat index is above the warning limit.',
  'HEAT_INDEX_CRITICAL': 'The heat index is above the critical limit.',
  'HUMIDITY_WARNING': 'Humidity is outside the normal range.',
  'HUMIDITY_CRITICAL': 'Humidity is outside the safe range.',
  'TEMPERATURE_WARNING': 'Temperature is above the warning limit.',
  'TEMPERATURE_CRITICAL': 'Temperature is above the critical limit.',
  'SENSOR_FAULT':
      'A sensor fault was reported; affected values are not treated as safe.',
};

String describeReasonCode(String code) {
  final known = _reasonText[code];
  if (known != null) return known;
  final words = code.toLowerCase().split('_').where((w) => w.isNotEmpty);
  final text = words.join(' ');
  if (text.isEmpty) return 'Unspecified reason.';
  return '${text[0].toUpperCase()}${text.substring(1)}.';
}
