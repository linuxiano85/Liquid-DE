import 'package:minervad/services/fucina/sicurezza_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('perdere una mitigazione o un hardening è una regressione', () {
    expect(
      protezioniPerse(
        {'MITIGATION_MDS': 'y', 'FORTIFY_SOURCE': 'y'},
        {'MITIGATION_MDS': 'n'},
      ),
      unorderedEquals(['MITIGATION_MDS', 'FORTIFY_SOURCE']),
    );
  });
  test('mantenere o aggiungere protezioni non è una regressione', () {
    expect(
      protezioniPerse(
        {'STACKPROTECTOR_STRONG': 'y'},
        {'STACKPROTECTOR_STRONG': 'y', 'FORTIFY_SOURCE': 'y'},
      ),
      isEmpty,
    );
  });
  test('debug, flag del compilatore e chiavi non sono mitigazioni', () {
    expect(
      protezioniAttive({
        'DEBUG_INFO_BTF': 'y',
        'CC_IS_GCC': 'y',
        'MODULE_SIG_KEY': '"private"',
        'FORTIFY_SOURCE': 'y',
      }),
      ['FORTIFY_SOURCE'],
    );
  });
}
