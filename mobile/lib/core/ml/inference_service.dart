/// Runs a loaded model on an input and returns its raw output. Everything
/// runs on the device.
abstract interface class InferenceService {
  Future<List<double>> run(String model, List<double> input);
}
