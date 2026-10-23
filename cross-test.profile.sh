# Sourced more than once; keep top-level settings idempotent.

# No linkage override: the harness builds the package's default static graph.
# Run package tests for each target, not the compile-only check step.
CROSS_BUILD_STEP=test

CROSS_BUILD_TIMEOUT=3600

# Per-test-case time limit.
CROSS_TIMEOUT=1800