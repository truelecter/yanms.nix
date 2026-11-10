# JVM flag presets for `services.yanms.instances.<name>.jvmOpts` (lists; leave out -Xmx and -Xms).
let
  # Flags for long-running modded servers with plenty of RAM (from the Enigmatica 9 Expert and
  # Vault Hunters setups).
  tuning = [
    "-XX:+UnlockExperimentalVMOptions"
    "-XX:+UnlockDiagnosticVMOptions"
    "-XX:+AlwaysActAsServerClassMachine"
    "-XX:+AlwaysPreTouch"
    "-XX:+DisableExplicitGC"
    "-XX:+UseNUMA"
    "-XX:NmethodSweepActivity=1"
    "-XX:ReservedCodeCacheSize=400M"
    "-XX:NonNMethodCodeHeapSize=12M"
    "-XX:ProfiledCodeHeapSize=194M"
    "-XX:NonProfiledCodeHeapSize=194M"
    "-XX:-DontCompileHugeMethods"
    "-XX:MaxNodeLimit=240000"
    "-XX:NodeLimitFudgeFactor=8000"
    "-XX:+UseVectorCmov"
    "-XX:+PerfDisableSharedMem"
    "-XX:+UseFastUnorderedTimeStamps"
    "-XX:+UseCriticalJavaThreadPriority"
    "-XX:ThreadPriorityPolicy=1"
    "-XX:AllocatePrefetchStyle=3"
  ];
in {
  inherit tuning;

  # ZGC, Java 17.
  zgc =
    tuning
    ++ [
      "-XX:+UseZGC"
      "-XX:AllocatePrefetchStyle=1"
      "-XX:-ZProactive"
      "-XX:ConcGCThreads=2"
    ];

  # Generational ZGC, Java 21.
  zgcGenerational =
    tuning
    ++ [
      "-XX:+UseZGC"
      "-XX:+ZGenerational"
      "-XX:-ZUncommit"
      "-XX:+ParallelRefProcEnabled"
      "-XX:-OmitStackTraceInFastThrow"
      "-XX:+UseStringDeduplication"
      "-XX:ConcGCThreads=4"
      "-XX:+UseTransparentHugePages"
    ];
}
