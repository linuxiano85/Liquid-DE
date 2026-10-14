/// Protezioni da preservare durante lo snellimento. Non comprende funzioni
/// di debug, driver, ottimizzazioni del compilatore o policy LSM inattive.
bool protezioneKernel(String simbolo) =>
    simbolo.startsWith('MITIGATION_') ||
    const {
      'CPU_MITIGATIONS',
      'SPECULATION_MITIGATIONS',
      'PAGE_TABLE_ISOLATION',
      'RETPOLINE',
      'STACKPROTECTOR',
      'STACKPROTECTOR_STRONG',
      'FORTIFY_SOURCE',
      'HARDENED_USERCOPY',
      'HARDENED_USERCOPY_DEFAULT_ON',
      'SLAB_FREELIST_RANDOM',
      'SLAB_FREELIST_HARDENED',
      'RANDOMIZE_BASE',
      'RANDOMIZE_MEMORY',
      'RANDOMIZE_KSTACK_OFFSET',
      'RANDOMIZE_KSTACK_OFFSET_DEFAULT',
      'INIT_ON_ALLOC_DEFAULT_ON',
      'INIT_ON_FREE_DEFAULT_ON',
      'STRICT_KERNEL_RWX',
      'STRICT_MODULE_RWX',
      'VMAP_STACK',
      'SECCOMP',
      'SECCOMP_FILTER',
      'MODULE_SIG',
      'MODULE_SIG_FORCE',
      'MODULE_SIG_ALL',
      'SECURITY',
      'SECURITY_DMESG_RESTRICT',
    }.contains(simbolo);

/// Solo simboli verificabili, mai stringhe di percorsi o chiavi private.
List<String> protezioniAttive(Map<String, String> config) => [
  for (final e in config.entries)
    if (e.value == 'y' && protezioneKernel(e.key)) e.key,
]..sort();

List<String> protezioniPerse(
  Map<String, String> prima,
  Map<String, String> dopo,
) => [
  for (final s in protezioniAttive(prima))
    if (dopo[s] != 'y') s,
];
